#if canImport(Network)

import Foundation
import Network
import Testing
@testable import GutenbergKitHTTP

@Suite("HTTPServer Start")
struct HTTPServerStartTests {

    // The unit-level readiness-wait timeout behavior (a listener stuck in a
    // non-terminal state must not hang the caller) is covered by
    // `HTTPServerTimeoutTests` against `HTTPServer.withStartTimeout`. This suite
    // keeps the end-to-end port-conflict check below.

    @Test("start fails promptly when the port is already taken (no hang)")
    func startFailsPromptlyOnPortConflict() async throws {
        let first = try await HTTPServer.start(name: "start-conflict-test-a") { _ in
            HTTPResponse(status: 200)
        }
        defer { first.stop() }

        let clock = ContinuousClock()
        let started = clock.now
        await #expect(throws: HTTPServerError.self) {
            _ = try await HTTPServer.start(
                name: "start-conflict-test-b",
                port: first.port,
                startTimeout: .milliseconds(500)
            ) { _ in
                HTTPResponse(status: 200)
            }
        }
        let elapsed = clock.now - started

        // Whether the conflict surfaces as an immediate `.failed` or parks the
        // listener in `.waiting`, start() must give up within the bounded wait
        // rather than suspending its caller indefinitely.
        #expect(elapsed < .seconds(5))
    }
}

#endif
