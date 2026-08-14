#if canImport(Network)

import Foundation
import Network
import Testing
@testable import GutenbergKitHTTP

@Suite("HTTPServer Start")
struct HTTPServerStartTests {

    @Test("readiness wait returns nil after the timeout when only non-terminal states arrive")
    func readinessWaitTimesOut() async {
        // A listener stuck in `.setup`/`.waiting` emits no further state
        // updates. Without the bound, the wait — and whatever startup path
        // awaits `HTTPServer.start` — would suspend forever.
        let (states, continuation) = AsyncStream.makeStream(of: NWListener.State.self)
        continuation.yield(.setup)
        continuation.yield(.waiting(.posix(.EADDRINUSE)))

        let clock = ContinuousClock()
        let started = clock.now
        let result = await HTTPServer.firstTerminalState(in: states, timeout: .milliseconds(200))
        let elapsed = clock.now - started
        continuation.finish()

        #expect(result == nil)
        // Waited out the timeout, then returned promptly instead of hanging.
        #expect(elapsed >= .milliseconds(150))
        #expect(elapsed < .seconds(5))
    }

    @Test("readiness wait skips non-terminal states and returns the first terminal one")
    func readinessWaitReturnsTerminalState() async {
        let (states, continuation) = AsyncStream.makeStream(of: NWListener.State.self)
        continuation.yield(.setup)
        continuation.yield(.waiting(.posix(.EADDRINUSE)))
        continuation.yield(.ready)

        let result = await HTTPServer.firstTerminalState(in: states, timeout: .seconds(5))
        continuation.finish()

        guard case .ready = result else {
            Issue.record("Expected .ready, got \(String(describing: result))")
            return
        }
    }

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
