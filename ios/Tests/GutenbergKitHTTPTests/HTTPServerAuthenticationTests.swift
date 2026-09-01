#if canImport(Network)

import Foundation
import Network
import Testing
@testable import GutenbergKitHTTP

@Suite("HTTPServer Authentication")
struct HTTPServerAuthenticationTests {

    @Test("request without token returns 407 with Content-Type and Proxy-Authenticate")
    func noTokenReturns407WithHeaders() async throws {
        let server = try await HTTPServer.start(
            name: "auth-test",
            requiresAuthentication: true
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        let url = URL(string: "http://127.0.0.1:\(server.port)/test")!
        let (_, response) = try await URLSession.shared.data(for: URLRequest(url: url))
        let http = try #require(response as? HTTPURLResponse)

        #expect(http.statusCode == 407)
        #expect(http.value(forHTTPHeaderField: "Content-Type") == "text/plain")
        #expect(http.value(forHTTPHeaderField: "Proxy-Authenticate") == "Bearer")
    }

    @Test("request with wrong token returns 407")
    func wrongTokenReturns407() async throws {
        let server = try await HTTPServer.start(
            name: "auth-test",
            requiresAuthentication: true
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        let url = URL(string: "http://127.0.0.1:\(server.port)/test")!
        var request = URLRequest(url: url)
        request.setValue("Bearer wrong-token", forHTTPHeaderField: "Proxy-Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)

        #expect(http.statusCode == 407)
        #expect(http.value(forHTTPHeaderField: "Proxy-Authenticate") == "Bearer")
    }

    @Test("request with valid token returns 200")
    func validTokenReturns200() async throws {
        let server = try await HTTPServer.start(
            name: "auth-test",
            requiresAuthentication: true
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        let url = URL(string: "http://127.0.0.1:\(server.port)/test")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(server.token)", forHTTPHeaderField: "Proxy-Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)

        #expect(http.statusCode == 200)
    }

    @Test("request with lowercase 'bearer' scheme returns 200")
    func lowercaseBearerSchemeReturns200() async throws {
        let server = try await HTTPServer.start(
            name: "auth-test",
            requiresAuthentication: true
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        let url = URL(string: "http://127.0.0.1:\(server.port)/test")!
        var request = URLRequest(url: url)
        request.setValue("bearer \(server.token)", forHTTPHeaderField: "Proxy-Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)

        #expect(http.statusCode == 200)
    }

    @Test("request with uppercase 'BEARER' scheme returns 200")
    func uppercaseBearerSchemeReturns200() async throws {
        let server = try await HTTPServer.start(
            name: "auth-test",
            requiresAuthentication: true
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        let url = URL(string: "http://127.0.0.1:\(server.port)/test")!
        var request = URLRequest(url: url)
        request.setValue("BEARER \(server.token)", forHTTPHeaderField: "Proxy-Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)

        #expect(http.statusCode == 200)
    }

    // MARK: - Relay-Authorization (fetch()-compatible alternative)

    @Test("Relay-Authorization with valid token returns 200")
    func relayAuthValidTokenReturns200() async throws {
        let server = try await HTTPServer.start(
            name: "auth-test",
            requiresAuthentication: true
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        let url = URL(string: "http://127.0.0.1:\(server.port)/test")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(server.token)", forHTTPHeaderField: "Relay-Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)

        #expect(http.statusCode == 200)
    }

    @Test("Relay-Authorization with wrong token returns 407")
    func relayAuthWrongTokenReturns407() async throws {
        let server = try await HTTPServer.start(
            name: "auth-test",
            requiresAuthentication: true
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        let url = URL(string: "http://127.0.0.1:\(server.port)/test")!
        var request = URLRequest(url: url)
        request.setValue("Bearer wrong-token", forHTTPHeaderField: "Relay-Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)

        #expect(http.statusCode == 407)
    }

    @Test("Relay-Authorization with lowercase 'bearer' scheme returns 200")
    func relayAuthLowercaseBearerReturns200() async throws {
        let server = try await HTTPServer.start(
            name: "auth-test",
            requiresAuthentication: true
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        let url = URL(string: "http://127.0.0.1:\(server.port)/test")!
        var request = URLRequest(url: url)
        request.setValue("bearer \(server.token)", forHTTPHeaderField: "Relay-Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)

        #expect(http.statusCode == 200)
    }

    @Test("Authorization header passes through to handler alongside Relay-Authorization")
    func authorizationPassesThroughWithRelayAuth() async throws {
        let server = try await HTTPServer.start(
            name: "auth-test",
            requiresAuthentication: true
        ) { req in
            let auth = req.parsed.header("Authorization") ?? ""
            let relayAuth = req.parsed.header("Relay-Authorization") ?? "absent"
            return HTTPResponse(
                status: 200,
                headers: [("X-Received-Auth", auth), ("X-Received-Relay", relayAuth)],
                body: Data("OK\n".utf8)
            )
        }
        defer { server.stop() }

        let raw = "GET /test HTTP/1.1\r\nHost: 127.0.0.1\r\nRelay-Authorization: Bearer \(server.token)\r\nAuthorization: Basic dXNlcjpwYXNz\r\n\r\n"
        let response = try await sendRaw(raw, toPort: server.port)

        #expect(response.contains("HTTP/1.1 200"))
        #expect(response.contains("X-Received-Auth: Basic dXNlcjpwYXNz"))
    }

    @Test("Proxy-Authorization takes precedence over Relay-Authorization")
    func proxyAuthTakesPrecedenceOverRelayAuth() async throws {
        let server = try await HTTPServer.start(
            name: "auth-test",
            requiresAuthentication: true
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        // Proxy-Authorization has the correct token, Relay-Authorization has a wrong one.
        // Server should accept because Proxy-Authorization is checked first.
        let raw = "GET /test HTTP/1.1\r\nHost: 127.0.0.1\r\nProxy-Authorization: Bearer \(server.token)\r\nRelay-Authorization: Bearer wrong\r\n\r\n"
        let response = try await sendRaw(raw, toPort: server.port)
        #expect(response.hasPrefix("HTTP/1.1 200"))
    }

    // MARK: - Authorization Passthrough

    @Test("Authorization header passes through to handler alongside Proxy-Authorization")
    func authorizationPassesThroughToHandler() async throws {
        let server = try await HTTPServer.start(
            name: "auth-test",
            requiresAuthentication: true
        ) { req in
            // Echo the Authorization header back in X-Received-Auth so the
            // test can verify it arrived at the handler untouched.
            let auth = req.parsed.header("Authorization") ?? ""
            return HTTPResponse(
                status: 200,
                headers: [("X-Received-Auth", auth)],
                body: Data("OK\n".utf8)
            )
        }
        defer { server.stop() }

        let url = URL(string: "http://127.0.0.1:\(server.port)/test")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(server.token)", forHTTPHeaderField: "Proxy-Authorization")
        request.setValue("Basic dXNlcjpwYXNz", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)

        #expect(http.statusCode == 200)
        #expect(http.value(forHTTPHeaderField: "X-Received-Auth") == "Basic dXNlcjpwYXNz")
    }

    // MARK: - CORS Preflight Auth Exemption

    @Test("preflight without token is answered under permissive CORS")
    func preflightWithoutTokenIsAnsweredUnderPermissiveCORS() async throws {
        // A preflight cannot carry credentials, so it is exempt from
        // authentication — and the library answers it itself, so the exemption
        // never reaches the handler.
        let server = try await HTTPServer.start(
            name: "auth-test",
            requiresAuthentication: true,
            cors: .permissive
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        let raw = "OPTIONS /test HTTP/1.1\r\nHost: 127.0.0.1\r\nAccess-Control-Request-Method: GET\r\n\r\n"
        let response = try await sendRaw(raw, toPort: server.port)
        #expect(response.hasPrefix("HTTP/1.1 204"))
    }

    @Test("preflight without token is authenticated without a CORS policy")
    func preflightWithoutTokenRequiresAuthWithoutCORS() async throws {
        // Without a policy to answer it, a preflight would reach the handler,
        // so the exemption would be an unauthenticated way in.
        let server = try await HTTPServer.start(
            name: "auth-test",
            requiresAuthentication: true
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        let raw = "OPTIONS /test HTTP/1.1\r\nHost: 127.0.0.1\r\nAccess-Control-Request-Method: GET\r\n\r\n"
        let response = try await sendRaw(raw, toPort: server.port)
        #expect(response.hasPrefix("HTTP/1.1 407"))
    }

    @Test("OPTIONS without Access-Control-Request-Method is not a preflight and returns 407")
    func nonPreflightOptionsWithoutTokenReturns407() async throws {
        // `canUser` issues a deliberate `OPTIONS` to read the `Allow` header. It
        // is a request the client made on its own behalf, so it carries the
        // token and must be authenticated like any other — the exemption covers
        // preflights, which cannot carry credentials, and nothing else.
        //
        // Under `.permissive` specifically: that is the only policy where the
        // exemption exists at all, so it is the only one where dropping the
        // `Access-Control-Request-Method` test would let this request through
        // unauthenticated. Under `.none` the assertion would hold no matter
        // what `isPreflight` returned.
        let server = try await HTTPServer.start(
            name: "auth-test",
            requiresAuthentication: true,
            cors: .permissive
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        let raw = "OPTIONS /test HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        let response = try await sendRaw(raw, toPort: server.port)
        #expect(response.hasPrefix("HTTP/1.1 407"))
    }

    @Test("authenticated OPTIONS without Access-Control-Request-Method reaches the handler")
    func nonPreflightOptionsWithTokenReachesHandler() async throws {
        let server = try await HTTPServer.start(
            name: "auth-test",
            requiresAuthentication: true
        ) { request in
            HTTPResponse(status: 200, headers: [("Allow", request.parsed.method)], body: Data())
        }
        defer { server.stop() }

        let raw = "OPTIONS /test HTTP/1.1\r\nHost: 127.0.0.1\r\nRelay-Authorization: Bearer \(server.token)\r\n\r\n"
        let response = try await sendRaw(raw, toPort: server.port)
        #expect(response.hasPrefix("HTTP/1.1 200"))
        #expect(response.contains("Allow: OPTIONS"))
    }

    @Test("permissive CORS answers a preflight itself but forwards a deliberate OPTIONS")
    func permissiveCORSDistinguishesPreflightFromOptions() async throws {
        let server = try await HTTPServer.start(
            name: "auth-test",
            requiresAuthentication: true,
            cors: .permissive
        ) { _ in
            HTTPResponse(status: 200, headers: [("Allow", "GET, POST")], body: Data())
        }
        defer { server.stop() }

        let preflight = "OPTIONS /test HTTP/1.1\r\nHost: 127.0.0.1\r\nAccess-Control-Request-Method: POST\r\n\r\n"
        #expect(try await sendRaw(preflight, toPort: server.port).hasPrefix("HTTP/1.1 204"))

        // Without the preflight header the request belongs to the handler; the
        // library answering it with its own 204 would swallow the `Allow`
        // header `canUser` exists to read.
        let deliberate = "OPTIONS /test HTTP/1.1\r\nHost: 127.0.0.1\r\nRelay-Authorization: Bearer \(server.token)\r\n\r\n"
        let response = try await sendRaw(deliberate, toPort: server.port)
        #expect(response.hasPrefix("HTTP/1.1 200"))
        #expect(response.contains("Allow: GET, POST"))
    }

    @Test("GET without token still returns 407 (only a preflight is exempt)")
    func getWithoutTokenStillReturns407() async throws {
        let server = try await HTTPServer.start(
            name: "auth-test",
            requiresAuthentication: true
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        let url = URL(string: "http://127.0.0.1:\(server.port)/test")!
        let (_, response) = try await URLSession.shared.data(for: URLRequest(url: url))
        let http = try #require(response as? HTTPURLResponse)

        #expect(http.statusCode == 407)
    }

    // MARK: - Delegate Error Bodies

    @Test("a delegate's body answers a refusal the handler never sees")
    func delegateBodyAnswersRefusal() async throws {
        // A client that parses every response the same way — api-fetch reads
        // them all as JSON — reports a text/plain refusal as a parse failure,
        // losing the reason it was refused.
        let server = try await HTTPServer.start(
            name: "error-body-test",
            requiresAuthentication: true,
            delegate: JSONErrorDelegate()
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        let raw = "GET /test HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        let response = try await sendRaw(raw, toPort: server.port)

        #expect(response.hasPrefix("HTTP/1.1 407"))
        #expect(response.contains("Content-Type: application/json"))
        #expect(response.contains(#"{"code":"refused"}"#))
        // The status and the protocol's own headers stay the server's: a
        // delegate supplies the payload, never the semantics.
        #expect(response.contains("Proxy-Authenticate: Bearer"))
    }

    @Test("a refusal falls back to the reason phrase without a delegate")
    func refusalWithoutDelegateIsPlainText() async throws {
        let server = try await HTTPServer.start(
            name: "error-body-test",
            requiresAuthentication: true
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        let raw = "GET /test HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        let response = try await sendRaw(raw, toPort: server.port)

        #expect(response.hasPrefix("HTTP/1.1 407"))
        #expect(response.contains("Content-Type: text/plain"))
        #expect(response.contains("Proxy Authentication Required"))
    }

    // MARK: - Content-Length Requirement

    @Test("POST without Content-Length returns 411")
    func postWithoutContentLengthReturns411() async throws {
        let server = try await HTTPServer.start(
            name: "length-test",
            requiresAuthentication: true
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        // URLSession always adds Content-Length, so use a raw TCP connection.
        let raw = "POST /test HTTP/1.1\r\nHost: 127.0.0.1\r\nProxy-Authorization: Bearer \(server.token)\r\n\r\n"
        let response = try await sendRaw(raw, toPort: server.port)
        #expect(response.hasPrefix("HTTP/1.1 411"))
    }

    @Test("GET without Content-Length returns 200 (body not expected)")
    func getWithoutContentLengthReturns200() async throws {
        let server = try await HTTPServer.start(
            name: "length-test",
            requiresAuthentication: true
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        let url = URL(string: "http://127.0.0.1:\(server.port)/test")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(server.token)", forHTTPHeaderField: "Proxy-Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
    }

    @Test("POST with Content-Length returns 200")
    func postWithContentLengthReturns200() async throws {
        let server = try await HTTPServer.start(
            name: "length-test",
            requiresAuthentication: true
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        let url = URL(string: "http://127.0.0.1:\(server.port)/test")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("hello".utf8)
        request.setValue("Bearer \(server.token)", forHTTPHeaderField: "Proxy-Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
    }

    // MARK: - Auth Disabled

    @Test("authentication is disabled when requiresAuthentication is false")
    func authDisabledPassesThrough() async throws {
        let server = try await HTTPServer.start(
            name: "auth-test",
            requiresAuthentication: false
        ) { _ in
            HTTPResponse(status: 200, body: Data("OK\n".utf8))
        }
        defer { server.stop() }

        let url = URL(string: "http://127.0.0.1:\(server.port)/test")!
        let (_, response) = try await URLSession.shared.data(for: URLRequest(url: url))
        let http = try #require(response as? HTTPURLResponse)

        #expect(http.statusCode == 200)
    }
    // MARK: - Helpers

    /// Sends a raw HTTP request over TCP and returns the response string.
    ///
    /// Needed because URLSession always adds Content-Length automatically.
    private func sendRaw(_ request: String, toPort port: UInt16) async throws -> String {
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

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Swift.Error>) in
            connection.send(content: Data(request.utf8), completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
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
}

/// Answers every server-generated error with a JSON body, the way a consumer
/// whose client parses all responses as JSON would.
private final class JSONErrorDelegate: HTTPServerDelegate {
    func errorBody(for error: HTTPServerError) -> HTTPErrorBody? {
        HTTPErrorBody(contentType: "application/json", data: Data(#"{"code":"refused"}"#.utf8))
    }
}

#endif // canImport(Network)
