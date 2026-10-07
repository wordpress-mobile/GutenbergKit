import Foundation
import Testing
@testable import GutenbergKit

/// Covers what ``RestRelay/handle(_:)`` sends upstream and what it hands back,
/// against a stubbed session rather than a site.
///
/// The header rewriting on both sides of the hop is the part of the relay that
/// fails silently: an upstream `Access-Control-Allow-Origin` that survives is
/// honored by WebKit over the policy's own, and a surviving `Content-Encoding`
/// makes WebKit decode an already-decoded body.
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
        // what WordPress rejects in the first place; the page's cookies are
        // not how the relay authenticates; the rest belong to the hop.
        let exchange = try await relay(headers: [
            "Origin": "file://",
            "Referer": "file:///editor.html",
            "Sec-Fetch-Site": "cross-site",
            "Sec-Fetch-Mode": "cors",
            "Cookie": "wordpress_logged_in_abc=1",
            "Connection": "keep-alive",
            "Accept-Encoding": "gzip, deflate",
        ])

        for header in [
            "Origin", "Referer", "Sec-Fetch-Site", "Sec-Fetch-Mode",
            "Cookie", "Connection",
        ] {
            #expect(
                exchange.upstream.value(forHTTPHeaderField: header) == nil,
                "\(header) should not reach the site"
            )
        }
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
        // `Access-Control-Allow-Origin`. One that survived would replace the
        // relay's own, and WebKit would reject the response the relay exists
        // to deliver.
        let exchange = try await relay(responseHeaders: [
            "Access-Control-Allow-Origin": "",
            "Access-Control-Allow-Credentials": "true",
            "Access-Control-Expose-Headers": "X-Upstream",
            "Vary": "Origin",
        ])

        for header in ["Access-Control-Allow-Credentials", "Vary"] {
            #expect(
                exchange.response.header(header) == nil,
                "\(header) should not reach the web view"
            )
        }
        // The relay's own headers replace the upstream's, rather than both
        // arriving and the browser reading whichever came first.
        #expect(exchange.response.header("Access-Control-Allow-Origin") == "*")
        let exposed = exchange.response.headers.filter { $0.key.lowercased() == "access-control-expose-headers" }
        #expect(exposed.count == 1)
        #expect(exposed.first?.value.hasPrefix("*, Allow") == true)
    }

    @Test("strips the site's cookies rather than rescoping them to the relay")
    func stripsSetCookie() async throws {
        // Passed on, these would be stored against the relay's scheme, a
        // different origin from the site that set them.
        let exchange = try await relay(responseHeaders: [
            "Set-Cookie": "wordpress_logged_in_abc=user%7C123; Path=/; HttpOnly",
        ])

        #expect(exchange.response.header("Set-Cookie") == nil)
    }

    @Test("strips Content-Encoding and Content-Length, which URLSession already acted on")
    func stripsContentEncoding() async throws {
        // `URLSession` decompresses transparently, so advertising the upstream
        // encoding makes WebKit decode plain bytes a second time, and the
        // upstream length is the compressed one.
        let exchange = try await relay(responseHeaders: ["Content-Encoding": "gzip", "Content-Length": "12"])

        #expect(exchange.response.header("Content-Encoding") == nil)
        #expect(exchange.response.header("Content-Length") == nil)
    }

    @Test("sends the page's body on, and exposes a block's own response headers")
    func relaysBodiesAndPluginHeaders() async throws {
        // A VideoPress chunk: the page read its `Blob` into an `ArrayBuffer`,
        // which WebKit delivers as `httpBody`, and the block reads the video
        // it made off the response headers.
        let exchange = try await relay(
            target: "/proxy/videopress/v1/upload-relay/abc",
            method: "POST",
            headers: ["Content-Type": "application/offset+octet-stream", "Upload-Offset": "0"],
            body: Data("chunk bytes".utf8),
            status: 204,
            responseHeaders: ["x-videopress-upload-guid": "eDeLfBNN"]
        )

        #expect(exchange.upstream.url?.absoluteString == "https://example.com/wp-json/videopress/v1/upload-relay/abc")
        #expect(exchange.sentBody == Data("chunk bytes".utf8))
        #expect(exchange.upstream.value(forHTTPHeaderField: "Upload-Offset") == "0")
        #expect(exchange.response.status == 204)
        #expect(exchange.response.header("x-videopress-upload-guid") == "eDeLfBNN")
        #expect(exchange.response.header("Access-Control-Expose-Headers")?.hasPrefix("*") == true)
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
        let sentBody: Data?
        let response: SchemeResponse

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
        body: Data? = nil,
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

        var request = URLRequest(url: try #require(URL(string: "gbk-rest://relay\(target)")))
        request.httpMethod = method
        request.allHTTPHeaderFields = headers
        request.httpBody = body
        let response = await relay.handle(request)

        return Exchange(sentRequest: stubbed.recorder.request, sentBody: stubbed.recorder.request?.httpBody, response: response)
    }
}

private extension SchemeResponse {
    /// The value of the first header matching `name`, case-insensitively.
    func header(_ name: String) -> String? {
        headers.first { $0.key.lowercased() == name.lowercased() }?.value
    }
}
