#if canImport(Network)

import Foundation
import Network
import Testing
@testable import GutenbergKitHTTP

/// Covers the split read-timeout model: the pre-body phase (headers + drain) is
/// bounded by `readTimeout`, while an accepted body is bounded by the generous
/// `bodyReadTimeout` plus the per-read `idleTimeout`. Also covers rejecting an
/// auth-exempt `OPTIONS` request that carries a body.
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

    @Test("auth-exempt OPTIONS carrying a body is rejected with 400")
    func optionsWithBodyReturns400() async throws {
        let server = try await HTTPServer.start(
            name: "options-with-body",
            requiresAuthentication: true
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        // A real CORS preflight is bodyless; an OPTIONS with a body must not be
        // read/drained on the auth-exempt path.
        let raw = "OPTIONS /test HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 5\r\n\r\nhello"
        let response = try await sendRaw(raw, toPort: server.port)
        #expect(response.hasPrefix("HTTP/1.1 400"))
    }

    @Test("auth-exempt OPTIONS with an oversized body is rejected with 400, not drained")
    func optionsWithOversizedBodyReturns400() async throws {
        let server = try await HTTPServer.start(
            name: "options-oversized-body",
            requiresAuthentication: true,
            maxRequestBodySize: 16
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        // Content-Length exceeds the max body size, so the parser would otherwise
        // enter the drain path — the OPTIONS-with-body guard must reject it first.
        let raw = "OPTIONS /test HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 1000\r\n\r\n"
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

        let raw = "OPTIONS /test HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        let response = try await sendRaw(raw, toPort: server.port)
        #expect(response.hasPrefix("HTTP/1.1 200"))
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

#endif // canImport(Network)
