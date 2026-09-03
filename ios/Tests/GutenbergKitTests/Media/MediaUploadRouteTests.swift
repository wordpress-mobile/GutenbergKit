import Foundation
import GutenbergKitHTTP
import Testing
@testable import GutenbergKit

@Suite("MediaUploadRoute", .enabled(if: localServerCanBind))
struct MediaUploadRouteTests {

  @Test("routes /upload with a query string and relays the query")
  func uploadWithQueryString() async throws {
    let delegate = ProcessOnlyDelegate()
    let mockUploader = MockDefaultUploader()
    let server = try await EditorLocalServer.start(routes: [MediaUploadRoute(uploadDelegate: delegate, defaultUploader: mockUploader)])
    defer { server.stop() }

    // `@wordpress/media-utils` uploads to `/wp/v2/media?_embed=wp:featuredmedia`,
    // so the middleware forwards that query on to the native server. Routing must
    // match on the path alone, and the query must reach WordPress unchanged.
    let boundary = UUID().uuidString
    let body = buildMultipartBody(boundary: boundary, filename: "photo.jpg", mimeType: "image/jpeg", data: Data("fake image data".utf8))

    let url = URL(string: "http://127.0.0.1:\(server.port)/upload?_embed=wp:featuredmedia")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(server.token)", forHTTPHeaderField: "Relay-Authorization")
    request.setBrowserOrigin()
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    let (_, response) = try await URLSession.shared.data(for: request)
    let httpResponse = try #require(response as? HTTPURLResponse)
    #expect(httpResponse.statusCode == 201)
    // The delegate returns `.original`, so this is the passthrough branch.
    // Pin which branch ran — `lastQuery` is recorded by both, so without this
    // the query assertion would pass even if routing collapsed onto one path.
    #expect(mockUploader.passthroughUploadCalled)
    #expect(!mockUploader.uploadCalled)
    #expect(mockUploader.lastQuery == "?_embed=wp:featuredmedia")
  }

  @Test("calls delegate and returns upload result")
  func delegateProcessAndUpload() async throws {
    let delegate = MockUploadDelegate()
    let server = try await EditorLocalServer.start(routes: [MediaUploadRoute(uploadDelegate: delegate)])
    defer { server.stop() }

    let boundary = UUID().uuidString
    let fileData = "fake image data".data(using: .utf8)!
    let body = buildMultipartBody(boundary: boundary, filename: "photo.jpg", mimeType: "image/jpeg", data: fileData)

    let url = URL(string: "http://127.0.0.1:\(server.port)/upload")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(server.token)", forHTTPHeaderField: "Relay-Authorization")
    request.setBrowserOrigin()
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
    let server = try await EditorLocalServer.start(routes: [MediaUploadRoute(uploadDelegate: delegate, defaultUploader: mockUploader)])
    defer { server.stop() }

    let boundary = UUID().uuidString
    let fileData = "fake data".data(using: .utf8)!
    let body = buildMultipartBody(boundary: boundary, filename: "doc.pdf", mimeType: "application/pdf", data: fileData)

    let url = URL(string: "http://127.0.0.1:\(server.port)/upload")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(server.token)", forHTTPHeaderField: "Relay-Authorization")
    request.setBrowserOrigin()
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

  @Test("skips processing and the temp copy when the delegate declines by metadata")
  func delegateDeclinesByMetadata() async throws {
    let delegate = DeclineByMetadataDelegate()
    let mockUploader = MockDefaultUploader()
    let server = try await EditorLocalServer.start(routes: [MediaUploadRoute(uploadDelegate: delegate, defaultUploader: mockUploader)])
    defer { server.stop() }

    let boundary = UUID().uuidString
    let body = buildMultipartBody(boundary: boundary, filename: "clip.mov", mimeType: "video/quicktime", data: Data("movie".utf8))

    let url = URL(string: "http://127.0.0.1:\(server.port)/upload")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(server.token)", forHTTPHeaderField: "Relay-Authorization")
    request.setBrowserOrigin()
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    let (_, response) = try await URLSession.shared.data(for: request)
    let httpResponse = try #require(response as? HTTPURLResponse)
    #expect(httpResponse.statusCode == 201)

    // Declined by metadata → the delegate is never asked to process (so the file
    // was never materialized), and the upload is passed through directly.
    #expect(!delegate.processFileCalled)
    #expect(mockUploader.passthroughUploadCalled)
    #expect(!mockUploader.uploadCalled)
  }

  @Test("forwards the delegate's processed metadata to the uploader")
  func processedMetadataForwarded() async throws {
    let delegate = ResizingDelegate()
    let mockUploader = MockDefaultUploader()
    let server = try await EditorLocalServer.start(routes: [MediaUploadRoute(uploadDelegate: delegate, defaultUploader: mockUploader)])
    defer { server.stop() }

    let boundary = UUID().uuidString
    let body = buildMultipartBody(boundary: boundary, filename: "clip.mov", mimeType: "video/quicktime", data: Data("movie".utf8))

    let url = URL(string: "http://127.0.0.1:\(server.port)/upload")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(server.token)", forHTTPHeaderField: "Relay-Authorization")
    request.setBrowserOrigin()
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    _ = try await URLSession.shared.data(for: request)

    // The delegate changed the format, so the uploader must receive the new
    // metadata — not the original video/quicktime + clip.mov.
    #expect(mockUploader.uploadCalled)
    #expect(mockUploader.lastUploadMimeType == "video/mp4")
    #expect(mockUploader.lastUploadFilename == "clip.mp4")
  }

  @Test("deletes the delegate's processed file after upload")
  func deletesProcessedFile() async throws {
    let delegate = ResizingDelegate()
    let mockUploader = MockDefaultUploader()
    let server = try await EditorLocalServer.start(routes: [MediaUploadRoute(uploadDelegate: delegate, defaultUploader: mockUploader)])
    defer { server.stop() }

    let boundary = UUID().uuidString
    let body = buildMultipartBody(boundary: boundary, filename: "clip.mov", mimeType: "video/quicktime", data: Data("movie".utf8))

    let url = URL(string: "http://127.0.0.1:\(server.port)/upload")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(server.token)", forHTTPHeaderField: "Relay-Authorization")
    request.setBrowserOrigin()
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    _ = try await URLSession.shared.data(for: request)

    // The route owns the file the delegate produced and must delete it once the
    // upload finishes — the defer in processAndUpload covers the success and throw
    // paths alike. A leaked processed file is a full-size temp per upload.
    let processedURL = try #require(delegate.producedURL)
    #expect(!FileManager.default.fileExists(atPath: processedURL.path(percentEncoded: false)))
  }

  @Test("startup sweep deletes stale upload temps but preserves fresh ones")
  func cleanOrphanedUploadsAgeThreshold() async throws {
    let dir = FileManager.default.temporaryDirectory
      .appending(component: "GutenbergKit-uploads", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let stale = dir.appending(component: "stale-\(UUID().uuidString)")
    let fresh = dir.appending(component: "fresh-\(UUID().uuidString)")
    try Data("x".utf8).write(to: stale)
    try Data("y".utf8).write(to: fresh)
    defer {
      try? FileManager.default.removeItem(at: stale)
      try? FileManager.default.removeItem(at: fresh)
    }
    // Backdate the stale file well past the 1-hour cutoff.
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: -7200)],
      ofItemAtPath: stale.path(percentEncoded: false)
    )

    // Creating the route kicks off cleanOrphanedUploads() off the
    // editor-startup path. The sweep must delete the aged file and keep the
    // fresh one — a flipped comparison would do the opposite and wipe an
    // in-flight upload.
    let route = MediaUploadRoute()
    await route.cleanupTask.value

    #expect(!FileManager.default.fileExists(atPath: stale.path(percentEncoded: false)))
    #expect(FileManager.default.fileExists(atPath: fresh.path(percentEncoded: false)))
  }

  @Test("does not strongly retain the upload delegate (weak — preserves deinit teardown)")
  func doesNotStronglyRetainDelegate() async throws {
    weak var weakDelegate: MockUploadDelegate?
    let server: EditorLocalServer
    do {
      let delegate = MockUploadDelegate()
      weakDelegate = delegate
      server = try await EditorLocalServer.start(routes: [MediaUploadRoute(uploadDelegate: delegate)])
    }
    defer { server.stop() }

    // MediaUploadRoute holds the delegate weakly, so releasing the host's strong
    // reference deallocates it. A strong reference here would reintroduce the
    // EditorViewController → localServer → … → delegate → EditorViewController
    // cycle, so deinit would never fire and the server would never stop.
    #expect(weakDelegate == nil)
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

/// A delegate that declines every file by metadata via `handlesFile`, so the
/// route must pass through without ever materializing the file or calling
/// `processFile`.
private final class DeclineByMetadataDelegate: MediaUploadDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private var _processFileCalled = false

  var processFileCalled: Bool { lock.withLock { _processFileCalled } }

  func handlesFile(ofType mimeType: String, named filename: String) -> Bool { false }

  func processFile(at url: URL, mimeType: String, filename: String) async throws -> ProcessedProxyFile {
    lock.withLock { _processFileCalled = true }
    return .original
  }
}

/// A delegate that produces a new file with changed metadata (e.g. a transcode).
private final class ResizingDelegate: MediaUploadDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private var _producedURL: URL?

  /// The URL of the processed file this delegate wrote, for cleanup assertions.
  var producedURL: URL? { lock.withLock { _producedURL } }

  func processFile(at url: URL, mimeType: String, filename: String) async throws -> ProcessedProxyFile {
    let newURL = url.deletingLastPathComponent().appending(component: "processed-\(UUID().uuidString)")
    try Data("processed".utf8).write(to: newURL)
    lock.withLock { _producedURL = newURL }
    return .processed(newURL, mimeType: "video/mp4", filename: "clip.mp4")
  }
}

private final class MockDefaultUploader: DefaultMediaUploader, @unchecked Sendable {
  private let lock = NSLock()
  private var _uploadCalled = false
  private var _passthroughUploadCalled = false
  private var _lastUploadMimeType: String?
  private var _lastUploadFilename: String?
  private var _lastQuery: String?

  var uploadCalled: Bool { lock.withLock { _uploadCalled } }
  var passthroughUploadCalled: Bool { lock.withLock { _passthroughUploadCalled } }
  var lastUploadMimeType: String? { lock.withLock { _lastUploadMimeType } }
  var lastUploadFilename: String? { lock.withLock { _lastUploadFilename } }
  var lastQuery: String? { lock.withLock { _lastQuery } }

  init() {
    super.init(httpClient: MockHTTPClient(), siteApiRoot: URL(string: "https://example.com/wp-json/")!)
  }

  override func upload(fileURL: URL, mimeType: String, filename: String, extraParts: [MultipartPart], query: String) async throws -> MediaUploadResponse {
    lock.withLock {
      _uploadCalled = true
      _lastUploadMimeType = mimeType
      _lastUploadFilename = filename
      _lastQuery = query
    }
    return mockResponse()
  }

  override func passthroughUpload(body: RequestBody, contentType: String, query: String) async throws -> MediaUploadResponse {
    lock.withLock {
      _passthroughUploadCalled = true
      _lastQuery = query
    }
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
