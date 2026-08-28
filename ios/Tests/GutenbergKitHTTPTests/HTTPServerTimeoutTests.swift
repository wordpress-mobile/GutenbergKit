#if canImport(Network)

import Foundation
import Network
import Testing
@testable import GutenbergKitHTTP

/// Covers the split read-timeout model: the pre-body phase (headers + drain) is
/// bounded by `readTimeout`, while an accepted body is bounded by the generous
/// `bodyReadTimeout` plus the per-read `idleTimeout`. Also covers rejecting an
/// auth-exempt CORS preflight that carries a body.
@Suite("HTTPServer Timeouts")
struct HTTPServerTimeoutTests {

    @Test("body that streams steadily past readTimeout still succeeds")
    func steadyBodyPastReadTimeoutSucceeds() async throws {
        // Pre-body cap is short; the body ceiling and idle timeout are generous.
        // A body streamed over a span longer than `readTimeout` (but with no gap
        // longer than `idleTimeout`) must complete — the pre-body cap must not
        // bound the accepted body.
        let server = try await HTTPServer.start(
            name: "timeout-steady-body",
            requiresAuthentication: true,
            readTimeout: .milliseconds(500),
            bodyReadTimeout: .seconds(20),
            idleTimeout: .seconds(5)
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        // Five 4-byte chunks, 200 ms apart → ~1s of body transfer, well past the
        // 500 ms pre-body cap, with each gap far under the 5s idle timeout.
        let chunks = Array(repeating: Data("data".utf8), count: 5)
        let contentLength = chunks.reduce(0) { $0 + $1.count }
        let header = "POST /test HTTP/1.1\r\nHost: 127.0.0.1\r\nProxy-Authorization: Bearer \(server.token)\r\nContent-Length: \(contentLength)\r\n\r\n"

        let response = try await sendChunked(header, chunks: chunks, gap: .milliseconds(200), toPort: server.port)
        #expect(response.hasPrefix("HTTP/1.1 200"))
    }

    @Test("body stalled beyond idleTimeout is reaped promptly despite a generous ceiling")
    func stalledBodyIsReaped() async throws {
        // `readTimeout` and `bodyReadTimeout` are long, so only the idle timeout
        // can end this connection. A body that stops mid-transfer must still be
        // reaped promptly by the idle guard rather than held for the full ceiling.
        //
        // iOS closes the connection on read timeout rather than delivering a 408
        // (see RFC9110ConformanceTests.serverSends408OnReadTimeout, disabled for
        // the same reason: "HTTPServer does not yet send 408 on idle timeout").
        // The property under test is the reaping, observed as a prompt close.
        let server = try await HTTPServer.start(
            name: "timeout-stalled-body",
            requiresAuthentication: true,
            readTimeout: .seconds(10),
            bodyReadTimeout: .seconds(10),
            idleTimeout: .milliseconds(500)
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        // Declare 100 bytes but send only 10, then stop. The server waits one idle
        // interval for more body bytes, gets none, and closes the connection.
        let header = "POST /test HTTP/1.1\r\nHost: 127.0.0.1\r\nProxy-Authorization: Bearer \(server.token)\r\nContent-Length: 100\r\n\r\n"
        let clock = ContinuousClock()
        let start = clock.now
        let response = try await sendChunked(header, chunks: [Data(repeating: 0x61, count: 10)], gap: .zero, toPort: server.port)
        let elapsed = clock.now - start

        #expect(!response.contains("HTTP/1.1 200"))  // the stalled body is not accepted
        #expect(elapsed < .seconds(3))               // reaped by the 500ms idle timeout, not the 10s ceiling
    }

    @Test("auth-exempt preflight carrying a body is rejected with 400")
    func preflightWithBodyReturns400() async throws {
        let server = try await HTTPServer.start(
            name: "options-with-body",
            requiresAuthentication: true
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        // A real CORS preflight is bodyless; one with a body must not be
        // read/drained on the auth-exempt path.
        let raw = "OPTIONS /test HTTP/1.1\r\nHost: 127.0.0.1\r\nAccess-Control-Request-Method: POST\r\nContent-Length: 5\r\n\r\nhello"
        let response = try await sendRaw(raw, toPort: server.port)
        #expect(response.hasPrefix("HTTP/1.1 400"))
    }

    @Test("auth-exempt preflight with an oversized body is rejected with 400, not drained")
    func preflightWithOversizedBodyReturns400() async throws {
        let server = try await HTTPServer.start(
            name: "options-oversized-body",
            requiresAuthentication: true,
            maxRequestBodySize: 16
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        // Content-Length exceeds the max body size, so the parser would otherwise
        // enter the drain path — the preflight-with-body guard must reject it first.
        let raw = "OPTIONS /test HTTP/1.1\r\nHost: 127.0.0.1\r\nAccess-Control-Request-Method: POST\r\nContent-Length: 1000\r\n\r\n"
        let response = try await sendRaw(raw, toPort: server.port)
        #expect(response.hasPrefix("HTTP/1.1 400"))
    }

    @Test("bodyless OPTIONS preflight still succeeds")
    func bodylessOptionsSucceeds() async throws {
        let server = try await HTTPServer.start(
            name: "options-bodyless",
            requiresAuthentication: true
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        let raw = "OPTIONS /test HTTP/1.1\r\nHost: 127.0.0.1\r\nAccess-Control-Request-Method: GET\r\n\r\n"
        let response = try await sendRaw(raw, toPort: server.port)
        #expect(response.hasPrefix("HTTP/1.1 200"))
    }

    // MARK: - Start timeout

    @Test("the start-readiness wait fails with .startTimeout instead of hanging")
    func startTimeoutFiresOnStuckBind() async {
        // `withStartTimeout` bounds `HTTPServer.start`'s wait for the listener to
        // become ready. If the readiness wait never completes (a listener stuck in
        // a non-terminal state), it must fail near the deadline — not hang the
        // caller (the editor load awaits this) for the whole operation.
        let clock = ContinuousClock()
        let start = clock.now
        do {
            _ = try await HTTPServer.withStartTimeout(.milliseconds(100)) {
                try await Task.sleep(for: .seconds(60)) // stands in for a stuck bind
                return 0
            }
            Issue.record("expected withStartTimeout to throw .startTimeout")
        } catch HTTPServerError.startTimeout {
            // Expected: the timeout won the race.
        } catch {
            Issue.record("expected .startTimeout, got \(error)")
        }
        #expect(clock.now - start < .seconds(2))
    }

    @Test("the start-readiness wait returns the bound server when it's ready in time")
    func startTimeoutPassesValueThroughWhenReady() async throws {
        // The common case: readiness completes well within the deadline, so the
        // timeout is inert and the operation's value flows through unchanged.
        let value = try await HTTPServer.withStartTimeout(.seconds(5)) { 42 }
        #expect(value == 42)
    }

    // MARK: - Recoverable parse errors

    @Test("a recoverable parse error is answered by the library and never reaches the handler")
    func recoverableErrorBypassesHandler() async throws {
        let handlerCalled = CallFlag()
        let server = try await HTTPServer.start(
            name: "recoverable-default",
            requiresAuthentication: false,
            maxRequestBodySize: 16
        ) { _ in
            handlerCalled.mark()
            return HTTPResponse(status: 200, body: Data("OK".utf8))
        }
        defer { server.stop() }

        // A 100-byte body far exceeds the 16-byte limit → payloadTooLarge, a
        // recoverable error. With no delegate, the library answers a generic 413.
        let header = "POST /test HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 100\r\n\r\n"
        let response = try await sendChunked(header, chunks: [Data(repeating: 0x61, count: 100)], gap: .zero, toPort: server.port)

        #expect(response.hasPrefix("HTTP/1.1 413"))
        #expect(!handlerCalled.wasCalled)  // a rejected request must never reach the handler
    }

    @Test("a delegate customizes the recoverable-error response")
    func delegateCustomizesRecoverableError() async throws {
        let server = try await HTTPServer.start(
            name: "recoverable-delegate",
            requiresAuthentication: false,
            maxRequestBodySize: 16,
            delegate: CustomErrorDelegate()
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK".utf8))
        }
        defer { server.stop() }

        let header = "POST /test HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 100\r\n\r\n"
        let response = try await sendChunked(header, chunks: [Data(repeating: 0x61, count: 100)], gap: .zero, toPort: server.port)

        #expect(response.hasPrefix("HTTP/1.1 413"))
        #expect(response.contains("custom-error-body"))  // the delegate's body, not the generic one
    }

    // MARK: - Helpers

    /// Sends `header` then each element of `chunks`, pausing `gap` before every
    /// chunk, and returns the first response chunk. Used to simulate a body that
    /// arrives incrementally over time.
    private func sendChunked(_ header: String, chunks: [Data], gap: Duration, toPort port: UInt16) async throws -> String {
        let connection = NWConnection(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        defer { connection.cancel() }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Swift.Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.stateUpdateHandler = nil
                    cont.resume()
                case .failed(let error):
                    connection.stateUpdateHandler = nil
                    cont.resume(throwing: error)
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }

        try await send(Data(header.utf8), on: connection)
        for chunk in chunks {
            if gap != .zero {
                try await Task.sleep(for: gap)
            }
            try await send(chunk, on: connection)
        }

        return try await withCheckedThrowingContinuation { cont in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: String(data: data ?? Data(), encoding: .utf8) ?? "")
                }
            }
        }
    }

    private func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Swift.Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    /// Sends a raw HTTP request over TCP and returns the response string.
    private func sendRaw(_ request: String, toPort port: UInt16) async throws -> String {
        try await sendChunked(request, chunks: [], gap: .zero, toPort: port)
    }
}

/// A thread-safe one-way flag for asserting whether a handler ran.
private final class CallFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func mark() { lock.lock(); value = true; lock.unlock() }
    var wasCalled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

/// A delegate that returns a recognizable body for a recoverable parse error.
private final class CustomErrorDelegate: HTTPServerDelegate {
    func response(forRecoverableParseError error: HTTPRequestParseError) -> HTTPResponse {
        HTTPResponse(status: error.httpStatus, body: Data("custom-error-body".utf8))
    }
}

#endif // canImport(Network)
