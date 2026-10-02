import Foundation
import Testing
@testable import GutenbergKit

/// Covers what ``EditorHTTPClient`` tells its delegate about each request's task,
/// against a real `URLSession` whose requests a stub protocol answers, so the task
/// callbacks are `URLSession`'s own.
@Suite("EditorHTTPClient task reporting")
struct EditorHTTPClientTaskReportingTests {
    private let url = URL(string: "https://example.com/wp-json/wp/v2/posts")!

    @Test("reports a request's task from creation to completion, with its metrics")
    func reportsCompletedRequest() async throws {
        let stubbed = StubURLProtocol.makeSession(stub: .init(status: 200, body: Data(#"{"id":1}"#.utf8)))
        defer { stubbed.finish() }
        let recorder = TaskEventRecorder()
        let client = EditorHTTPClient(urlSession: stubbed.session, authHeader: "Bearer test", authorizationScope: .example, delegate: recorder)

        _ = try await client.perform(URLRequest(url: url))

        #expect(recorder.events == ["created", "metrics", "completed", "performed"])
        #expect(Set(recorder.tasks).count == 1, "every callback should name the same task")
        guard case .bytes(let data) = recorder.completedData else {
            Issue.record("expected the response body, got \(String(describing: recorder.completedData))")
            return
        }
        #expect(data == Data(#"{"id":1}"#.utf8))
    }

    @Test("reports a request that never gets a response, which didPerformRequest can't")
    func reportsFailedRequest() async throws {
        let stubbed = StubURLProtocol.makeSession(stub: .init(failure: URLError(.notConnectedToInternet)))
        defer { stubbed.finish() }
        let recorder = TaskEventRecorder()
        let client = EditorHTTPClient(urlSession: stubbed.session, authHeader: "Bearer test", authorizationScope: .example, delegate: recorder)

        await #expect(throws: URLError.self) {
            try await client.perform(URLRequest(url: url))
        }

        #expect(recorder.events.first == "created")
        #expect(recorder.events.last == "failed")
        #expect(!recorder.events.contains("performed"))
        #expect((recorder.completionError as? URLError)?.code == .notConnectedToInternet)
    }

    @Test("reports a download with the file it wrote")
    func reportsDownload() async throws {
        let stubbed = StubURLProtocol.makeSession(stub: .init(status: 200, body: Data("asset".utf8)))
        defer { stubbed.finish() }
        let recorder = TaskEventRecorder()
        let client = EditorHTTPClient(urlSession: stubbed.session, authHeader: "Bearer test", authorizationScope: .example, delegate: recorder)

        _ = try await client.download(URLRequest(url: url))

        #expect(recorder.events.first == "created")
        #expect(recorder.events.contains("completed"))
        guard case .file = recorder.completedData else {
            Issue.record("expected the downloaded file, got \(String(describing: recorder.completedData))")
            return
        }
    }

    @Test("reports the upload client's requests, which carry media uploads")
    func reportsUploadClientRequests() async throws {
        let stubbed = StubURLProtocol.makeSession(stub: .init(status: 201, body: Data(#"{"id":7}"#.utf8)))
        defer { stubbed.finish() }
        let recorder = TaskEventRecorder()
        let client = EditorHTTPClient(urlSession: stubbed.session, authHeader: "Bearer test", authorizationScope: .example, delegate: recorder)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        _ = try await client.uploadClient().performRaw(request)

        #expect(recorder.events.first == "created")
        #expect(recorder.events.contains("completed"))
    }

    @Test("without a delegate, nothing is reported and requests still go out")
    func noDelegate() async throws {
        let stubbed = StubURLProtocol.makeSession(stub: .init(status: 200, body: Data("{}".utf8)))
        defer { stubbed.finish() }
        let client = EditorHTTPClient(urlSession: stubbed.session, authHeader: "Bearer test", authorizationScope: .example)

        _ = try await client.perform(URLRequest(url: url))

        #expect(stubbed.recorder.request != nil)
    }
}
