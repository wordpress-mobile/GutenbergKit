import Foundation
import Testing
import WebKit

@testable import GutenbergKit

@MainActor
@Suite("ActiveSchemeTasks")
struct ActiveSchemeTasksTests {
    /// WebKit can give a new request the address of one it just stopped. Starting the
    /// same object again stands in for that.
    @Test("work for a stopped request can't reach a new one at the same address")
    func staleWorkMissesANewRequest() throws {
        var active = ActiveSchemeTasks()
        let task = FakeSchemeTask(request: URLRequest(url: RestRelayHandleTests.relayURL(for: "https://example.com/wp-json/wp/v2/posts")))

        var stoppedKey: ActiveSchemeTasks.Key?
        active.start(task) { key in
            stoppedKey = key
            return Task {}
        }
        active.stop(task)
        active.start(task) { _ in Task {} }

        let key = try #require(stoppedKey)
        #expect(active.task(for: key) == nil, "the stopped request's work found the new request")

        active.answer(key, with: SchemeResponse(status: 200))
        #expect(task.response == nil, "answered the new request with the stopped request's response")
        #expect(active.count == 1)
    }
}
