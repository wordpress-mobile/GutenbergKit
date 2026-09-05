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

    @Test("serves requests from an HTTPRequestHandler object, carrying its state")
    func servesFromRequestHandlerObject() async throws {
        // The point of the object overload: the handler holds its dependencies as
        // stored properties and serves from an instance method, so a consumer with
        // state doesn't need statics threading a context through every call.
        let server = try await HTTPServer.start(
            name: "handler-object-test",
            requiresAuthentication: false,
            handler: EchoHandler(greeting: "hello from a struct")
        )
        defer { server.stop() }

        let url = URL(string: "http://127.0.0.1:\(server.port)/anything")!
        let (data, response) = try await URLSession.shared.data(from: url)

        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self) == "hello from a struct")
    }
}

/// A value-type handler — it cannot form a reference cycle back to whatever owns
/// the server, which is why ``HTTPRequestHandler`` isn't `AnyObject`-constrained.
private struct EchoHandler: HTTPRequestHandler {
    let greeting: String

    func handle(_ request: HTTPServer.Request) async -> HTTPResponse {
        HTTPResponse(status: 200, body: Data(greeting.utf8))
    }
}

#endif
