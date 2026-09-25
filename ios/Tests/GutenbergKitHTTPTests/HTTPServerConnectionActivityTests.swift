#if canImport(Network)

import Foundation
import Network
import Testing
@testable import GutenbergKitHTTP

/// Covers ``HTTPServerDelegate/withConnectionActivity(_:)``: the scope a delegate wraps
/// around a connection has to cover the whole exchange with the client, not just the
/// handler. The media upload server holds a background-task assertion there, and a gap
/// at either end is a window where locking the phone suspends the app mid-upload.
///
/// Each test would hang rather than pass if the scope were narrower, so every wait has a
/// timeout and a failure reads as the gap it found.
@Suite("HTTPServer Connection Activity")
struct HTTPServerConnectionActivityTests {

    @Test("the activity starts before the request body arrives and ends after the response is written")
    func activitySpansTheWholeExchange() async throws {
        let delegate = RecordingActivityDelegate()
        let handlerRanInside = TestFlag()
        let server = try await HTTPServer.start(
            name: "activity-whole-exchange",
            requiresAuthentication: true,
            delegate: delegate
        ) { _ in
            if delegate.isInside { handlerRanInside.raise() }
            return HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        let connection = try await connect(toPort: server.port)
        defer { connection.cancel() }
        let body = Data("hello".utf8)
        let header = "POST /upload HTTP/1.1\r\nHost: 127.0.0.1\r\nProxy-Authorization: Bearer \(server.token)\r\nContent-Length: \(body.count)\r\n\r\n"
        try await send(Data(header.utf8), on: connection)

        // The body hasn't been sent, so the handler can't have run. An activity that only
        // wrapped the handler wouldn't have started yet.
        let startedBeforeBody = await delegate.entered.wait(timeout: .seconds(3))
        #expect(startedBeforeBody, "the activity didn't start until the request body arrived")

        try await send(body, on: connection)
        let response = try await receiveResponse(on: connection)
        delegate.clientHasResponse.raise()

        #expect(response.hasPrefix("HTTP/1.1 200"))
        #expect(handlerRanInside.isRaised, "the handler ran outside the activity")
        let exited = await delegate.exited.wait(timeout: .seconds(5))
        #expect(exited, "the activity never ended")
        #expect(delegate.responseArrivedInside == true, "the response was written after the activity ended")
    }

    @Test("the server's own responses are written inside the activity too")
    func libraryResponsesAreWrittenInsideTheActivity() async throws {
        let delegate = RecordingActivityDelegate()
        let server = try await HTTPServer.start(
            name: "activity-library-response",
            requiresAuthentication: true,
            delegate: delegate
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        // No token, so the server answers 407 itself and the handler never runs.
        let connection = try await connect(toPort: server.port)
        defer { connection.cancel() }
        let request = "POST /upload HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\n\r\n"
        try await send(Data(request.utf8), on: connection)
        let response = try await receiveResponse(on: connection)
        delegate.clientHasResponse.raise()

        #expect(response.hasPrefix("HTTP/1.1 407"))
        let exited = await delegate.exited.wait(timeout: .seconds(5))
        #expect(exited, "the activity never ended")
        #expect(delegate.responseArrivedInside == true, "the 407 was written after the activity ended")
    }

    // MARK: - Helpers

    private func connect(toPort port: UInt16) async throws -> NWConnection {
        let connection = NWConnection(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
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
        return connection
    }

    private func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Swift.Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    private func receiveResponse(on connection: NWConnection) async throws -> String {
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
}

/// Records what happens inside its connection activity.
///
/// After `body` returns it waits for the test to say the client has the response. If the
/// server wrote the response only after `body` returned, the client can't have it until
/// this returns, so the wait runs out and ``responseArrivedInside`` is `false`.
private final class RecordingActivityDelegate: HTTPServerDelegate, @unchecked Sendable {
    let entered = TestFlag()
    let clientHasResponse = TestFlag()
    let exited = TestFlag()

    private let lock = NSLock()
    private var inside = false
    private var arrivedInside: Bool?

    var isInside: Bool { lock.withLock { inside } }
    var responseArrivedInside: Bool? { lock.withLock { arrivedInside } }

    func withConnectionActivity(_ body: () async -> Void) async {
        lock.withLock { inside = true }
        entered.raise()
        await body()
        let arrived = await clientHasResponse.wait(timeout: .seconds(3))
        lock.withLock {
            inside = false
            arrivedInside = arrived
        }
        exited.raise()
    }
}

/// A one-way flag a test can wait on.
private final class TestFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false

    func raise() { lock.withLock { raised = true } }
    var isRaised: Bool { lock.withLock { raised } }

    func wait(timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if isRaised { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return isRaised
    }
}

#endif // canImport(Network)
