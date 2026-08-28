import Foundation
import Testing

@testable import GutenbergKit

@Suite("RestRelay upstream URLs")
struct RestRelayUpstreamURLTests {

    private func upstream(_ relay: String, root: String) -> String? {
        RestRelay.upstreamURL(
            for: URL(string: relay)!,
            siteApiRoot: URL(string: root)!
        )?.absoluteString
    }

    @Test("resolves the relay path against the site API root")
    func resolvesPath() {
        #expect(
            upstream("gbk-rest:///wp/v2/posts", root: "https://example.com/wp-json/")
                == "https://example.com/wp-json/wp/v2/posts"
        )
    }

    @Test("carries the query through unchanged")
    func carriesQuery() {
        #expect(
            upstream("gbk-rest:///wp/v2/posts?context=edit&_locale=user", root: "https://example.com/wp-json/")
                == "https://example.com/wp-json/wp/v2/posts?context=edit&_locale=user"
        )
    }

    @Test("joins cleanly when the API root has no trailing slash")
    func joinsUnslashedRoot() {
        #expect(
            upstream("gbk-rest:///wp/v2/posts", root: "https://example.com/wp-json")
                == "https://example.com/wp-json/wp/v2/posts"
        )
    }

    @Test("preserves percent-encoding rather than re-encoding it")
    func preservesEncoding() {
        #expect(
            upstream("gbk-rest:///wp/v2/search?search=100%25%20cotton", root: "https://example.com/wp-json/")
                == "https://example.com/wp-json/wp/v2/search?search=100%25%20cotton"
        )
    }

    /// A site on plain permalinks has an API root that already carries a query,
    /// so the relayed path's own `?` has to become `&` to stay in the same query
    /// string. `createRootURLMiddleware` does this for direct requests; the
    /// relay root it is given has no query, so the relay does it natively.
    @Test("merges the query into an API root that is already a query")
    func mergesIntoPlainPermalinkRoot() {
        #expect(
            upstream("gbk-rest:///wp/v2/posts?context=edit", root: "https://example.com/?rest_route=/")
                == "https://example.com/?rest_route=/wp/v2/posts&context=edit"
        )
    }

    @Test("leaves a plain-permalink path alone when it has no query of its own")
    func plainPermalinkWithoutQuery() {
        #expect(
            upstream("gbk-rest:///wp/v2/posts", root: "https://example.com/?rest_route=/")
                == "https://example.com/?rest_route=/wp/v2/posts"
        )
    }

    /// The path is the whole of the target, so the relay cannot be pointed at
    /// another host. A URL that tries to smuggle one in an authority is refused
    /// rather than reinterpreted as a path.
    @Test("refuses a relay URL carrying an authority")
    func refusesAuthority() {
        #expect(upstream("gbk-rest://evil.example.com/wp/v2/posts", root: "https://example.com/wp-json/") == nil)
    }

    @Test("refuses a URL that is not addressed to the relay scheme")
    func refusesForeignScheme() {
        #expect(upstream("https://evil.example.com/wp/v2/posts", root: "https://example.com/wp-json/") == nil)
    }
}

@Suite("RestRelay response headers")
struct RestRelayResponseHeaderTests {

    private func relayed(_ upstream: [String: String], status: Int = 200) -> [String: String] {
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com/wp-json/wp/v2/posts")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: upstream
        )!
        return RestRelay.responseHeaders(from: response)
    }

    /// WebKit enforces CORS on a custom scheme's response even though it never
    /// preflights the request, and a `file://` document's `null` origin matches
    /// nothing but `*`. Without this the response is discarded.
    @Test("allows any origin")
    func allowsAnyOrigin() {
        #expect(relayed([:])["Access-Control-Allow-Origin"] == "*")
    }

    /// With `*` but nothing exposed, the body is readable while every response
    /// header reads back as null — which silently breaks `canUser` (`Allow`)
    /// and pagination.
    @Test("exposes the response headers the editor reads")
    func exposesReadHeaders() {
        let exposed = relayed([:])["Access-Control-Expose-Headers"]
        for header in ["Allow", "Link", "X-WP-Total", "X-WP-TotalPages"] {
            #expect(exposed?.contains(header) == true)
        }
    }

    @Test("forwards the headers the editor reads")
    func forwardsReadHeaders() {
        let headers = relayed([
            "Allow": "GET, POST",
            "Link": "<https://example.com/wp-json/wp/v2/posts?page=2>; rel=\"next\"",
            "X-WP-Total": "37",
            "Content-Type": "application/json"
        ])
        #expect(headers["Allow"] == "GET, POST")
        #expect(headers["Link"] == "<https://example.com/wp-json/wp/v2/posts?page=2>; rel=\"next\"")
        #expect(headers["X-WP-Total"] == "37")
        #expect(headers["Content-Type"] == "application/json")
    }

    /// WordPress answers an origin it rejects with an empty
    /// `Access-Control-Allow-Origin`. Forwarded, it would override the `*` this
    /// relay adds and WebKit would discard the response — the exact failure the
    /// relay exists to avoid.
    @Test("drops the upstream's own CORS headers")
    func dropsUpstreamCORS() {
        let headers = relayed([
            "Access-Control-Allow-Origin": "",
            "Access-Control-Expose-Headers": "X-Something",
            "Vary": "Origin"
        ])
        #expect(headers["Access-Control-Allow-Origin"] == "*")
        #expect(headers["Access-Control-Expose-Headers"]?.contains("X-Something") == false)
        #expect(headers["Vary"] == nil)
    }

    /// URLSession has already decompressed the body, so the upstream's encoding
    /// and length no longer describe what the handler delivers.
    @Test("drops transport headers that no longer describe the body")
    func dropsTransportHeaders() {
        let headers = relayed([
            "Content-Encoding": "gzip",
            "Content-Length": "512",
            "Connection": "keep-alive"
        ])
        #expect(headers["Content-Encoding"] == nil)
        #expect(headers["Content-Length"] == nil)
        #expect(headers["Connection"] == nil)
    }
}

@Suite("RestRelay error responses")
struct RestRelayErrorResponseTests {

    @Test("are shaped like a WordPress REST error")
    func wordPressShaped() throws {
        let response = RelayResponse.error(status: 502, code: "relay_request_failed", message: "Boom")

        #expect(response.statusCode == 502)
        #expect(response.headers["Content-Type"] == "application/json")
        #expect(response.headers["Access-Control-Allow-Origin"] == "*")

        let payload = try #require(
            try JSONSerialization.jsonObject(with: response.body) as? [String: String]
        )
        #expect(payload["code"] == "relay_request_failed")
        #expect(payload["message"] == "Boom")
    }
}

@Suite("RestRelay request handling")
struct RestRelayRequestTests {

    /// Points at a port nothing listens on: the cases below are decided before
    /// the relay reaches the network, and the one that does get that far should
    /// be refused locally rather than sent anywhere.
    private let relay = RestRelay(
        siteApiRoot: URL(string: "http://127.0.0.1:1/wp-json/")!,
        authHeader: "Bearer test-token"
    )

    private func request(_ url: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        return request
    }

    @Test("rejects a request it cannot resolve to the site")
    func rejectsUnresolvableURL() async throws {
        let response = await relay.response(for: request("gbk-rest://elsewhere/wp/v2/posts"))

        #expect(response.statusCode == 400)
        let payload = try JSONSerialization.jsonObject(with: response.body) as? [String: String]
        #expect(payload?["code"] == "relay_invalid_url")
    }

    /// WebKit withholds a blob-backed body from a scheme handler with no error.
    /// Relaying the bodyless write would have WordPress accept it as a no-op and
    /// the editor report success, so it fails loudly instead. Nothing is sent
    /// upstream, which is why this needs no network.
    @Test("fails loudly when the marked request body was withheld")
    func failsOnWithheldBody() async throws {
        var withheld = request("gbk-rest:///wp/v2/media", method: "POST")
        withheld.setValue("attached", forHTTPHeaderField: RestRelay.bodyMarkerHeader)

        let response = await relay.response(for: withheld)

        #expect(response.statusCode == 500)
        let payload = try JSONSerialization.jsonObject(with: response.body) as? [String: String]
        #expect(payload?["code"] == "relay_body_unavailable")
    }

    /// The marker is what distinguishes a withheld body from one that was never
    /// sent: api-fetch's `httpV1Middleware` stamps `Content-Type` on every
    /// PUT/PATCH/DELETE, so a bodyless `deleteEntityRecord` looks identical to a
    /// dropped upload without it.
    @Test("does not fire the body guard on an unmarked bodyless write")
    func allowsUnmarkedBodylessWrite() async throws {
        var delete = request("gbk-rest:///wp/v2/posts/1", method: "POST")
        delete.setValue("application/json", forHTTPHeaderField: "Content-Type")
        delete.setValue("DELETE", forHTTPHeaderField: "X-HTTP-Method-Override")

        let response = await relay.response(for: delete)

        // It reaches the network and fails there, which is the point: it was
        // not refused before it was sent.
        let payload = try JSONSerialization.jsonObject(with: response.body) as? [String: String]
        #expect(payload?["code"] == "relay_request_failed")
    }
}

@Suite("RestRelay redirect guard")
struct RestRelayRedirectGuardTests {

    private func guardFor(_ root: String) -> RedirectGuard {
        RedirectGuard(apiRoot: URL(string: root)!)
    }

    @Test("follows a redirect that stays on the site")
    func allowsSameHost() {
        let redirectGuard = guardFor("https://example.com/wp-json/")
        #expect(redirectGuard.isAllowed(URL(string: "https://example.com/wp-json/wp/v2/posts/2")!))
        #expect(redirectGuard.isAllowed(URL(string: "https://EXAMPLE.com/elsewhere")!))
    }

    /// `URLSession` follows redirects on its own, carrying the natively
    /// injected `Authorization` to whatever host the site names and relaying
    /// that host's body back — so containment has to hold on every hop, not
    /// just the first.
    @Test("refuses a redirect to another host")
    func refusesCrossHost() {
        let redirectGuard = guardFor("https://example.com/wp-json/")
        #expect(!redirectGuard.isAllowed(URL(string: "https://evil.example.net/wp-json/")!))
        #expect(!redirectGuard.isAllowed(URL(string: "https://example.com.evil.net/")!))
    }

    @Test("refuses a downgrade to an insecure scheme")
    func refusesDowngrade() {
        let redirectGuard = guardFor("https://example.com/wp-json/")
        #expect(!redirectGuard.isAllowed(URL(string: "http://example.com/wp-json/")!))
    }

    /// A site already served over `http` (a local dev environment) has nothing
    /// to downgrade, and its redirect to `https` is an upgrade.
    @Test("allows either scheme when the site is already insecure")
    func allowsUpgradeFromInsecureSite() {
        let redirectGuard = guardFor("http://localhost:8888/wp-json/")
        #expect(redirectGuard.isAllowed(URL(string: "http://localhost:8888/wp-json/wp/v2/posts")!))
        #expect(redirectGuard.isAllowed(URL(string: "https://localhost:8888/wp-json/wp/v2/posts")!))
    }
}
