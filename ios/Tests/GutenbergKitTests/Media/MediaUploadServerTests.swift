import Darwin
import Foundation
import Testing
@testable import GutenbergKit

/// Check if NWListener can bind in this environment (fails in some test sandboxes).
private let _canStartUploadServer: Bool = {
  do {
    let server = try MediaUploadServer()
    server.stop()
    return true
  } catch {
    return false
  }
}()

// MARK: - Integration Tests (require network)

@Suite("MediaUploadServer Integration", .enabled(if: _canStartUploadServer))
struct MediaUploadServerTests {

  @Test("starts and provides a port and token")
  func startAndStop() throws {
    let server = try MediaUploadServer()
    #expect(server.port > 0)
    #expect(!server.token.isEmpty)
    server.stop()
  }

  @Test("rejects requests without auth token")
  func rejectsUnauthenticated() async throws {
    let server = try MediaUploadServer()
    defer { server.stop() }

    let url = URL(string: "http://127.0.0.1:\(server.port)/upload")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"

    let (_, response) = try await URLSession.shared.data(for: request)
    let httpResponse = try #require(response as? HTTPURLResponse)
    #expect(httpResponse.statusCode == 401)
  }

  @Test("rejects requests with wrong token")
  func rejectsWrongToken() async throws {
    let server = try MediaUploadServer()
    defer { server.stop() }

    let url = URL(string: "http://127.0.0.1:\(server.port)/upload")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer wrong-token", forHTTPHeaderField: "Authorization")

    let (_, response) = try await URLSession.shared.data(for: request)
    let httpResponse = try #require(response as? HTTPURLResponse)
    #expect(httpResponse.statusCode == 401)
  }

  @Test("responds to OPTIONS preflight with CORS headers")
  func corsPreflightResponse() async throws {
    let server = try MediaUploadServer()
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
    let server = try MediaUploadServer()
    defer { server.stop() }

    let url = URL(string: "http://127.0.0.1:\(server.port)/unknown")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(server.token)", forHTTPHeaderField: "Authorization")

    let (_, response) = try await URLSession.shared.data(for: request)
    let httpResponse = try #require(response as? HTTPURLResponse)
    #expect(httpResponse.statusCode == 404)
  }

  @Test("calls delegate and returns upload result")
  func delegateProcessAndUpload() async throws {
    let delegate = MockUploadDelegate()
    let server = try MediaUploadServer(uploadDelegate: delegate)
    defer { server.stop() }

    let boundary = UUID().uuidString
    let fileData = "fake image data".data(using: .utf8)!
    let body = buildMultipartBody(boundary: boundary, filename: "photo.jpg", mimeType: "image/jpeg", data: fileData)

    // Send via raw TCP socket to bypass URLSession's resumable upload protocol
    // framing (draft-ietf-httpbis-resumable-upload), which prepends extra bytes
    // that break multipart parsing. Production uses WebView fetch(), unaffected.
    let data = try await sendRawUpload(
      port: server.port, token: server.token, boundary: boundary, body: body
    )

    #expect(delegate.processFileCalled)
    #expect(delegate.uploadFileCalled)
    #expect(delegate.lastMimeType == "image/jpeg")
    #expect(delegate.lastFilename == "photo.jpg")

    let result = try JSONDecoder().decode(MediaUploadResult.self, from: data)
    #expect(result.id == 42)
    #expect(result.url == "https://example.com/photo.jpg")
    #expect(result.type == "image")
  }

  @Test("falls back to default uploader when delegate returns nil")
  func delegateFallbackToDefault() async throws {
    let delegate = ProcessOnlyDelegate()
    let mockUploader = MockDefaultUploader()
    let server = try MediaUploadServer(uploadDelegate: delegate, defaultUploader: mockUploader)
    defer { server.stop() }

    let boundary = UUID().uuidString
    let fileData = "fake data".data(using: .utf8)!
    let body = buildMultipartBody(boundary: boundary, filename: "doc.pdf", mimeType: "application/pdf", data: fileData)

    let data = try await sendRawUpload(
      port: server.port, token: server.token, boundary: boundary, body: body
    )

    #expect(delegate.processFileCalled)
    #expect(mockUploader.uploadCalled)

    let result = try JSONDecoder().decode(MediaUploadResult.self, from: data)
    #expect(result.id == 99)
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

  /// Sends a multipart upload via a raw TCP socket, bypassing URLSession.
  ///
  /// URLSession on iOS 26+ uses the resumable upload protocol
  /// (draft-ietf-httpbis-resumable-upload) which prepends framing bytes to the
  /// request body, breaking multipart parsing on our NWListener-based server.
  /// Production traffic comes from the WebView's `fetch()` API which sends
  /// standard HTTP, so this only affects tests.
  ///
  /// This workaround can be removed once URLSession stops using the resumable
  /// upload protocol for localhost connections, or if we switch to a different
  /// HTTP server implementation that handles it.
  private func sendRawUpload(port: UInt16, token: String, boundary: String, body: Data) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      let fd = socket(AF_INET, SOCK_STREAM, 0)
      guard fd >= 0 else {
        continuation.resume(throwing: POSIXError(.init(rawValue: errno)!))
        return
      }

      var addr = sockaddr_in()
      addr.sin_family = sa_family_t(AF_INET)
      addr.sin_port = UInt16(port).bigEndian
      addr.sin_addr.s_addr = inet_addr("127.0.0.1")

      let connectResult = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
      }

      guard connectResult == 0 else {
        close(fd)
        continuation.resume(throwing: POSIXError(.init(rawValue: errno)!))
        return
      }

      // Build raw HTTP request
      var request = Data()
      request.append("POST /upload HTTP/1.1\r\n")
      request.append("Host: 127.0.0.1:\(port)\r\n")
      request.append("Authorization: Bearer \(token)\r\n")
      request.append("Content-Type: multipart/form-data; boundary=\(boundary)\r\n")
      request.append("Content-Length: \(body.count)\r\n")
      request.append("Connection: close\r\n")
      request.append("\r\n")
      request.append(body)

      request.withUnsafeBytes { ptr in
        _ = send(fd, ptr.baseAddress!, ptr.count, 0)
      }

      // Read response
      var responseData = Data()
      let bufferSize = 65536
      let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
      defer { buffer.deallocate() }

      while true {
        let bytesRead = recv(fd, buffer, bufferSize, 0)
        if bytesRead <= 0 { break }
        responseData.append(buffer, count: bytesRead)
      }
      close(fd)

      // Extract HTTP body (after \r\n\r\n)
      guard let headerEnd = responseData.range(of: Data("\r\n\r\n".utf8)) else {
        continuation.resume(throwing: POSIXError(.EBADMSG))
        return
      }

      // Verify we got HTTP 200
      let headerString = String(data: responseData[responseData.startIndex..<headerEnd.lowerBound], encoding: .utf8) ?? ""
      guard headerString.contains("200") else {
        let bodyStr = String(data: responseData[headerEnd.upperBound...], encoding: .utf8) ?? ""
        continuation.resume(throwing: TestUploadError.httpError(header: headerString, body: bodyStr))
        return
      }

      let responseBody = Data(responseData[headerEnd.upperBound...])
      continuation.resume(returning: responseBody)
    }
  }
}

// MARK: - Unit Tests (no network required)

@Suite("MediaUploadDelegate defaults")
struct MediaUploadDelegateDefaultsTests {

  @Test("default processFile returns original URL")
  func defaultProcessFile() async throws {
    let delegate = MinimalDelegate()
    let url = URL(fileURLWithPath: "/tmp/test.jpg")
    let result = try await delegate.processFile(at: url, mimeType: "image/jpeg")
    #expect(result == url)
  }

  @Test("default uploadFile returns nil")
  func defaultUploadFile() async throws {
    let delegate = MinimalDelegate()
    let url = URL(fileURLWithPath: "/tmp/test.jpg")
    let result = try await delegate.uploadFile(at: url, mimeType: "image/jpeg", filename: "test.jpg")
    #expect(result == nil)
  }
}

@Suite("MediaUploadResult encoding")
struct MediaUploadResultTests {

  @Test("encodes to JSON with all fields")
  func encodesToJSON() throws {
    let result = MediaUploadResult(
      id: 123,
      url: "https://example.com/photo.jpg",
      alt: "A photo",
      caption: "My caption",
      title: "photo",
      mime: "image/jpeg",
      type: "image"
    )

    let data = try JSONEncoder().encode(result)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    #expect(json["id"] as? Int == 123)
    #expect(json["url"] as? String == "https://example.com/photo.jpg")
    #expect(json["alt"] as? String == "A photo")
    #expect(json["caption"] as? String == "My caption")
    #expect(json["title"] as? String == "photo")
    #expect(json["mime"] as? String == "image/jpeg")
    #expect(json["type"] as? String == "image")
  }

  @Test("round-trips through JSON")
  func roundTrips() throws {
    let original = MediaUploadResult(
      id: 42,
      url: "https://example.com/file.pdf",
      title: "file",
      mime: "application/pdf",
      type: "file"
    )

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(MediaUploadResult.self, from: data)

    #expect(decoded.id == original.id)
    #expect(decoded.url == original.url)
    #expect(decoded.alt == original.alt)
    #expect(decoded.title == original.title)
    #expect(decoded.mime == original.mime)
    #expect(decoded.type == original.type)
  }
}

// MARK: - Errors

private enum TestUploadError: Error, CustomStringConvertible {
  case httpError(header: String, body: String)

  var description: String {
    switch self {
    case .httpError(let header, let body): "HTTP error: \(header)\n\(body)"
    }
  }
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

  func processFile(at url: URL, mimeType: String) async throws -> URL {
    lock.withLock {
      _processFileCalled = true
      _lastMimeType = mimeType
    }
    return url
  }

  func uploadFile(at url: URL, mimeType: String, filename: String) async throws -> MediaUploadResult? {
    lock.withLock {
      _uploadFileCalled = true
      _lastFilename = filename
    }
    return MediaUploadResult(
      id: 42,
      url: "https://example.com/photo.jpg",
      title: "photo",
      mime: "image/jpeg",
      type: "image"
    )
  }
}

private final class ProcessOnlyDelegate: MediaUploadDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private var _processFileCalled = false

  var processFileCalled: Bool { lock.withLock { _processFileCalled } }

  func processFile(at url: URL, mimeType: String) async throws -> URL {
    lock.withLock { _processFileCalled = true }
    return url
  }
}

private final class MinimalDelegate: MediaUploadDelegate {
  // Uses all default implementations
}

private final class MockDefaultUploader: DefaultMediaUploader, @unchecked Sendable {
  private let lock = NSLock()
  private var _uploadCalled = false

  var uploadCalled: Bool { lock.withLock { _uploadCalled } }

  init() {
    super.init(httpClient: MockHTTPClient(), siteApiRoot: URL(string: "https://example.com/wp-json/")!)
  }

  override func upload(fileURL: URL, mimeType: String, filename: String) async throws -> MediaUploadResult {
    lock.withLock { _uploadCalled = true }
    return MediaUploadResult(
      id: 99,
      url: "https://example.com/doc.pdf",
      title: "doc",
      mime: "application/pdf",
      type: "file"
    )
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
