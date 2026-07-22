#if canImport(Network)

import Foundation
import Network
import Testing
@testable import GutenbergKitHTTP

/// Covers the "connection close cancels the in-flight handler" behaviour. Once a
/// request has been fully read, no bytes flow on the connection until the
/// response is sent, so a handler awaiting slow outbound work (the media-upload
/// relay awaiting `POST /wp/v2/media`) leaves the connection idle. If the peer
/// closes it during that window — what the editor WebView does when it aborts an
/// upload — the handler's task must be cancelled so the outbound work is torn
/// down instead of running to completion and orphaning an attachment.
@Suite("HTTPServer Cancellation")
struct HTTPServerCancellationTests {

    @Test("peer closing the connection cancels an in-flight handler")
    func peerCloseCancelsHandler() async throws {
        let signals = HandlerSignals()

        let server = try await HTTPServer.start(
            name: "cancel-on-close",
            requiresAuthentication: true
        ) { _ in
            signals.markStarted()
            do {
                // Stands in for slow outbound work. A cancelled task throws here
                // promptly, well before the sleep would otherwise complete.
                try await Task.sleep(for: .seconds(10))
                signals.markFinishedNormally()
            } catch {
                signals.markCancelled()
            }
            return HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        // Open a raw connection and send a complete request so the handler runs.
        let connection = NWConnection(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: server.port)!,
            using: .tcp
        )
        try await waitUntilReady(connection)
        let request = "POST /upload HTTP/1.1\r\nHost: 127.0.0.1\r\nProxy-Authorization: Bearer \(server.token)\r\nContent-Length: 0\r\n\r\n"
        try await send(Data(request.utf8), on: connection)

        // Once the handler is actually running, abort by closing the client side
        // of the connection — exactly what an aborted `fetch` does.
        try await signals.waitUntilStarted()
        connection.cancel()

        // The handler must observe cancellation promptly, not run its 10s sleep
        // to completion.
        let cancelled = await signals.waitUntilCancelled(timeout: .seconds(3))
        #expect(cancelled)
        #expect(!signals.didFinishNormally)
    }

    @Test("stopping the server mid-handler closes the connection without sending a response")
    func serverStopMidHandlerSendsNoResponse() async throws {
        let signals = HandlerSignals()

        let server = try await HTTPServer.start(
            name: "cancel-on-stop",
            requiresAuthentication: true
        ) { _ in
            signals.markStarted()
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                signals.markCancelled()
            }
            // The handler is non-throwing, so it still returns a response after
            // being cancelled — the server must NOT write it to the dying
            // connection.
            return HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }

        let connection = NWConnection(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: server.port)!,
            using: .tcp
        )
        try await waitUntilReady(connection)
        let request = "POST /upload HTTP/1.1\r\nHost: 127.0.0.1\r\nProxy-Authorization: Bearer \(server.token)\r\nContent-Length: 0\r\n\r\n"
        try await send(Data(request.utf8), on: connection)

        // Once the handler is running, stop the server — this cancels the
        // in-flight connection task.
        try await signals.waitUntilStarted()
        server.stop()

        // The client must see the connection close (EOF/reset), not an HTTP
        // response written to a connection being torn down.
        let received = (try? await receiveResponse(connection)) ?? ""
        #expect(!received.hasPrefix("HTTP/1.1"))
        connection.cancel()
    }

    @Test("handler that finishes first still sends its response despite the watcher")
    func handlerFinishesFirstStillResponds() async throws {
        // The close watcher must not interfere with the normal path: a handler
        // that completes before any close still produces a response on the live
        // connection.
        let server = try await HTTPServer.start(
            name: "no-close-normal-response",
            requiresAuthentication: true
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        let request = "POST /upload HTTP/1.1\r\nHost: 127.0.0.1\r\nProxy-Authorization: Bearer \(server.token)\r\nContent-Length: 0\r\n\r\n"
        let response = try await sendRaw(request, toPort: server.port)
        #expect(response.hasPrefix("HTTP/1.1 200"))
    }

    // MARK: - Helpers

    private func waitUntilReady(_ connection: NWConnection) async throws {
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
    }

    private func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Swift.Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    /// Reads one chunk from the connection, returning it as a string (empty on a
    /// clean EOF). Throws if the connection errors (e.g. reset).
    private func receiveResponse(_ connection: NWConnection) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, any Swift.Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: String(data: data ?? Data(), encoding: .utf8) ?? "")
                }
            }
        }
    }

    private func sendRaw(_ request: String, toPort port: UInt16) async throws -> String {
        let connection = NWConnection(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        defer { connection.cancel() }
        try await waitUntilReady(connection)
        try await send(Data(request.utf8), on: connection)
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
}

/// Thread-safe coordinator letting a test observe when the server's handler
/// starts and whether it observed cancellation.
private final class HandlerSignals: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private var cancelled = false
    private var finishedNormally = false

    func markStarted() { lock.lock(); started = true; lock.unlock() }
    func markCancelled() { lock.lock(); cancelled = true; lock.unlock() }
    func markFinishedNormally() { lock.lock(); finishedNormally = true; lock.unlock() }

    private var isStarted: Bool { lock.lock(); defer { lock.unlock() }; return started }
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    var didFinishNormally: Bool { lock.lock(); defer { lock.unlock() }; return finishedNormally }

    func waitUntilStarted(timeout: Duration = .seconds(3)) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if isStarted { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw HandlerSignalTimeout.handlerNeverStarted
    }

    func waitUntilCancelled(timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if isCancelled { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return isCancelled
    }
}

private enum HandlerSignalTimeout: Error {
    case handlerNeverStarted
}

#endif // canImport(Network)
