import Foundation
import GutenbergKitHTTP
import Testing
@testable import GutenbergKit

/// Check if HTTPServer can bind in this environment (fails in some test sandboxes).
private let _canStartUploadServer: Bool = {
  let result = UnsafeMutableSendablePointer(false)
  let semaphore = DispatchSemaphore(value: 0)
  Task {
    do {
      let server = try await MediaUploadServer.start()
      server.stop()
      result.value = true
    } catch {
      result.value = false
    }
    semaphore.signal()
  }
  semaphore.wait()
  return result.value
}()

/// Sendable wrapper for a mutable value, used to communicate results out of a Task.
private final class UnsafeMutableSendablePointer<T>: @unchecked Sendable {
  var value: T
  init(_ value: T) { self.value = value }
}

// MARK: - Integration Tests (require network)

@Suite("MediaUploadServer Integration", .enabled(if: _canStartUploadServer))
struct MediaUploadServerTests {

  @Test("starts and provides a port and token")
  func startAndStop() async throws {
    let server = try await MediaUploadServer.start()
    #expect(server.port > 0)
    #expect(!server.token.isEmpty)
    server.stop()
  }

  @Test("rejects requests without auth token")
  func rejectsUnauthenticated() async throws {
    let server = try await MediaUploadServer.start()
    defer { server.stop() }

    let url = URL(string: "http://127.0.0.1:\(server.port)/upload")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"

    let (_, response) = try await URLSession.shared.data(for: request)
    let httpResponse = try #require(response as? HTTPURLResponse)
    #expect(httpResponse.statusCode == 407)
  }

  @Test("rejects requests with wrong token")
  func rejectsWrongToken() async throws {
    let server = try await MediaUploadServer.start()
    defer { server.stop() }

    let url = URL(string: "http://127.0.0.1:\(server.port)/upload")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer wrong-token", forHTTPHeaderField: "Relay-Authorization")

    let (_, response) = try await URLSession.shared.data(for: request)
    let httpResponse = try #require(response as? HTTPURLResponse)
    #expect(httpResponse.statusCode == 407)
  }

  @Test("responds to OPTIONS preflight with CORS headers")
  func corsPreflightResponse() async throws {
    let server = try await MediaUploadServer.start()
    defer { server.stop() }

    let url = URL(string: "http://127.0.0.1:\(server.port)/upload")!
    var request = URLRequest(url: url)
    request.httpMethod = "OPTIONS"

    let (_, response) = try await URLSession.shared.data(for: request)
    let httpResponse = try #require(response as? HTTPURLResponse)
    #expect(httpResponse.statusCode == 204)
    #expect(httpResponse.value(forHTTPHeaderField: "Access-Control-Allow-Origin") == "*")
    #expect(httpResponse.value(forHTTPHeaderField: "Access-Control-Allow-Methods")?.contains("POST") == true)
  }

  @Test("returns 404 for unknown paths")
  func unknownPath() async throws {
    let server = try await MediaUploadServer.start()
    defer { server.stop() }

    let url = URL(string: "http://127.0.0.1:\(server.port)/unknown")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(server.token)", forHTTPHeaderField: "Relay-Authorization")

    let (_, response) = try await URLSession.shared.data(for: request)
    let httpResponse = try #require(response as? HTTPURLResponse)
    #expect(httpResponse.statusCode == 404)
  }

  @Test("calls delegate and returns upload result")
  func delegateProcessAndUpload() async throws {
    let delegate = MockUploadDelegate()
    let server = try await MediaUploadServer.start(uploadDelegate: delegate)
    defer { server.stop() }

    let boundary = UUID().uuidString
    let fileData = "fake image data".data(using: .utf8)!
    let body = buildMultipartBody(boundary: boundary, filename: "photo.jpg", mimeType: "image/jpeg", data: fileData)

    let url = URL(string: "http://127.0.0.1:\(server.port)/upload")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(server.token)", forHTTPHeaderField: "Relay-Authorization")
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    let (data, response) = try await URLSession.shared.data(for: request)
    let httpResponse = try #require(response as? HTTPURLResponse)
    #expect(httpResponse.statusCode == 201)

    #expect(delegate.processFileCalled)
    #expect(delegate.uploadFileCalled)
    #expect(delegate.lastMimeType == "image/jpeg")
    #expect(delegate.lastFilename == "photo.jpg")

    // The server relays WordPress's raw response body verbatim.
    let object = try JSONSerialization.jsonObject(with: data)
    let json = try #require(object as? [String: Any])
    #expect(json["id"] as? Int == 42)
    #expect(json["source_url"] as? String == "https://example.com/photo.jpg")
    #expect(json["media_type"] as? String == "image")
  }

  @Test("uses passthrough when delegate does not modify file")
  func delegatePassthrough() async throws {
    let delegate = ProcessOnlyDelegate()
    let mockUploader = MockDefaultUploader()
    let server = try await MediaUploadServer.start(uploadDelegate: delegate, defaultUploader: mockUploader)
    defer { server.stop() }

    let boundary = UUID().uuidString
    let fileData = "fake data".data(using: .utf8)!
    let body = buildMultipartBody(boundary: boundary, filename: "doc.pdf", mimeType: "application/pdf", data: fileData)

    let url = URL(string: "http://127.0.0.1:\(server.port)/upload")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(server.token)", forHTTPHeaderField: "Relay-Authorization")
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    let (data, response) = try await URLSession.shared.data(for: request)
    let httpResponse = try #require(response as? HTTPURLResponse)
    #expect(httpResponse.statusCode == 201)

    #expect(delegate.processFileCalled)
    // Passthrough: original body forwarded directly, not re-encoded.
    #expect(mockUploader.passthroughUploadCalled)
    #expect(!mockUploader.uploadCalled)

    // The server relays WordPress's raw response body verbatim.
    let object = try JSONSerialization.jsonObject(with: data)
    let json = try #require(object as? [String: Any])
    #expect(json["id"] as? Int == 99)
  }

  @Test("forwards the delegate's processed metadata to the uploader")
  func processedMetadataForwarded() async throws {
    let delegate = ResizingDelegate()
    let mockUploader = MockDefaultUploader()
    let server = try await MediaUploadServer.start(uploadDelegate: delegate, defaultUploader: mockUploader)
    defer { server.stop() }

    let boundary = UUID().uuidString
    let body = buildMultipartBody(boundary: boundary, filename: "clip.mov", mimeType: "video/quicktime", data: Data("movie".utf8))

    let url = URL(string: "http://127.0.0.1:\(server.port)/upload")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(server.token)", forHTTPHeaderField: "Relay-Authorization")
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    _ = try await URLSession.shared.data(for: request)

    // The delegate changed the format, so the uploader must receive the new
    // metadata — not the original video/quicktime + clip.mov.
    #expect(mockUploader.uploadCalled)
    #expect(mockUploader.lastUploadMimeType == "video/mp4")
    #expect(mockUploader.lastUploadFilename == "clip.mp4")
  }

  @Test("returns 413 with CORS headers when request body exceeds max size")
  func oversizedUploadReturns413WithCORSHeaders() async throws {
    let server = try await MediaUploadServer.start(maxRequestBodySize: 1024)
    defer { server.stop() }

    let boundary = UUID().uuidString
    let oversizedData = Data(repeating: 0x42, count: 2048)
    let body = buildMultipartBody(boundary: boundary, filename: "big.bin", mimeType: "application/octet-stream", data: oversizedData)

    let url = URL(string: "http://127.0.0.1:\(server.port)/upload")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(server.token)", forHTTPHeaderField: "Relay-Authorization")
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    let (data, response) = try await URLSession.shared.data(for: request)
    let httpResponse = try #require(response as? HTTPURLResponse)
    #expect(httpResponse.statusCode == 413)
    #expect(httpResponse.value(forHTTPHeaderField: "Access-Control-Allow-Origin") == "*")

    let responseBody = String(data: data, encoding: .utf8) ?? ""
    #expect(responseBody.contains("too large"))
  }

  private func buildMultipartBody(boundary: String, filename: String, mimeType: String, data: Data) -> Data {
    var body = Data()
    body.append("--\(boundary)\r\n")
    body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
    body.append("Content-Type: \(mimeType)\r\n\r\n")
    body.append(data)
    body.append("\r\n--\(boundary)--\r\n")
    return body
  }
}

// MARK: - Streaming Multipart Body Tests

@Suite("DefaultMediaUploader streaming multipart body")
struct MultipartBodyStreamTests {

  @Test("streaming output matches in-memory multipart format")
  func streamMatchesInMemory() throws {
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("stream-test-\(UUID().uuidString)")
    let fileContent = Data("hello world".utf8)
    try fileContent.write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let boundary = "test-boundary-123"
    let filename = "photo.jpg"
    let mimeType = "image/jpeg"

    // Build expected output using the old in-memory approach.
    var expected = Data()
    expected.append(Data("--\(boundary)\r\n".utf8))
    expected.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
    expected.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
    expected.append(fileContent)
    expected.append(Data("\r\n--\(boundary)--\r\n".utf8))

    // Build streaming output.
    let (stream, contentLength) = try DefaultMediaUploader.multipartBodyStream(
      fileURL: tempFile, boundary: boundary, filename: filename, mimeType: mimeType, extraFields: []
    )
    #expect(contentLength == expected.count)

    let result = readAllFromStream(stream)
    #expect(result == expected)
  }

  @Test("includes non-file parts (e.g. post) ahead of the file")
  func multipartBodyIncludesExtraParts() throws {
    let boundary = "boundary"
    let filename = "photo.jpg"
    let mimeType = "image/jpeg"
    let fileContent = Data("image bytes".utf8)
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("stream-extra-\(UUID().uuidString)")
    try fileContent.write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    var expected = Data()
    expected.append(Data("--\(boundary)\r\n".utf8))
    expected.append(Data("Content-Disposition: form-data; name=\"post\"\r\n\r\n".utf8))
    expected.append(Data("123\r\n".utf8))
    expected.append(Data("--\(boundary)\r\n".utf8))
    expected.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
    expected.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
    expected.append(fileContent)
    expected.append(Data("\r\n--\(boundary)--\r\n".utf8))

    let (stream, contentLength) = try DefaultMediaUploader.multipartBodyStream(
      fileURL: tempFile, boundary: boundary, filename: filename, mimeType: mimeType,
      extraFields: [("post", Data("123".utf8))]
    )
    #expect(contentLength == expected.count)
    #expect(readAllFromStream(stream) == expected)
  }

  @Test("content length matches actual stream output for larger files")
  func contentLengthAccurate() throws {
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("stream-test-\(UUID().uuidString)")
    let fileContent = Data(repeating: 0x42, count: 100_000)
    try fileContent.write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let (stream, contentLength) = try DefaultMediaUploader.multipartBodyStream(
      fileURL: tempFile, boundary: "boundary", filename: "big.bin", mimeType: "application/octet-stream", extraFields: []
    )

    let result = readAllFromStream(stream)
    #expect(result.count == contentLength)
  }
}

// MARK: - Helpers

/// Reads all bytes from an InputStream using `read()` return value as
/// the sole termination signal (not `hasBytesAvailable`, which is
/// unreliable for piped/bound streams).
private func readAllFromStream(_ stream: InputStream) -> Data {
  stream.open()
  defer { stream.close() }

  var data = Data()
  let bufferSize = 8192
  let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
  defer { buffer.deallocate() }
  while true {
    let read = stream.read(buffer, maxLength: bufferSize)
    if read <= 0 { break }
    data.append(buffer, count: read)
  }
  return data
}

// MARK: - Mocks

private final class MockUploadDelegate: MediaUploadDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private var _processFileCalled = false
  private var _uploadFileCalled = false
  private var _lastMimeType: String?
  private var _lastFilename: String?

  var processFileCalled: Bool { lock.withLock { _processFileCalled } }
  var uploadFileCalled: Bool { lock.withLock { _uploadFileCalled } }
  var lastMimeType: String? { lock.withLock { _lastMimeType } }
  var lastFilename: String? { lock.withLock { _lastFilename } }

  func processFile(at url: URL, mimeType: String, filename: String) async throws -> ProcessedProxyFile {
    lock.withLock {
      _processFileCalled = true
      _lastMimeType = mimeType
    }
    return .original
  }

  func uploadFile(at url: URL, mimeType: String, filename: String) async throws -> MediaUploadResponse? {
    lock.withLock {
      _uploadFileCalled = true
      _lastFilename = filename
    }
    let json = #"{"id":42,"source_url":"https://example.com/photo.jpg","media_type":"image"}"#
    return MediaUploadResponse(statusCode: 201, body: Data(json.utf8))
  }
}

private final class ProcessOnlyDelegate: MediaUploadDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private var _processFileCalled = false

  var processFileCalled: Bool { lock.withLock { _processFileCalled } }

  func processFile(at url: URL, mimeType: String, filename: String) async throws -> ProcessedProxyFile {
    lock.withLock { _processFileCalled = true }
    return .original
  }
}

/// A delegate that produces a new file with changed metadata (e.g. a transcode).
private final class ResizingDelegate: MediaUploadDelegate, @unchecked Sendable {
  func processFile(at url: URL, mimeType: String, filename: String) async throws -> ProcessedProxyFile {
    let newURL = url.deletingLastPathComponent().appending(component: "processed-\(UUID().uuidString)")
    try Data("processed".utf8).write(to: newURL)
    return .processed(newURL, mimeType: "video/mp4", filename: "clip.mp4")
  }
}

private final class MockDefaultUploader: DefaultMediaUploader, @unchecked Sendable {
  private let lock = NSLock()
  private var _uploadCalled = false
  private var _passthroughUploadCalled = false
  private var _lastUploadMimeType: String?
  private var _lastUploadFilename: String?

  var uploadCalled: Bool { lock.withLock { _uploadCalled } }
  var passthroughUploadCalled: Bool { lock.withLock { _passthroughUploadCalled } }
  var lastUploadMimeType: String? { lock.withLock { _lastUploadMimeType } }
  var lastUploadFilename: String? { lock.withLock { _lastUploadFilename } }

  init() {
    super.init(httpClient: MockHTTPClient(), siteApiRoot: URL(string: "https://example.com/wp-json/")!)
  }

  override func upload(fileURL: URL, mimeType: String, filename: String, extraParts: [MultipartPart], query: String) async throws -> MediaUploadResponse {
    lock.withLock {
      _uploadCalled = true
      _lastUploadMimeType = mimeType
      _lastUploadFilename = filename
    }
    return mockResponse()
  }

  override func passthroughUpload(body: RequestBody, contentType: String, query: String) async throws -> MediaUploadResponse {
    lock.withLock { _passthroughUploadCalled = true }
    return mockResponse()
  }

  private func mockResponse() -> MediaUploadResponse {
    let json = #"{"id":99,"source_url":"https://example.com/doc.pdf","media_type":"file"}"#
    return MediaUploadResponse(statusCode: 201, body: Data(json.utf8))
  }
}

private struct MockHTTPClient: EditorHTTPClientProtocol {
  func perform(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let response = HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    return (Data(), response)
  }

  func download(_ urlRequest: URLRequest) async throws -> (URL, HTTPURLResponse) {
    let response = HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    return (FileManager.default.temporaryDirectory, response)
  }
}

private extension Data {
  mutating func append(_ string: String) {
    append(string.data(using: .utf8)!)
  }
}
