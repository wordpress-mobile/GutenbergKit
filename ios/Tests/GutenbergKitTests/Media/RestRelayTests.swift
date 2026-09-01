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

    @Test("refuses dot segments whose separators are encoded too")
    func refusesDotSegmentsWithEncodedSeparators() {
        // The whole traversal is one literal segment, so it is only a dot
        // segment to a server that decodes the separator before normalizing.
        let relay = makeRelay(apiRoot: Self.prettyRoot)
        #expect(relay.upstreamURL(for: request("/proxy/%2e%2e%2f%2e%2e%2fwp-admin/admin-ajax.php")) == nil)
        #expect(relay.upstreamURL(for: request("/proxy/wp%5C..%5Cwp-admin/")) == nil)
        #expect(relay.upstreamURL(for: request("/proxy/wp\\..\\wp-admin/")) == nil)
    }

    @Test("an encoded slash within a segment is not a dot segment")
    func allowsEncodedSlashesWithinSegments() {
        // A template ID is `theme//slug`, encoded into a single path segment.
        let relay = makeRelay(apiRoot: Self.prettyRoot)
        #expect(
            relay.upstreamURL(for: request("/proxy/wp/v2/templates/twentytwentyfour%2F%2Fsingle"))?.absoluteString
                == "https://example.com/wp-json/wp/v2/templates/twentytwentyfour%2F%2Fsingle"
        )
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

    @Test("drops a rest_route parameter that would replace the path")
    func dropsCallerSuppliedRestRoute() {
        // WordPress prefers `$_GET['rest_route']` over the value a permalink
        // rewrite produced, so without this the caller's parameter, not the
        // validated path, would select the route — on either root shape.
        let pretty = makeRelay(apiRoot: Self.prettyRoot)
        #expect(
            pretty.upstreamURL(for: request("/proxy/wp/v2/posts?rest_route=/wp/v2/users&_locale=user"))?.absoluteString
                == "https://example.com/wp-json/wp/v2/posts?_locale=user"
        )

        let plain = makeRelay(apiRoot: Self.plainRoot)
        #expect(
            plain.upstreamURL(for: request("/proxy/wp/v2/posts?rest_route=/wp/v2/users"))?.absoluteString
                == "https://example.com/?rest_route=/wp/v2/posts"
        )
        // Percent-encoded because PHP decodes the name before matching it.
        #expect(
            pretty.upstreamURL(for: request("/proxy/wp/v2/posts?rest%5Froute=/wp/v2/users"))?.absoluteString
                == "https://example.com/wp-json/wp/v2/posts"
        )
    }

    @Test("keeps parameters whose names merely resemble rest_route")
    func keepsSimilarlyNamedParameters() {
        let relay = makeRelay(apiRoot: Self.prettyRoot)
        #expect(
            relay.upstreamURL(for: request("/proxy/wp/v2/posts?rest_routes=1&x_rest_route=2"))?.absoluteString
                == "https://example.com/wp-json/wp/v2/posts?rest_routes=1&x_rest_route=2"
        )
    }

    @Test("refuses a request outside the relay route")
    func refusesForeignRoute() {
        let relay = makeRelay(apiRoot: Self.prettyRoot)
        #expect(relay.upstreamURL(for: request("/upload")) == nil)
        #expect(relay.upstreamURL(for: request("/proxying/wp/v2/posts")) == nil)
    }

    // MARK: - Redirects

    @Test("follows a redirect that stays under the API root")
    func followsContainedRedirect() {
        let followed = redirectDecision(to: "https://example.com/wp-json/wp/v2/posts/1")

        #expect(followed?.url?.absoluteString == "https://example.com/wp-json/wp/v2/posts/1")
    }

    @Test("refuses a redirect that leaves the API root")
    func refusesEscapingRedirect() {
        // Another host, another path on the same site, and a scheme downgrade.
        // The credential should follow the request only to the API it was
        // configured for.
        for target in [
            "https://elsewhere.example/wp-json/wp/v2/posts",
            "https://example.com/wp-login.php",
            "http://example.com/wp-json/wp/v2/posts",
        ] {
            #expect(redirectDecision(to: target) == nil, "should refuse \(target)")
        }
    }

    @Test("follows a redirect that only upgrades the scheme")
    func followsSchemeUpgrade() {
        // A site whose `siteurl` is `http` but which answers on `https` is the
        // deployment `relayUpstreamPath` already relays; refusing its redirect
        // here would fail every request the layer above deliberately sent.
        let redirectGuard = RestRelay.RedirectGuard(allowedPrefix: "http://example.com/wp-json/")
        let followed = decide(redirectGuard, target: "https://example.com/wp-json/wp/v2/posts")

        #expect(followed?.url?.absoluteString == "https://example.com/wp-json/wp/v2/posts")
        #expect(redirectGuard.refusedTarget == nil)
    }

    @Test("the scheme upgrade admits nothing else")
    func schemeUpgradeStaysContained() {
        // Upgrading the scheme must not also relax the host or the path.
        for target in [
            "https://elsewhere.example/wp-json/wp/v2/posts",
            "https://example.com/wp-login.php",
            "https://www.example.com/wp-json/wp/v2/posts",
            "https://example.com:8443/wp-json/wp/v2/posts",
        ] {
            let redirectGuard = RestRelay.RedirectGuard(allowedPrefix: "http://example.com/wp-json/")
            #expect(decide(redirectGuard, target: target) == nil, "should refuse \(target)")
        }
    }

    @Test("reports the refused target so the editor can say what happened")
    func recordsRefusedTarget() {
        // Without this the relay would hand back the 3xx itself, and `fetch`
        // — which follows redirects by default — would chase it to the host
        // the guard just declined.
        let redirectGuard = RestRelay.RedirectGuard(allowedPrefix: "https://example.com/wp-json/")
        #expect(redirectGuard.refusedTarget == nil)

        _ = decide(redirectGuard, target: "https://elsewhere.example/x")

        #expect(redirectGuard.refusedTarget == "https://elsewhere.example/x")
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

    /// The request a fresh guard would follow for a redirect to `target`, or
    /// `nil` if it refuses.
    private func redirectDecision(to target: String) -> URLRequest? {
        decide(
            RestRelay.RedirectGuard(allowedPrefix: "https://example.com/wp-json/"),
            target: target
        )
    }

    /// Asks `redirectGuard` whether to follow a redirect to `target`.
    private func decide(_ redirectGuard: RestRelay.RedirectGuard, target: String) -> URLRequest? {
        let url = URL(string: target)!
        var followed: URLRequest?
        redirectGuard.urlSession(
            .shared,
            task: URLSession.shared.dataTask(with: url),
            willPerformHTTPRedirection: HTTPURLResponse(
                url: URL(string: "https://example.com/wp-json/wp/v2/posts")!,
                statusCode: 301,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": target]
            )!,
            newRequest: URLRequest(url: url),
            completionHandler: { followed = $0 }
        )
        return followed
    }
}

#endif // canImport(Network)
