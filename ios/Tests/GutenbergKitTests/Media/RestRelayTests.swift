import Foundation
import Testing
@testable import GutenbergKit

/// Covers how a relayed request becomes an upstream URL. On the site API route
/// this is the relay's containment boundary: the web view supplies a path, never
/// a URL, and nothing it can put in that path may address anything outside the
/// site API root. The forward route takes a URL, and never carries the site
/// credential.
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

    @Test("decodes the route of a root advertised with it encoded")
    func decodesAdvertisedPlainPermalinkRoot() {
        // WordPress advertises a plain-permalink root through `add_query_arg`,
        // which percent-encodes the route: `index.php?rest_route=%2F`. The
        // slash termination has to land inside that value, since WordPress
        // reads `rest_route=%2F/wp/v2/posts` as the route `//wp/v2/posts`.
        let relay = makeRelay(apiRoot: URL(string: "https://example.com/index.php?rest_route=%2F")!)
        #expect(
            relay.upstreamURL(for: request("/proxy/wp/v2/posts?_locale=user"))?.absoluteString
                == "https://example.com/index.php?rest_route=/wp/v2/posts&_locale=user"
        )
        #expect(
            relay.upstreamURL(for: request("/proxy"))?.absoluteString
                == "https://example.com/index.php?rest_route=/"
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

    @Test("forwards the query verbatim, rest_route included")
    func forwardsQueryVerbatim() {
        // WordPress prefers `$_GET['rest_route']` over the route the path
        // names, so the caller picks the route whichever way it spells the
        // parameter. Deliberately not filtered: see the type's Security notes.
        let relay = makeRelay(apiRoot: Self.prettyRoot)
        #expect(
            relay.upstreamURL(for: request("/proxy/wp/v2/posts?rest_route=/wp/v2/users&_locale=user"))?.absoluteString
                == "https://example.com/wp-json/wp/v2/posts?rest_route=/wp/v2/users&_locale=user"
        )
    }

    @Test("refuses a request outside the relay route")
    func refusesForeignRoute() {
        let relay = makeRelay(apiRoot: Self.prettyRoot)
        #expect(relay.upstreamURL(for: request("/sessions")) == nil)
        #expect(relay.upstreamURL(for: request("/proxying/wp/v2/posts")) == nil)
    }

    // MARK: - Other hosts

    @Test("reads the URL a forwarded request is for")
    func readsForwardedURL() {
        let relay = makeRelay(apiRoot: Self.prettyRoot)
        #expect(
            relay.forwardedURL(for: request("/forward?url=https%3A%2F%2Fexample.org%2Fapi%3Fq%3Da%2520b%26x%3D1"))?.absoluteString
                == "https://example.org/api?q=a%20b&x=1"
        )
        #expect(
            relay.forwardedURL(for: request("/forward?url=http%3A%2F%2F127.0.0.1%3A8888%2Fwp-json%2F"))?.absoluteString
                == "http://127.0.0.1:8888/wp-json/"
        )
    }

    @Test("forwards only to http and https URLs")
    func forwardsOnlyToWebURLs() {
        let relay = makeRelay(apiRoot: Self.prettyRoot)
        for target in [
            "/forward?url=file%3A%2F%2F%2Fetc%2Fhosts",
            "/forward?url=gbk-upload%3A%2F%2Fupload%2Fsessions",
            "/forward?url=https%3Ano-host",
            "/forward?url=%2Frelative%2Fpath",
            "/forward",
            "/forward?other=https%3A%2F%2Fexample.org%2F",
        ] {
            #expect(relay.forwardedURL(for: request(target)) == nil, "should refuse \(target)")
        }
    }

    @Test("a forwarded request is not a site API request, and the reverse")
    func routesDoNotOverlap() {
        let relay = makeRelay(apiRoot: Self.prettyRoot)
        #expect(relay.upstreamURL(for: request("/forward?url=https%3A%2F%2Fexample.org%2F")) == nil)
        #expect(relay.forwardedURL(for: request("/proxy/wp/v2/posts?url=https%3A%2F%2Fexample.org%2F")) == nil)
        #expect(relay.forwardedURL(for: request("/forwarding?url=https%3A%2F%2Fexample.org%2F")) == nil)
    }

    // MARK: - Redirects

    @Test("follows any redirect for a request to another host")
    func followsEveryRedirectWithoutPrefix() {
        // A request for another host carries no site credential to keep in.
        let redirectGuard = RestRelay.RedirectGuard(allowedPrefix: nil)
        for target in [
            "https://elsewhere.example/wp-json/wp/v2/posts",
            "https://example.com/wp-login.php",
            "http://example.com/wp-json/wp/v2/posts",
        ] {
            #expect(decide(redirectGuard, target: target)?.url?.absoluteString == target, "should follow \(target)")
        }
        #expect(redirectGuard.refusedTarget == nil)
    }

    @Test("keeps a caller's Authorization on a redirect to the same origin")
    func keepsAuthorizationWithinOrigin() {
        // `URLSession` drops it on every redirect. WebKit's `fetch` keeps it
        // while the scheme, host, and port stay the same.
        for target in [
            "https://api.example/v1/query/",
            "https://API.example:443/v2/other",
        ] {
            let redirectGuard = RestRelay.RedirectGuard(allowedPrefix: nil, authorization: "Bearer jwt")
            let followed = decide(redirectGuard, from: "https://api.example/v1/query", target: target)
            #expect(followed?.value(forHTTPHeaderField: "Authorization") == "Bearer jwt", "should keep it for \(target)")
        }
    }

    @Test("drops a caller's Authorization on a redirect to another origin")
    func dropsAuthorizationAcrossOrigins() {
        // Another host, port, or scheme is another origin, and `fetch` drops
        // the header for each. The redirect itself is still followed.
        for target in [
            "https://cdn.example/v1/query",
            "https://www.api.example/v1/query",
            "https://api.example:8443/v1/query",
            "http://api.example/v1/query",
        ] {
            let redirectGuard = RestRelay.RedirectGuard(allowedPrefix: nil, authorization: "Bearer jwt")
            let followed = decide(redirectGuard, from: "https://api.example/v1/query", target: target)
            #expect(followed?.url?.absoluteString == target, "should follow \(target)")
            #expect(followed?.value(forHTTPHeaderField: "Authorization") == nil, "should drop it for \(target)")
        }
    }

    @Test("doesn't put a caller's Authorization back once a redirect has left its origin")
    func keepsAuthorizationOffAfterLeavingOrigin() {
        // WebKit's `fetch` reaches the original host without it after a
        // redirect away and another one back.
        let redirectGuard = RestRelay.RedirectGuard(allowedPrefix: nil, authorization: "Bearer jwt")
        _ = decide(redirectGuard, from: "https://api.example/start", target: "https://cdn.example/bounce")
        let followed = decide(redirectGuard, from: "https://cdn.example/bounce", target: "https://api.example/end")

        #expect(followed?.url?.absoluteString == "https://api.example/end")
        #expect(followed?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("keeps the site credential on a redirect to the same origin only")
    func keepsSiteCredentialWithinOrigin() {
        // The rule for another host applies here too. The `www.` alias and the
        // `https` upgrade are still followed, but they are other origins, so
        // they arrive without it, as they would from `fetch`.
        for (root, target, expected) in [
            ("https://example.com/wp-json/", "https://example.com/wp-json/wp/v2/posts/", "Bearer site"),
            ("https://example.com/wp-json/", "https://www.example.com/wp-json/wp/v2/posts", nil),
            ("http://example.com/wp-json/", "https://example.com/wp-json/wp/v2/posts", nil),
        ] as [(String, String, String?)] {
            let redirectGuard = RestRelay.RedirectGuard(allowedPrefix: root, authorization: "Bearer site")
            let followed = decide(redirectGuard, from: root + "wp/v2/posts", target: target)
            #expect(followed?.url?.absoluteString == target, "should follow \(target)")
            #expect(followed?.value(forHTTPHeaderField: "Authorization") == expected, "for \(target)")
        }
    }

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
            "https://example.com:8443/wp-json/wp/v2/posts",
        ] {
            let redirectGuard = RestRelay.RedirectGuard(allowedPrefix: "http://example.com/wp-json/")
            #expect(decide(redirectGuard, target: target) == nil, "should refuse \(target)")
        }
    }

    @Test("follows a redirect to an alias of the configured host")
    func followsHostAlias() {
        // The spellings `relayUpstreamPath` tolerates, so the two layers
        // agree: a site whose canonical redirect names its `www.` alias, or
        // wp-env answering on `127.0.0.1` for a root configured as
        // `localhost`, would otherwise have every relayed request refused.
        for (root, target) in [
            ("https://example.com/wp-json/", "https://www.example.com/wp-json/wp/v2/posts"),
            ("https://www.example.com/wp-json/", "https://example.com/wp-json/wp/v2/posts"),
            ("http://localhost:8888/wp-json/", "http://127.0.0.1:8888/wp-json/wp/v2/posts"),
            ("http://example.com/wp-json/", "https://www.example.com/wp-json/wp/v2/posts"),
            ("https://example.com/wp-json/", "https://Example.com:443/wp-json/wp/v2/posts"),
        ] {
            let redirectGuard = RestRelay.RedirectGuard(allowedPrefix: root)
            #expect(decide(redirectGuard, target: target)?.url?.absoluteString == target, "should follow \(target)")
            #expect(redirectGuard.refusedTarget == nil)
        }
    }

    @Test("the alias tolerance admits nothing else")
    func hostAliasStaysContained() {
        // Only the spellings of the same name: not a subdomain, a lookalike,
        // another port on the alias, or another path.
        for target in [
            "https://www2.example.com/wp-json/wp/v2/posts",
            "https://example.com.evil.example/wp-json/wp/v2/posts",
            "https://wwwexample.com/wp-json/wp/v2/posts",
            "https://www.example.com:8443/wp-json/wp/v2/posts",
            "https://www.example.com/wp-login.php",
        ] {
            #expect(redirectDecision(to: target) == nil, "should refuse \(target)")
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

    /// The URL the page's `fetch` addresses for a relay target such as
    /// `/proxy/wp/v2/posts?x=1`.
    private func request(_ target: String) -> URL {
        URL(string: "gbk-rest://relay\(target)")!
    }

    /// The request a fresh guard would follow for a redirect to `target`, or
    /// `nil` if it refuses.
    private func redirectDecision(to target: String) -> URLRequest? {
        decide(
            RestRelay.RedirectGuard(allowedPrefix: "https://example.com/wp-json/"),
            target: target
        )
    }

    /// A task for the delegate signature, which the guard never inspects.
    ///
    /// Built once from a session the tests own and immediately invalidated:
    /// asking `URLSession.shared` for one per assertion left a suspended task
    /// retained for the life of the test process each time.
    private static let unusedTask: URLSessionTask = {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        return session.dataTask(with: URL(string: "https://example.com/")!)
    }()

    /// Asks `redirectGuard` whether to follow a redirect from `source` to `target`.
    ///
    /// The new request has no `Authorization`, as `URLSession` hands it over.
    private func decide(
        _ redirectGuard: RestRelay.RedirectGuard,
        from source: String = "https://example.com/wp-json/wp/v2/posts",
        target: String
    ) -> URLRequest? {
        let url = URL(string: target)!
        var followed: URLRequest?
        redirectGuard.urlSession(
            .shared,
            task: Self.unusedTask,
            willPerformHTTPRedirection: HTTPURLResponse(
                url: URL(string: source)!,
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
