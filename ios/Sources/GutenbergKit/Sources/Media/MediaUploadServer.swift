import Foundation
import Network
import OSLog
import UniformTypeIdentifiers

/// A lightweight local HTTP server that receives file uploads from the WebView
/// and routes them through the native media processing pipeline.
///
/// The server binds to `127.0.0.1` on a random available port and validates
/// all requests using a per-session Bearer token. It handles:
/// - `OPTIONS` preflight requests (CORS)
/// - `POST /upload` multipart form-data uploads
///
/// Lifecycle is tied to `EditorViewController` — start when the editor loads,
/// stop on deinit.
final class MediaUploadServer: Sendable {

  /// The port the server is listening on, available after `start()`.
  let port: UInt16

  /// Per-session auth token for validating incoming requests.
  let token: String

  private let listener: NWListener
  private let queue = DispatchQueue(label: "com.gutenbergkit.upload-server")
  private let uploadDelegate: (any MediaUploadDelegate)?
  private let defaultUploader: DefaultMediaUploader?

  /// Creates a new upload server.
  ///
  /// - Parameters:
  ///   - uploadDelegate: Optional delegate for customizing file processing and upload.
  ///   - defaultUploader: Fallback uploader used when no delegate provides `uploadFile`.
  init(
    uploadDelegate: (any MediaUploadDelegate)? = nil,
    defaultUploader: DefaultMediaUploader? = nil
  ) throws {
    self.token = UUID().uuidString
    self.uploadDelegate = uploadDelegate
    self.defaultUploader = defaultUploader

    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)

    let listener = try NWListener(using: parameters)
    self.listener = listener

    // Determine the assigned port by starting synchronously enough to read it.
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var assignedPort: UInt16 = 0

    // newConnectionHandler must be set before start(). Since we can't
    // reference `self` yet (port isn't assigned), use a box that we fill
    // once init completes. There is a brief window between listener.start()
    // and `serverRef = self` where incoming connections would be silently
    // dropped (serverRef is nil). In practice this is negligible because
    // the JS layer only sends requests after the editor loads, well after
    // init returns.
    nonisolated(unsafe) var serverRef: MediaUploadServer?

    listener.newConnectionHandler = { connection in
      serverRef?.handleConnection(connection)
    }

    listener.stateUpdateHandler = { state in
      switch state {
      case .ready:
        if let port = listener.port {
          assignedPort = port.rawValue
        }
        semaphore.signal()
      case .failed(let error):
        Logger.uploadServer.error("Listener failed: \(error)")
        semaphore.signal()
      case .cancelled:
        semaphore.signal()
      case .waiting(let error):
        // Transient state — the listener may still transition to .ready.
        Logger.uploadServer.info("Listener waiting for network path: \(error)")
      default:
        break
      }
    }

    listener.start(queue: queue)
    // Allow up to 3 seconds for the listener to become ready.
    _ = semaphore.wait(timeout: .now() + 3)

    guard assignedPort != 0 else {
      throw ServerError.failedToStart
    }

    self.port = assignedPort
    serverRef = self

    Logger.uploadServer.info("Upload server started on port \(assignedPort)")
  }

  /// Stops the server and releases resources.
  func stop() {
    listener.cancel()
    Logger.uploadServer.info("Upload server stopped")
  }

  deinit {
    listener.cancel()
  }

  // MARK: - Connection Handling

  private func handleConnection(_ connection: NWConnection) {
    connection.start(queue: queue)

    receiveAllData(on: connection) { [weak self] data in
      guard let self, let data else {
        connection.cancel()
        return
      }

      Task {
        let response = await self.handleRequest(data)
        connection.send(content: response, completion: .contentProcessed { _ in
          connection.cancel()
        })
      }
    }
  }

  /// Accumulates all data from a connection until the request is complete.
  private func receiveAllData(on connection: NWConnection, completion: @escaping @Sendable (Data?) -> Void) {
    // Buffer is only accessed serially on the NWConnection's queue callback chain,
    // but Swift concurrency can't prove this statically.
    nonisolated(unsafe) var buffer = Data()

    @Sendable func receiveChunk() {
      connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
        if let content {
          buffer.append(content)
        }

        if isComplete || error != nil {
          completion(buffer.isEmpty ? nil : buffer)
        } else {
          // Check if we have a complete HTTP request (Content-Length based).
          if self.isRequestComplete(buffer) {
            completion(buffer)
          } else {
            receiveChunk()
          }
        }
      }
    }

    receiveChunk()
  }

  /// Checks whether the accumulated buffer contains a complete HTTP request.
  private func isRequestComplete(_ data: Data) -> Bool {
    guard let headerEndRange = data.range(of: Data("\r\n\r\n".utf8)) else {
      return false
    }

    guard let headers = String(data: data[data.startIndex..<headerEndRange.lowerBound], encoding: .utf8) else {
      return false
    }

    let headerLines = headers.split(separator: "\r\n")

    // Check for Content-Length header
    if let contentLengthLine = headerLines.first(where: { $0.lowercased().hasPrefix("content-length:") }) {
      let contentLength = Int(contentLengthLine.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "0") ?? 0
      let bodyLength = data.count - headerEndRange.upperBound
      return bodyLength >= contentLength
    }

    // Chunked transfer encoding: the last chunk is "0\r\n\r\n" (or "0\r\n" + trailers + "\r\n").
    // Check if the data ends with the final chunk terminator.
    if headerLines.contains(where: { $0.lowercased().contains("transfer-encoding:") && $0.lowercased().contains("chunked") }) {
      let finalChunk = Data("\r\n0\r\n\r\n".utf8)
      return data.hasSuffix(finalChunk)
    }

    // No Content-Length and not chunked — for methods that shouldn't have a body
    // (OPTIONS, GET), headers alone are sufficient. For POST, we can't determine
    // completeness without Content-Length, so rely on connection close.
    let requestLine = headerLines.first ?? ""
    if requestLine.hasPrefix("POST") || requestLine.hasPrefix("PUT") {
      return false
    }

    return true
  }

  // MARK: - Request Handling

  private func handleRequest(_ data: Data) async -> Data {
    guard let request = HTTPRequest(data: data) else {
      return makeResponse(status: 400, statusText: "Bad Request", body: "Malformed HTTP request")
    }

    // CORS preflight
    if request.method == "OPTIONS" {
      return makeCORSResponse()
    }

    // Auth validation
    let expectedAuth = "Bearer \(token)"
    guard request.headers["authorization"] == expectedAuth else {
      return makeResponse(status: 401, statusText: "Unauthorized", body: "Invalid or missing token")
    }

    // Route
    guard request.method == "POST", request.path == "/upload" else {
      return makeResponse(status: 404, statusText: "Not Found", body: "Not found")
    }

    return await handleUpload(request)
  }

  private func handleUpload(_ request: HTTPRequest) async -> Data {
    guard let contentType = request.headers["content-type"],
          contentType.contains("multipart/form-data"),
          let boundary = extractBoundary(from: contentType) else {
      return makeResponse(status: 400, statusText: "Bad Request", body: "Expected multipart/form-data")
    }

    guard let file = parseMultipartFile(data: request.body, boundary: boundary) else {
      Logger.uploadServer.error("Multipart parse failed. Body size: \(request.body.count), boundary: \(boundary)")
      return makeResponse(status: 400, statusText: "Bad Request", body: "No file found in request")
    }

    // Write file to temp directory
    let tempDir = FileManager.default.temporaryDirectory
      .appending(component: "GutenbergKit-uploads", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let fileURL = tempDir.appending(component: "\(UUID().uuidString)-\(file.filename)")
    do {
      try file.data.write(to: fileURL)
    } catch {
      Logger.uploadServer.error("Failed to write upload to disk: \(error)")
      return makeResponse(status: 500, statusText: "Internal Server Error", body: "Failed to save file")
    }

    // Process the file and upload to the remote WordPress server.
    let result: Result<MediaUploadResult, Error>
    do {
      let media = try await processAndUpload(fileURL: fileURL, mimeType: file.mimeType, filename: file.filename)
      result = .success(media)
    } catch {
      result = .failure(error)
    }

    switch result {
    case .success(let media):
      do {
        let json = try JSONEncoder().encode(media)
        return makeResponse(status: 200, statusText: "OK", body: json, contentType: "application/json")
      } catch {
        return makeResponse(status: 500, statusText: "Internal Server Error", body: "Failed to encode response")
      }
    case .failure(let error):
      Logger.uploadServer.error("Upload processing failed: \(error)")
      return makeResponse(status: 500, statusText: "Internal Server Error", body: error.localizedDescription)
    }
  }

  private func processAndUpload(fileURL: URL, mimeType: String, filename: String) async throws -> MediaUploadResult {
    // Step 1: Process (resize, transcode, etc.)
    let processedURL: URL
    if let delegate = uploadDelegate {
      processedURL = try await delegate.processFile(at: fileURL, mimeType: mimeType)
    } else {
      processedURL = fileURL
    }

    // Step 2: Upload to remote WordPress
    if let delegate = uploadDelegate,
       let result = try await delegate.uploadFile(at: processedURL, mimeType: mimeType, filename: filename) {
      return result
    } else if let defaultUploader {
      return try await defaultUploader.upload(fileURL: processedURL, mimeType: mimeType, filename: filename)
    } else {
      throw ServerError.noUploader
    }
  }

  // MARK: - HTTP Response Building

  private func makeCORSResponse() -> Data {
    let headers = [
      "Access-Control-Allow-Origin: *",
      "Access-Control-Allow-Methods: POST, OPTIONS",
      "Access-Control-Allow-Headers: Authorization, Content-Type",
      "Access-Control-Max-Age: 86400",
      "Content-Length: 0",
    ].joined(separator: "\r\n")

    return "HTTP/1.1 204 No Content\r\n\(headers)\r\n\r\n".data(using: .utf8)!
  }

  private func makeResponse(status: Int, statusText: String, body: String) -> Data {
    makeResponse(status: status, statusText: statusText, body: body.data(using: .utf8)!, contentType: "text/plain")
  }

  private func makeResponse(status: Int, statusText: String, body: Data, contentType: String) -> Data {
    let headers = [
      "Access-Control-Allow-Origin: *",
      "Access-Control-Allow-Headers: Authorization, Content-Type",
      "Content-Type: \(contentType)",
      "Content-Length: \(body.count)",
    ].joined(separator: "\r\n")

    var response = "HTTP/1.1 \(status) \(statusText)\r\n\(headers)\r\n\r\n".data(using: .utf8)!
    response.append(body)
    return response
  }

  // MARK: - Multipart Parsing

  private func extractBoundary(from contentType: String) -> String? {
    guard let range = contentType.range(of: "boundary=") else { return nil }
    var boundary = String(contentType[range.upperBound...])
    // Remove quotes if present
    if boundary.hasPrefix("\"") && boundary.hasSuffix("\"") {
      boundary = String(boundary.dropFirst().dropLast())
    }
    // Remove trailing parameters
    if let semiIndex = boundary.firstIndex(of: ";") {
      boundary = String(boundary[..<semiIndex])
    }
    return boundary
  }

  private struct UploadedFile {
    let filename: String
    let mimeType: String
    let data: Data
  }

  private func parseMultipartFile(data: Data, boundary: String) -> UploadedFile? {
    let boundaryData = "--\(boundary)".data(using: .utf8)!
    let doubleCRLF = "\r\n\r\n".data(using: .utf8)!

    // Find all boundary start positions (where each `--boundary` begins)
    var boundaryStarts: [Data.Index] = []
    var searchStart = data.startIndex
    while searchStart < data.endIndex,
          let range = data.range(of: boundaryData, in: searchStart..<data.endIndex) {
      boundaryStarts.append(range.lowerBound)
      searchStart = range.upperBound
    }

    guard boundaryStarts.count >= 2 else { return nil }

    // Each part is between consecutive boundaries.
    // Part content starts after `--boundary\r\n` and ends before `\r\n--boundary`.
    for i in 0..<boundaryStarts.count - 1 {
      let partStart = data.index(boundaryStarts[i], offsetBy: boundaryData.count)
      let partEnd = boundaryStarts[i + 1]

      guard partStart < partEnd else { continue }
      var part = data[partStart..<partEnd]

      // Strip leading \r\n after boundary line
      let crlf = Data("\r\n".utf8)
      if part.prefix(crlf.count) == crlf {
        part = part.dropFirst(crlf.count)
      }
      // Strip trailing \r\n before next boundary
      if part.suffix(crlf.count) == crlf {
        part = part.dropLast(crlf.count)
      }

      guard let headerEnd = part.range(of: doubleCRLF) else { continue }

      let headerData = part[part.startIndex..<headerEnd.lowerBound]
      guard let headers = String(data: headerData, encoding: .utf8) else { continue }

      guard headers.contains("filename=") else { continue }

      let filename = extractHeaderValue(from: headers, key: "filename") ?? "upload"
      let mimeType = extractContentType(from: headers) ?? "application/octet-stream"

      let bodyData = part[headerEnd.upperBound...]
      return UploadedFile(filename: filename, mimeType: mimeType, data: Data(bodyData))
    }

    return nil
  }

  private func extractHeaderValue(from headers: String, key: String) -> String? {
    guard let range = headers.range(of: "\(key)=\"") else { return nil }
    let afterKey = headers[range.upperBound...]
    guard let endQuote = afterKey.firstIndex(of: "\"") else { return nil }
    return String(afterKey[..<endQuote])
  }

  private func extractContentType(from headers: String) -> String? {
    for line in headers.split(separator: "\r\n") {
      if line.lowercased().hasPrefix("content-type:") {
        return line.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces)
      }
    }
    return nil
  }

  // MARK: - Errors

  enum ServerError: Error, LocalizedError {
    case failedToStart
    case noUploader

    var errorDescription: String? {
      switch self {
      case .failedToStart: "Failed to start upload server"
      case .noUploader: "No upload delegate or default uploader configured"
      }
    }
  }
}

// MARK: - HTTP Request Parsing

private struct HTTPRequest {
  let method: String
  let path: String
  let headers: [String: String]
  let body: Data

  init?(data: Data) {
    // Search for the header/body separator in raw bytes so that binary body
    // content (e.g. JPEG data) doesn't cause a UTF-8 decode failure.
    let separator = Data("\r\n\r\n".utf8)
    guard let separatorRange = data.range(of: separator) else {
      return nil
    }

    let headerData = data[data.startIndex..<separatorRange.lowerBound]
    guard let headerSection = String(data: headerData, encoding: .utf8) else {
      return nil
    }

    let lines = headerSection.split(separator: "\r\n", omittingEmptySubsequences: false)

    guard let requestLine = lines.first else { return nil }
    let parts = requestLine.split(separator: " ")
    guard parts.count >= 2 else { return nil }

    self.method = String(parts[0])
    self.path = String(parts[1])

    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
      let headerParts = line.split(separator: ":", maxSplits: 1)
      if headerParts.count == 2 {
        headers[headerParts[0].trimmingCharacters(in: .whitespaces).lowercased()] =
          headerParts[1].trimmingCharacters(in: .whitespaces)
      }
    }
    self.headers = headers

    let rawBody: Data
    if separatorRange.upperBound < data.endIndex {
      rawBody = Data(data[separatorRange.upperBound...])
    } else {
      rawBody = Data()
    }

    // Decode chunked transfer encoding if present
    let isChunked = headers.values.contains(where: { $0.lowercased().contains("chunked") })
    if isChunked && !rawBody.isEmpty {
      self.body = HTTPRequest.decodeChunkedBody(rawBody)
    } else {
      self.body = rawBody
    }
  }

  /// Decodes an HTTP chunked transfer-encoded body into a flat Data buffer.
  private static func decodeChunkedBody(_ data: Data) -> Data {
    var result = Data()
    var offset = data.startIndex
    let crlf = Data("\r\n".utf8)

    while offset < data.endIndex {
      // Find the end of the chunk size line
      guard let crlfRange = data.range(of: crlf, in: offset..<data.endIndex) else { break }

      // Parse chunk size (hex)
      let sizeData = data[offset..<crlfRange.lowerBound]
      guard let sizeString = String(data: sizeData, encoding: .ascii),
            let chunkSize = UInt(sizeString.trimmingCharacters(in: .whitespaces), radix: 16) else { break }

      // Chunk size 0 means end of body
      if chunkSize == 0 { break }

      let chunkStart = crlfRange.upperBound
      let chunkEnd = data.index(chunkStart, offsetBy: Int(chunkSize), limitedBy: data.endIndex) ?? data.endIndex
      result.append(data[chunkStart..<chunkEnd])

      // Skip past the chunk data and trailing CRLF
      offset = min(data.index(chunkEnd, offsetBy: crlf.count, limitedBy: data.endIndex) ?? data.endIndex, data.endIndex)
    }

    return result
  }
}

// MARK: - Default Media Uploader

/// Uploads files to the WordPress REST API using site credentials from EditorConfiguration.
class DefaultMediaUploader: @unchecked Sendable {
  private let httpClient: EditorHTTPClientProtocol
  private let siteApiRoot: URL

  init(httpClient: EditorHTTPClientProtocol, siteApiRoot: URL) {
    self.httpClient = httpClient
    self.siteApiRoot = siteApiRoot
  }

  func upload(fileURL: URL, mimeType: String, filename: String) async throws -> MediaUploadResult {
    let fileData = try Data(contentsOf: fileURL)
    let boundary = UUID().uuidString

    var body = Data()
    body.append("--\(boundary)\r\n")
    body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
    body.append("Content-Type: \(mimeType)\r\n\r\n")
    body.append(fileData)
    body.append("\r\n--\(boundary)--\r\n")

    let uploadURL = siteApiRoot.appending(path: "wp/v2/media")
    var request = URLRequest(url: uploadURL)
    request.httpMethod = "POST"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    let (data, _) = try await httpClient.perform(request)

    // Parse the WordPress media response into our result type
    let wpMedia: WPMediaResponse
    do {
      wpMedia = try JSONDecoder().decode(WPMediaResponse.self, from: data)
    } catch {
      let preview = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
      throw MediaUploadError.unexpectedResponse(preview: preview, underlyingError: error)
    }

    return MediaUploadResult(
      id: wpMedia.id,
      url: wpMedia.source_url,
      alt: wpMedia.alt_text ?? "",
      caption: wpMedia.caption?.rendered ?? "",
      title: wpMedia.title.rendered,
      mime: wpMedia.mime_type,
      type: wpMedia.media_type
    )
  }
}

/// WordPress REST API media response (subset of fields).
private struct WPMediaResponse: Decodable {
  let id: Int
  let source_url: String
  let alt_text: String?
  let caption: RenderedField?
  let title: RenderedField
  let mime_type: String
  let media_type: String

  struct RenderedField: Decodable {
    let rendered: String
  }
}

/// Errors specific to the native media upload pipeline.
enum MediaUploadError: Error, LocalizedError {
  /// The WordPress REST API returned a non-JSON response (e.g. HTML error page).
  case unexpectedResponse(preview: String, underlyingError: Error)

  var errorDescription: String? {
    switch self {
    case .unexpectedResponse(let preview, _):
      return "WordPress returned an unexpected response: \(preview)"
    }
  }
}

// MARK: - Helpers

private extension Data {
  mutating func append(_ string: String) {
    append(string.data(using: .utf8)!)
  }

  func hasSuffix(_ other: Data) -> Bool {
    guard count >= other.count else { return false }
    return self[(endIndex - other.count)...] == other
  }
}

extension Logger {
  static let uploadServer = Logger(subsystem: "com.gutenbergkit", category: "upload-server")
}
