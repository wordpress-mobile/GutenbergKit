#if canImport(Network)

import Foundation
import GutenbergKitHTTP
import Testing
@testable import GutenbergKit

/// Covers how a relayed request's path becomes an upstream URL. This is the
/// relay's containment boundary: the web view supplies a path, never a URL, and
/// nothing it can put in that path may address anything outside the site API
/// root.
@Suite("RestRelay upstream URL")
struct RestRelayTests {

    /// A site on pretty permalinks.
    private static let prettyRoot = URL(string: "https://example.com/wp-json/")!

    /// A site on plain permalinks, where the API root carries a query and the
    /// path has to merge into it rather than start a second one.
    private static let plainRoot = URL(string: "https://example.com/?rest_route=/")!

    // MARK: - Path resolution

    @Test("appends the path and query to the API root")
    func appendsPathAndQuery() {
        let relay = makeRelay(apiRoot: Self.prettyRoot)
        #expect(
            relay.upstreamURL(for: request("/proxy/wp/v2/posts?_locale=user"))?.absoluteString
                == "https://example.com/wp-json/wp/v2/posts?_locale=user"
        )
    }

    @Test("resolves the API root itself for a bare route")
    func bareRouteResolvesToAPIRoot() {
        let relay = makeRelay(apiRoot: Self.prettyRoot)
        #expect(relay.upstreamURL(for: request("/proxy"))?.absoluteString == "https://example.com/wp-json/")
        #expect(relay.upstreamURL(for: request("/proxy/"))?.absoluteString == "https://example.com/wp-json/")
    }

    @Test("adds a trailing slash to an API root configured without one")
    func normalizesAPIRootWithoutTrailingSlash() {
        let relay = makeRelay(apiRoot: URL(string: "https://example.com/wp-json")!)
        #expect(
            relay.upstreamURL(for: request("/proxy/wp/v2/posts"))?.absoluteString
                == "https://example.com/wp-json/wp/v2/posts"
        )
    }

    @Test("continues the query of an API root that already carries one")
    func mergesIntoAQueryCarryingAPIRoot() {
        // Plain permalinks: `https://example.com/?rest_route=/` + `wp/v2/posts`
        // has to produce one query string, not two — mirroring what
        // `createRootURLMiddleware` does on the JavaScript side.
        let relay = makeRelay(apiRoot: Self.plainRoot)
        #expect(
            relay.upstreamURL(for: request("/proxy/wp/v2/posts?_locale=user"))?.absoluteString
                == "https://example.com/?rest_route=/wp/v2/posts&_locale=user"
        )
        #expect(
            relay.upstreamURL(for: request("/proxy/wp/v2/posts?a=1&b=2"))?.absoluteString
                == "https://example.com/?rest_route=/wp/v2/posts&a=1&b=2"
        )
    }

    @Test("preserves percent-encoding in the query")
    func preservesPercentEncoding() {
        let relay = makeRelay(apiRoot: Self.prettyRoot)
        #expect(
            relay.upstreamURL(for: request("/proxy/wp/v2/search?search=caf%C3%A9&per_page=100"))?.absoluteString
                == "https://example.com/wp-json/wp/v2/search?search=caf%C3%A9&per_page=100"
        )
    }

    // MARK: - Containment

    @Test("refuses a path that walks out of the API root")
    func refusesDotSegments() {
        let relay = makeRelay(apiRoot: Self.prettyRoot)
        #expect(relay.upstreamURL(for: request("/proxy/../wp-admin/admin-ajax.php")) == nil)
        #expect(relay.upstreamURL(for: request("/proxy/wp/v2/../../../wp-admin/")) == nil)
        #expect(relay.upstreamURL(for: request("/proxy/wp/v2/./posts")) == nil)
    }

    @Test("refuses percent-encoded dot segments")
    func refusesEncodedDotSegments() {
        // `URLSession` leaves these encoded, but the receiving server may decode
        // before resolving, so they are refused here rather than forwarded.
        let relay = makeRelay(apiRoot: Self.prettyRoot)
        #expect(relay.upstreamURL(for: request("/proxy/%2e%2e/wp-admin/")) == nil)
        #expect(relay.upstreamURL(for: request("/proxy/wp/%2E%2E/%2e%2e/")) == nil)
    }

    @Test("a dot inside a path segment is not a dot segment")
    func allowsDotsWithinSegments() {
        let relay = makeRelay(apiRoot: Self.prettyRoot)
        #expect(
            relay.upstreamURL(for: request("/proxy/oembed/1.0/embed?url=https%3A%2F%2Fexample.com"))?.absoluteString
                == "https://example.com/wp-json/oembed/1.0/embed?url=https%3A%2F%2Fexample.com"
        )
    }

    @Test("an absolute URL in the path stays under the API root")
    func absoluteURLInPathStaysContained() {
        // There is no URL to resolve, so a smuggled one becomes an ordinary
        // (404ing) path segment rather than another host.
        let relay = makeRelay(apiRoot: Self.prettyRoot)
        let resolved = relay.upstreamURL(for: request("/proxy/https://elsewhere.example/x"))
        #expect(resolved?.absoluteString.hasPrefix("https://example.com/wp-json/") == true)
        #expect(relay.upstreamURL(for: request("/proxy//elsewhere.example/x"))?.host() == "example.com")
    }

    @Test("refuses a request outside the relay route")
    func refusesForeignRoute() {
        let relay = makeRelay(apiRoot: Self.prettyRoot)
        #expect(relay.upstreamURL(for: request("/upload")) == nil)
        #expect(relay.upstreamURL(for: request("/proxying/wp/v2/posts")) == nil)
    }

    // MARK: - Routing

    @Test("claims its own route and nothing else")
    func routeMatching() {
        #expect(RestRelay.handles(request("/proxy")))
        #expect(RestRelay.handles(request("/proxy/wp/v2/posts?_locale=user")))
        #expect(!RestRelay.handles(request("/upload")))
        #expect(!RestRelay.handles(request("/proxying")))
    }

    // MARK: - Helpers

    private func makeRelay(apiRoot: URL) -> RestRelay {
        RestRelay(
            configuration: EditorConfigurationBuilder(
                postType: .post,
                siteURL: URL(string: "https://example.com")!,
                siteApiRoot: apiRoot,
                authHeader: "Bearer test-token"
            ).build()
        )
    }

    private func request(_ target: String, method: String = "GET") -> ParsedHTTPRequest {
        .complete(method: method, target: target, httpVersion: "HTTP/1.1", headers: [:], body: nil)
    }
}

#endif // canImport(Network)
