import Foundation
import Testing
import WebKit

@testable import GutenbergKit

@MainActor
@Suite("MediaUploadSchemeHandler")
struct MediaUploadSchemeHandlerTests {
  private func makeHandler(service: (any MediaUploading)?) -> MediaUploadSchemeHandler {
    MediaUploadSchemeHandler(
      service: service,
      store: MediaUploadSessionStore(
        directory: FileManager.default.temporaryDirectory.appending(component: "scheme-tests-\(UUID().uuidString)")
      )
    )
  }

  /// Starts a request and waits for the handler to answer it.
  @discardableResult
  private func send(
    _ handler: MediaUploadSchemeHandler,
    _ path: String,
    method: String = "POST",
    json: [String: Any]? = nil,
    body: Data? = nil
  ) async throws -> FakeSchemeTask {
    var request = URLRequest(url: URL(string: "gbk-upload://upload\(path)")!)
    request.httpMethod = method
    if let json {
      request.httpBody = try JSONSerialization.data(withJSONObject: json)
    } else {
      request.httpBody = body
    }
    let task = FakeSchemeTask(request: request)
    handler.start(task)
    await task.waitUntilAnswered()
    return task
  }

  private func beginSession(_ handler: MediaUploadSchemeHandler, size: Int) async throws -> String {
    let task = try await send(handler, "/sessions", json: ["filename": "clip.mp4", "mimeType": "video/mp4", "size": size])
    #expect(task.status == 201)
    return try #require(task.json["id"] as? String)
  }

  // MARK: - Uploads from the page

  @Test("assembles chunks, finishes with the fields and query, and relays WordPress's answer")
  func uploadsInChunks() async throws {
    let service = ScriptedUploadService { _ in
      MediaUploadResponse(statusCode: 201, body: Data(#"{"id":42}"#.utf8))
    }
    let handler = makeHandler(service: service)

    let id = try await beginSession(handler, size: 10)
    let first = try await send(handler, "/sessions/\(id)/chunks?offset=0", body: Data("01234".utf8))
    let second = try await send(handler, "/sessions/\(id)/chunks?offset=5", body: Data("56789".utf8))
    let finish = try await send(handler, "/sessions/\(id)/finish", json: [
      "fields": [["name": "post", "value": "7"]],
      "query": "?_embed"
    ])

    #expect(first.json["received"] as? Int == 5)
    #expect(second.json["received"] as? Int == 10)
    #expect(finish.status == 201)
    #expect(finish.json["id"] as? Int == 42)
    #expect(finish.header("Content-Type") == "application/json")
    let call = try #require(service.calls.first)
    #expect(call.contents == Data("0123456789".utf8))
    #expect(call.file.filename == "clip.mp4")
    #expect(call.fields == [MediaUploadField(name: "post", value: "7")])
    #expect(call.query == "?_embed")
    #expect(!FileManager.default.fileExists(atPath: call.file.url.path), "the staging copy outlived the upload")
  }

  @Test("relays a failed upload's status and attachment ID, and exposes the header to the page")
  func relaysRecoverableFailures() async throws {
    let service = ScriptedUploadService { _ in
      MediaUploadResponse(
        statusCode: 500,
        body: Data(#"{"code":"rest_upload_sideload_error"}"#.utf8),
        headers: ["x-wp-upload-attachment-id": "42"]
      )
    }
    let handler = makeHandler(service: service)
    let id = try await beginSession(handler, size: 0)

    let finish = try await send(handler, "/sessions/\(id)/finish", json: [:])

    #expect(finish.status == 500)
    #expect(finish.header("x-wp-upload-attachment-id") == "42")
    #expect(finish.header("Access-Control-Expose-Headers") == "x-wp-upload-attachment-id")
    #expect(finish.header("Access-Control-Allow-Origin") == "*")
  }

  @Test("answers every request with CORS headers, including errors")
  func corsOnErrors() async throws {
    let handler = makeHandler(service: ScriptedUploadService())

    let notFound = try await send(handler, "/nope")
    let preflight = try await send(handler, "/sessions", method: "OPTIONS")

    #expect(notFound.status == 404)
    #expect(notFound.header("Access-Control-Allow-Origin") == "*")
    #expect(preflight.status == 204)
    #expect(preflight.header("Access-Control-Allow-Methods")?.contains("POST") == true)
  }

  @Test("refuses a chunk with no body rather than leaving the file short")
  func refusesEmptyChunks() async throws {
    let handler = makeHandler(service: ScriptedUploadService())
    let id = try await beginSession(handler, size: 4)

    let chunk = try await send(handler, "/sessions/\(id)/chunks?offset=0", body: nil)

    #expect(chunk.status == 400)
    #expect(chunk.json["code"] as? String == "native_upload_empty_chunk")
  }

  @Test("refuses an out-of-order chunk")
  func refusesOutOfOrderChunks() async throws {
    let handler = makeHandler(service: ScriptedUploadService())
    let id = try await beginSession(handler, size: 10)

    let chunk = try await send(handler, "/sessions/\(id)/chunks?offset=5", body: Data("56789".utf8))

    #expect(chunk.status == 409)
  }

  @Test("refuses to finish a file missing bytes, without uploading it")
  func refusesIncompleteUploads() async throws {
    let service = ScriptedUploadService()
    let handler = makeHandler(service: service)
    let id = try await beginSession(handler, size: 10)
    try await send(handler, "/sessions/\(id)/chunks?offset=0", body: Data("01234".utf8))

    let finish = try await send(handler, "/sessions/\(id)/finish", json: [:])

    #expect(finish.status == 409)
    #expect(service.calls.isEmpty)
  }

  @Test("answers an unknown session with a 404")
  func unknownSession() async throws {
    let handler = makeHandler(service: ScriptedUploadService())

    let finish = try await send(handler, "/sessions/0f8fad5b-d9cb-469f-a165-70867728950e/finish", json: [:])

    #expect(finish.status == 404)
  }

  @Test("a cancelled session can't be finished")
  func cancelledSessions() async throws {
    let service = ScriptedUploadService()
    let handler = makeHandler(service: service)
    let id = try await beginSession(handler, size: 0)

    let cancel = try await send(handler, "/sessions/\(id)/cancel")
    let finish = try await send(handler, "/sessions/\(id)/finish", json: [:])

    #expect(cancel.status == 204)
    #expect(finish.status == 404)
    #expect(service.calls.isEmpty)
  }

  @Test("answers a malformed request body with a 400")
  func malformedBodies() async throws {
    let handler = makeHandler(service: ScriptedUploadService())

    let begin = try await send(handler, "/sessions", body: Data("not json".utf8))

    #expect(begin.status == 400)
  }

  // MARK: - Files native code holds

  @Test("finishes a registered file without the page sending its bytes")
  func uploadsRegisteredFiles() async throws {
    let service = ScriptedUploadService()
    let handler = makeHandler(service: service)
    let url = try makeTemporaryFile(Data("imported video".utf8), named: "IMG_0001.MOV")
    let id = try #require(await handler.register(MediaUploadFile(url: url, mimeType: "video/quicktime", filename: "IMG_0001.MOV")))

    let finish = try await send(handler, "/sessions/\(id)/finish", json: ["fields": [["name": "post", "value": "7"]]])

    #expect(finish.status == 201)
    #expect(service.calls.first?.contents == Data("imported video".utf8))
    #expect(service.calls.first?.file.filename == "IMG_0001.MOV")
    #expect(FileManager.default.fileExists(atPath: url.path), "deleted a file the handler doesn't own")
  }

  // MARK: - Deletes

  @Test("relays a media delete with its query")
  func relaysDeletes() async throws {
    let service = ScriptedUploadService()
    let handler = makeHandler(service: service)

    let delete = try await send(handler, "/media/42/delete", json: ["query": "?force=true"])

    #expect(delete.status == 200)
    #expect(service.deletes.first?.0 == "42")
    #expect(service.deletes.first?.1 == "?force=true")
  }

  @Test("refuses a delete for an attachment ID that isn't numeric")
  func refusesNonNumericDeletes() async throws {
    let service = ScriptedUploadService()
    let handler = makeHandler(service: service)

    let delete = try await send(handler, "/media/../delete", json: [:])

    #expect(delete.status == 404)
    #expect(service.deletes.isEmpty)
  }

  // MARK: - Stopping

  @Test("answers every request with a 503 when there is no media handling")
  func unavailableWithoutAService() async throws {
    let handler = makeHandler(service: nil)

    let begin = try await send(handler, "/sessions", json: ["filename": "a.jpg", "mimeType": "image/jpeg"])

    #expect(begin.status == 503)
    #expect(begin.json["code"] as? String == "native_upload_unavailable")
    #expect(await handler.register(MediaUploadFile(url: URL(fileURLWithPath: "/tmp/x"), mimeType: "image/jpeg", filename: "x")) == nil)
  }

  @Test("disable() cancels an upload in flight and refuses new ones")
  func disableCancelsUploads() async throws {
    let gate = AsyncGate()
    let service = ScriptedUploadService { _ in
      await gate.enter()
      try Task.checkCancellation()
      return MediaUploadResponse(statusCode: 201, body: Data("{}".utf8))
    }
    let handler = makeHandler(service: service)
    let id = try await beginSession(handler, size: 0)

    var request = URLRequest(url: URL(string: "gbk-upload://upload/sessions/\(id)/finish")!)
    request.httpMethod = "POST"
    request.httpBody = Data("{}".utf8)
    let finish = FakeSchemeTask(request: request)
    handler.start(finish)
    await gate.waitUntilEntered()

    handler.disable()
    await gate.open()
    await finish.waitUntilAnswered()

    #expect(finish.status == 503)
    let begin = try await send(handler, "/sessions", json: ["filename": "a.jpg", "mimeType": "image/jpeg"])
    #expect(begin.status == 503)
  }

  @Test("never answers a request WebKit stopped, and cancels its upload")
  func stoppedRequestsAreNotAnswered() async throws {
    let gate = AsyncGate()
    let sawCancellation = Flag()
    let service = ScriptedUploadService { _ in
      await gate.enter()
      if Task.isCancelled { sawCancellation.set() }
      try Task.checkCancellation()
      return MediaUploadResponse(statusCode: 201, body: Data("{}".utf8))
    }
    let handler = makeHandler(service: service)
    let id = try await beginSession(handler, size: 0)

    var request = URLRequest(url: URL(string: "gbk-upload://upload/sessions/\(id)/finish")!)
    request.httpMethod = "POST"
    request.httpBody = Data("{}".utf8)
    let finish = FakeSchemeTask(request: request)
    handler.start(finish)
    await gate.waitUntilEntered()

    handler.stop(finish)
    await gate.open()
    for _ in 0..<50 where handler.activeRequestCount > 0 || !sawCancellation.isSet {
      try await Task.sleep(for: .milliseconds(10))
    }
    try await Task.sleep(for: .milliseconds(50))

    #expect(sawCancellation.isSet, "the upload kept running for a page that left")
    #expect(finish.response == nil, "answered a stopped task, which WebKit raises on")
    #expect(!finish.finished)
  }
}

/// A `WKURLSchemeTask` that records what the handler sends it.
final class FakeSchemeTask: NSObject, WKURLSchemeTask, @unchecked Sendable {
  let request: URLRequest
  private let lock = NSLock()
  private var _response: URLResponse?
  private var _body = Data()
  private var _finished = false
  private var _failure: (any Error)?

  var response: URLResponse? { lock.withLock { _response } }
  var body: Data { lock.withLock { _body } }
  var finished: Bool { lock.withLock { _finished } }
  var failure: (any Error)? { lock.withLock { _failure } }

  init(request: URLRequest) {
    self.request = request
  }

  func didReceive(_ response: URLResponse) { lock.withLock { _response = response } }
  func didReceive(_ data: Data) { lock.withLock { _body.append(data) } }
  func didFinish() { lock.withLock { _finished = true } }
  func didFailWithError(_ error: any Error) { lock.withLock { _failure = error } }

  var status: Int? { (response as? HTTPURLResponse)?.statusCode }

  func header(_ name: String) -> String? {
    (response as? HTTPURLResponse)?.value(forHTTPHeaderField: name)
  }

  var json: [String: Any] {
    (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
  }

  func waitUntilAnswered(timeout: Duration = .seconds(5)) async {
    let deadline = ContinuousClock.now + timeout
    while !finished && failure == nil && ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(2))
    }
  }
}

final class Flag: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false
  var isSet: Bool { lock.withLock { value } }
  func set() { lock.withLock { value = true } }
}
