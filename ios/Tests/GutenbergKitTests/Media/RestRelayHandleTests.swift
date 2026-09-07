#if canImport(Network)

import Foundation
import Testing
@testable import GutenbergKit
@testable import GutenbergKitHTTP

/// Covers what ``RestRelay/handle(_:)`` sends upstream and what it hands back,
/// against a stubbed session rather than a site.
///
/// The header rewriting on both sides of the hop is the part of the relay that
/// fails silently: an upstream `Access-Control-Allow-Origin` that survives is
/// honored by WebKit over the policy's own, and a surviving `Content-Encoding`
/// makes WebKit decode an already-decoded body. ``RestRelayIntegrationTests``
/// covers the same ground against wp-env, but it is gated on credentials and
/// skipped in CI, so a regression there ships green.
@Suite("RestRelay request handling")
struct RestRelayHandleTests {

    // MARK: - Request rewriting

    @Test("injects the site credential and discards the caller's")
    func injectsSiteCredential() async throws {
        let exchange = try await relay(
            headers: ["Authorization": "Bearer caller-token"]
        )

        #expect(exchange.upstream.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
    }

    @Test("strips the headers that describe the web view's own hop")
    func stripsHopHeaders() async throws {
        // `origin`/`referer`/`sec-fetch-*` describe the `file://` page and are
        // what WordPress rejects in the first place; the relay's own bearer
        // token is not the site's business; the rest are hop-by-hop.
        let exchange = try await relay(headers: [
            "Origin": "file://",
            "Referer": "file:///editor.html",
            "Sec-Fetch-Site": "cross-site",
            "Sec-Fetch-Mode": "cors",
            "Relay-Authorization": "Bearer relay-token",
            "Connection": "keep-alive",
            "Host": "127.0.0.1:8080",
            "Accept-Encoding": "gzip, deflate",
        ])

        for header in [
            "Origin", "Referer", "Sec-Fetch-Site", "Sec-Fetch-Mode",
            "Relay-Authorization", "Connection",
        ] {
            #expect(
                exchange.upstream.value(forHTTPHeaderField: header) == nil,
                "\(header) should not reach the site"
            )
        }
    }

    @Test("strips the headers the request's own Connection names")
    func stripsConnectionNamedHeaders() async throws {
        // RFC 9110 §7.6.1: `Connection` names further headers that describe this
        // hop only, so a forwarding hop consumes those too rather than passing
        // them to the site.
        let exchange = try await relay(headers: [
            "Connection": "X-Hop-Only, close",
            "X-Hop-Only": "1",
        ])

        #expect(exchange.upstream.value(forHTTPHeaderField: "X-Hop-Only") == nil)
    }

    @Test("forwards the headers the site needs")
    func forwardsContentHeaders() async throws {
        let exchange = try await relay(
            method: "POST",
            headers: ["Content-Type": "application/json", "X-HTTP-Method-Override": "PUT"]
        )

        #expect(exchange.upstream.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(exchange.upstream.value(forHTTPHeaderField: "X-HTTP-Method-Override") == "PUT")
        #expect(exchange.upstream.httpMethod == "POST")
    }

    // MARK: - Response rewriting

    @Test("strips the upstream CORS headers that would override the policy's")
    func stripsUpstreamCORSHeaders() async throws {
        // WordPress answers an origin it rejects with an *empty*
        // `Access-Control-Allow-Origin`. The library adds its own headers with
        // `addingHeadersIfAbsent`, so one that survives here wins — and WebKit
        // rejects the response the relay exists to deliver.
        let exchange = try await relay(responseHeaders: [
            "Access-Control-Allow-Origin": "",
            "Access-Control-Allow-Credentials": "true",
            "Access-Control-Expose-Headers": "X-Upstream",
            "Vary": "Origin",
        ])

        for header in [
            "Access-Control-Allow-Origin", "Access-Control-Allow-Credentials", "Vary",
        ] {
            #expect(
                exchange.response.header(header) == nil,
                "\(header) should not reach the web view"
            )
        }
        // The relay's own expose list replaces the upstream's, rather than
        // both arriving and the browser reading whichever came first.
        let exposed = exchange.response.headers.filter { $0.0.lowercased() == "access-control-expose-headers" }
        #expect(exposed.count == 1)
        #expect(exposed.first?.1.contains("Allow") == true)
    }

    @Test("strips the site's cookies rather than rescoping them to loopback")
    func stripsSetCookie() async throws {
        // Passed on, these would be stored against `127.0.0.1:<port>` — a
        // different origin, on a port another process owns once this server
        // stops.
        let exchange = try await relay(responseHeaders: [
            "Set-Cookie": "wordpress_logged_in_abc=user%7C123; Path=/; HttpOnly",
        ])

        #expect(exchange.response.header("Set-Cookie") == nil)
    }

    @Test("strips Content-Encoding, which URLSession already acted on")
    func stripsContentEncoding() async throws {
        // `URLSession` decompresses transparently, so advertising the upstream
        // encoding makes WebKit decode plain bytes a second time.
        let exchange = try await relay(responseHeaders: ["Content-Encoding": "gzip"])

        #expect(exchange.response.header("Content-Encoding") == nil)
    }

    @Test("relays the status, body, and the headers the editor reads")
    func relaysStatusBodyAndHeaders() async throws {
        let exchange = try await relay(
            status: 201,
            responseHeaders: ["Allow": "GET, POST", "X-WP-Total": "42"],
            responseBody: Data(#"{"id":1}"#.utf8)
        )

        #expect(exchange.response.status == 201)
        #expect(exchange.response.body == Data(#"{"id":1}"#.utf8))
        #expect(exchange.response.header("Allow") == "GET, POST")
        #expect(exchange.response.header("X-WP-Total") == "42")
    }

    @Test("answers an upstream failure as a relay error the editor can decode")
    func reportsUpstreamFailure() async throws {
        let exchange = try await relay(failure: URLError(.notConnectedToInternet))

        #expect(exchange.response.status == 502)
        let body = try #require(String(data: exchange.response.body, encoding: .utf8))
        #expect(body.contains("relay_upstream_failed"))
    }

    @Test("replays a streamed body across a redirect it follows")
    func replaysStreamedBodyAcrossRedirect() async throws {
        // A body over the in-memory threshold is spilled to disk and sent as
        // a one-shot stream. A `308` has `URLSession` resend it, which needs
        // a fresh stream or fails with `requestBodyStreamExhausted`. The site
        // is a real server rather than a stub: `URLSession` asks for a
        // replacement only for a stream it drained itself.
        let contents = Data(repeating: 0x41, count: 100_000)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try contents.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let resent = ReceivedBody()
        let site = try await HTTPServer.start(name: "relay-redirect-site", requiresAuthentication: false) { request in
            guard request.parsed.query.isEmpty else {
                resent.record((try? await request.parsed.body?.data) ?? Data())
                return HTTPResponse(status: 201)
            }
            // Relative, as RFC 9110 allows, since the port is not known
            // until the server has started.
            return HTTPResponse(status: 308, headers: [("Location", "/wp-json/wp/v2/media?redirected=1")])
        }
        defer { site.stop() }

        let relay = RestRelay(
            configuration: EditorConfigurationBuilder(
                postType: .post,
                siteURL: URL(string: "http://127.0.0.1:\(site.port)")!,
                siteApiRoot: URL(string: "http://127.0.0.1:\(site.port)/wp-json/")!,
                authHeader: "Bearer test-token"
            ).build()
        )
        let parsed = ParsedHTTPRequest.complete(
            method: "POST",
            target: "/proxy/wp/v2/media",
            httpVersion: "HTTP/1.1",
            headers: ["Content-Type": "image/jpeg"],
            body: RequestBody(fileURL: file)
        )

        let response = await relay.handle(HTTPServer.Request(parsed: parsed, parseDuration: .zero))

        #expect(response.status == 201)
        #expect(resent.body == contents)
    }

    @Test("refuses a path outside the API root before sending anything")
    func refusesForbiddenPath() async throws {
        let exchange = try await relay(target: "/proxy/../wp-admin/")

        #expect(exchange.response.status == 403)
        #expect(exchange.sentRequest == nil, "nothing should have been sent upstream")
    }

    // MARK: - Helpers

    /// One relayed exchange: what reached the stub, and what the relay returned.
    private struct Exchange {
        let sentRequest: URLRequest?
        let response: HTTPResponse

        /// The request that reached the stub. Fails the test if none did.
        var upstream: URLRequest {
            guard let sentRequest else {
                Issue.record("No request reached the stubbed session")
                return URLRequest(url: URL(string: "about:blank")!)
            }
            return sentRequest
        }
    }

    /// Relays one request through a stubbed session and reports both sides.
    private func relay(
        target: String = "/proxy/wp/v2/posts?_locale=user",
        method: String = "GET",
        headers: [String: String] = [:],
        status: Int = 200,
        responseHeaders: [String: String] = [:],
        responseBody: Data = Data(),
        failure: (any Error)? = nil
    ) async throws -> Exchange {
        let stub = StubURLProtocol.Stub(
            status: status,
            headers: responseHeaders,
            body: responseBody,
            failure: failure
        )
        let stubbed = StubURLProtocol.makeSession(stub: stub)
        defer { stubbed.finish() }

        let relay = RestRelay(
            configuration: EditorConfigurationBuilder(
                postType: .post,
                siteURL: URL(string: "https://example.com")!,
                siteApiRoot: URL(string: "https://example.com/wp-json/")!,
                authHeader: "Bearer test-token"
            ).build(),
            session: stubbed.session
        )

        let parsed = ParsedHTTPRequest.complete(
            method: method,
            target: target,
            httpVersion: "HTTP/1.1",
            headers: headers,
            body: nil
        )
        let response = await relay.handle(
            HTTPServer.Request(parsed: parsed, parseDuration: .zero)
        )

        return Exchange(sentRequest: stubbed.recorder.request, response: response)
    }
}

/// The body a test server received, handed across from its handler.
private final class ReceivedBody: @unchecked Sendable {
    private let lock = NSLock()
    private var _body: Data?

    var body: Data? {
        lock.withLock { _body }
    }

    func record(_ body: Data) {
        lock.withLock { _body = body }
    }
}

private extension HTTPResponse {
    /// The value of the first header matching `name`, case-insensitively.
    func header(_ name: String) -> String? {
        headers.first { $0.0.lowercased() == name.lowercased() }?.1
    }
}

#endif
