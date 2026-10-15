import Foundation
import Testing

@testable import GutenbergKit

// Test doubles shared by the native media upload suites.

// MARK: - HTTP clients

/// An HTTP client whose `performRaw` relays a canned response without validating
/// status, while `perform` throws on a non-2xx — mirroring the real
/// `EditorHTTPClient`. Lets a test prove `InternalMediaClient` routes uploads
/// through `performRaw` (relay) rather than `perform` (throw).
struct RelayStubHTTPClient: EditorHTTPClientProtocol {
  let statusCode: Int
  let body: Data
  var headerFields: [String: String]?

  func perform(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let response = HTTPURLResponse(
      url: urlRequest.url!, statusCode: statusCode, httpVersion: nil, headerFields: headerFields)!
    guard (200...299).contains(statusCode) else {
      throw NSError(domain: "RelayStubHTTPClient", code: statusCode)
    }
    return (body, response)
  }

  func performRaw(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let response = HTTPURLResponse(
      url: urlRequest.url!, statusCode: statusCode, httpVersion: nil, headerFields: headerFields)!
    return (body, response)
  }

  func download(_ urlRequest: URLRequest) async throws -> (URL, HTTPURLResponse) {
    let response = HTTPURLResponse(url: urlRequest.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    return (FileManager.default.temporaryDirectory, response)
  }
}

/// Captures the URL of the last request so a test can assert the media endpoint
/// URL (namespace + query) the uploader built.
final class URLCapturingHTTPClient: EditorHTTPClientProtocol, @unchecked Sendable {
  private let lock = NSLock()
  private var _lastURL: URL?
  var lastURL: URL? { lock.withLock { _lastURL } }

  private func ok(_ urlRequest: URLRequest) -> (Data, HTTPURLResponse) {
    lock.withLock { _lastURL = urlRequest.url }
    return (Data("{}".utf8), HTTPURLResponse(url: urlRequest.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
  }

  func perform(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) { ok(urlRequest) }
  func performRaw(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) { ok(urlRequest) }
  func download(_ urlRequest: URLRequest) async throws -> (URL, HTTPURLResponse) {
    let (_, response) = ok(urlRequest)
    return (FileManager.default.temporaryDirectory, response)
  }
}

/// Drains and records the body of the last request.
final class BodyCapturingHTTPClient: EditorHTTPClientProtocol, @unchecked Sendable {
  private let lock = NSLock()
  private var _lastBody: Data?
  var lastBody: Data? { lock.withLock { _lastBody } }

  func performRaw(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let body = urlRequest.httpBodyStream.map(readAllFromStream) ?? urlRequest.httpBody ?? Data()
    lock.withLock { _lastBody = body }
    return (Data("{}".utf8), HTTPURLResponse(url: urlRequest.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
  }

  func perform(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) { try await performRaw(urlRequest) }
  func download(_ urlRequest: URLRequest) async throws -> (URL, HTTPURLResponse) {
    (FileManager.default.temporaryDirectory, HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
  }
}

struct InertHTTPClient: EditorHTTPClientProtocol {
  func perform(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
    (Data(), HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
  }

  func download(_ urlRequest: URLRequest) async throws -> (URL, HTTPURLResponse) {
    (FileManager.default.temporaryDirectory, HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
  }
}

/// Reads all bytes from an InputStream using `read()` return value as
/// the sole termination signal (not `hasBytesAvailable`, which is
/// unreliable for piped/bound streams).
func readAllFromStream(_ stream: InputStream) -> Data {
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

// MARK: - Internal media client

/// Records what it was asked to upload or delete, and answers like WordPress.
final class RecordingInternalMediaClient: InternalMediaClient, @unchecked Sendable {
  struct Upload: Equatable {
    let fileURL: URL
    let contents: Data
    let mimeType: String
    let filename: String
    let fields: [MediaUploadField]
    let query: String
  }

  private let lock = NSLock()
  private var _uploads: [Upload] = []
  private var _deletes: [(id: String, query: String)] = []
  private let response: MediaUploadResponse

  var uploads: [Upload] { lock.withLock { _uploads } }
  var deletes: [(id: String, query: String)] { lock.withLock { _deletes } }

  init(response: MediaUploadResponse = MediaUploadResponse(
    statusCode: 201,
    body: Data(#"{"id":99,"source_url":"https://example.com/photo.jpg"}"#.utf8)
  )) {
    self.response = response
    super.init(httpClient: InertHTTPClient(), siteApiRoot: URL(string: "https://example.com/wp-json/")!)
  }

  override func upload(fileURL: URL, mimeType: String, filename: String, fields: [MediaUploadField], query: String) async throws -> MediaUploadResponse {
    let contents = (try? Data(contentsOf: fileURL)) ?? Data()
    lock.withLock {
      _uploads.append(Upload(fileURL: fileURL, contents: contents, mimeType: mimeType, filename: filename, fields: fields, query: query))
    }
    return response
  }

  override func deleteMedia(attachmentId: String, query: String) async throws -> MediaUploadResponse {
    lock.withLock { _deletes.append((attachmentId, query)) }
    return MediaUploadResponse(statusCode: 200, body: Data(#"{"deleted":true}"#.utf8))
  }
}

// MARK: - Uploaders

/// Records the ``MediaUpload`` it is handed, and returns a finished attachment.
final class RecordingUploader: MediaUploader, @unchecked Sendable {
  private let lock = NSLock()
  private var _received: MediaUpload?
  private var _receivedContents: Data?

  var received: MediaUpload? { lock.withLock { _received } }
  var receivedContents: Data? { lock.withLock { _receivedContents } }

  func upload(_ upload: MediaUpload) async throws -> Data {
    let contents = try? Data(contentsOf: upload.fileURL)
    lock.withLock {
      _received = upload
      _receivedContents = contents
    }
    // Shaped like a real attachment: the editor's `transformAttachment` reads
    // `title.raw`, so an example without it would model a body that fails in the
    // editor.
    return Data(#"{"id":7,"source_url":"https://example.com/photo.jpg","media_type":"image","title":{"raw":"photo"},"caption":{"raw":""}}"#.utf8)
  }
}

/// An uploader whose delivery fails terminally, as one would after exhausting its own
/// post-process recovery and force-deleting the orphan.
struct ThrowingUploader: MediaUploader {
  struct Failure: Error {}

  func upload(_ upload: MediaUpload) async throws -> Data {
    throw Failure()
  }
}

// MARK: - Processors

/// Records that `processFile` ran, and leaves the file as it is.
final class ProcessOnlyProcessor: MediaProcessor, @unchecked Sendable {
  private let lock = NSLock()
  private var _processFileCalled = false

  var processFileCalled: Bool { lock.withLock { _processFileCalled } }

  func processFile(at url: URL, mimeType: String, filename: String) async throws -> ProcessedProxyFile {
    lock.withLock { _processFileCalled = true }
    return .original
  }
}

/// A processor that declines every file by metadata via `handlesFile`, and records
/// whether `processFile` ran anyway.
final class DeclineByMetadataProcessor: MediaProcessor, @unchecked Sendable {
  private let lock = NSLock()
  private var _processFileCalled = false

  var processFileCalled: Bool { lock.withLock { _processFileCalled } }

  func handlesFile(ofType mimeType: String, named filename: String) -> Bool { false }

  func processFile(at url: URL, mimeType: String, filename: String) async throws -> ProcessedProxyFile {
    lock.withLock { _processFileCalled = true }
    return .original
  }
}

/// A value-type processor that transcodes into a new file. `struct`, and `Sendable`
/// without `@unchecked` — the shape ``MediaProcessor``'s documentation recommends.
struct ValueTypeProcessor: MediaProcessor {
  func processFile(at url: URL, mimeType: String, filename: String) async throws -> ProcessedProxyFile {
    let processed = FileManager.default.temporaryDirectory
      .appending(component: "value-\(UUID().uuidString).mp4")
    try Data("transcoded".utf8).write(to: processed)
    return .processed(processed, mimeType: "video/mp4", filename: "clip.mp4")
  }
}

/// A processor that writes a new file with changed metadata, and remembers where.
final class ResizingProcessor: MediaProcessor, @unchecked Sendable {
  private let lock = NSLock()
  private var _producedURL: URL?

  /// The URL of the processed file this processor wrote, for cleanup assertions.
  var producedURL: URL? { lock.withLock { _producedURL } }

  func processFile(at url: URL, mimeType: String, filename: String) async throws -> ProcessedProxyFile {
    let newURL = FileManager.default.temporaryDirectory.appending(component: "processed-\(UUID().uuidString)")
    try Data("processed".utf8).write(to: newURL)
    lock.withLock { _producedURL = newURL }
    return .processed(newURL, mimeType: "video/mp4", filename: "clip.mp4")
  }
}

// MARK: - Upload service

/// A ``MediaUploading`` service driven by closures, recording each call.
final class ScriptedUploadService: MediaUploading, @unchecked Sendable {
  struct Call: Equatable {
    let file: MediaUploadFile
    let contents: Data
    let fields: [MediaUploadField]
    let query: String
  }

  private let lock = NSLock()
  private var _calls: [Call] = []
  private var _deletes: [(String, String)] = []
  private let onUpload: @Sendable (MediaUploadFile) async throws -> MediaUploadResponse

  var calls: [Call] { lock.withLock { _calls } }
  var deletes: [(String, String)] { lock.withLock { _deletes } }

  init(onUpload: @escaping @Sendable (MediaUploadFile) async throws -> MediaUploadResponse = { _ in
    MediaUploadResponse(statusCode: 201, body: Data(#"{"id":42}"#.utf8))
  }) {
    self.onUpload = onUpload
  }

  func upload(_ file: MediaUploadFile, fields: [MediaUploadField], query: String) async throws -> MediaUploadResponse {
    let contents = (try? Data(contentsOf: file.url)) ?? Data()
    lock.withLock { _calls.append(Call(file: file, contents: contents, fields: fields, query: query)) }
    return try await onUpload(file)
  }

  func delete(attachmentId: String, query: String) async throws -> MediaUploadResponse {
    lock.withLock { _deletes.append((attachmentId, query)) }
    return MediaUploadResponse(statusCode: 200, body: Data(#"{"deleted":true}"#.utf8))
  }
}

// MARK: - Files

/// Writes `contents` to a new temporary file.
func makeTemporaryFile(_ contents: Data = Data("fake image".utf8), named name: String = "photo.jpg") throws -> URL {
  let directory = FileManager.default.temporaryDirectory.appending(component: "upload-tests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let url = directory.appending(component: name)
  try contents.write(to: url)
  return url
}
