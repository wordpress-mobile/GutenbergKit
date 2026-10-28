import Foundation
import Testing
@testable import GutenbergKit

/// Covers where the relay sends a request. A URL below the site API root goes to a
/// URL the relay builds from the configured root, which is the relay's containment
/// boundary: nothing the web view puts in the URL may make a request that carries
/// the site credential address anything outside the root. Any other URL goes where
/// it was going, and the relay never adds the site credential to it.
@Suite("RestRelay destination")
struct RestRelayTests {

    /// A site on pretty permalinks.
    private static let prettyRoot = URL(string: "https://example.com/wp-json/")!

    /// A site on plain permalinks, where the API root carries a query and the
    /// path has to merge into it rather than start a second one.
    private static let plainRoot = URL(string: "https://example.com/?rest_route=/")!

    /// A plain-permalink root as WordPress advertises it, through `add_query_arg`,
    /// which percent-encodes the route.
    private static let advertisedPlainRoot = URL(string: "https://example.com/index.php?rest_route=%2F")!

    // MARK: - Site API requests

    @Test("sends a site API request to the API root, path and query included")
    func sendsSiteAPIRequestToRoot() {
        #expect(
            siteAPIURL("https://example.com/wp-json/wp/v2/posts?_locale=user")
                == "https://example.com/wp-json/wp/v2/posts?_locale=user"
        )
        #expect(siteAPIURL("https://example.com/wp-json/") == "https://example.com/wp-json/")
    }

    @Test("adds a trailing slash to an API root configured without one")
    func normalizesAPIRootWithoutTrailingSlash() {
        #expect(
            siteAPIURL("https://example.com/wp-json/wp/v2/posts", root: URL(string: "https://example.com/wp-json")!)
                == "https://example.com/wp-json/wp/v2/posts"
        )
    }

    @Test("preserves percent-encoding in the query")
    func preservesPercentEncoding() {
        #expect(
            siteAPIURL("https://example.com/wp-json/wp/v2/search?search=caf%C3%A9&per_page=100")
                == "https://example.com/wp-json/wp/v2/search?search=caf%C3%A9&per_page=100"
        )
    }

    @Test("sends a host alias to the configured host")
    func toleratesHostAlias() {
        // WordPress builds `Link` headers from `home_url()`, which can spell the
        // host differently: `www.` versus bare, or wp-env writing `127.0.0.1`
        // for a site configured as `localhost`.
        #expect(
            siteAPIURL("https://www.example.com/wp-json/wp/v2/posts?page=2")
                == "https://example.com/wp-json/wp/v2/posts?page=2"
        )
        #expect(
            siteAPIURL("http://127.0.0.1:8888/wp-json/wp/v2/posts", root: URL(string: "http://localhost:8888/wp-json/")!)
                == "http://localhost:8888/wp-json/wp/v2/posts"
        )
    }

    @Test("sends a request with another scheme or a default port to the configured root")
    func toleratesSchemeAndDefaultPort() {
        // An `http` `siteurl` behind a TLS-terminating proxy.
        #expect(siteAPIURL("http://example.com:80/wp-json/wp/v2/posts") == "https://example.com/wp-json/wp/v2/posts")
        #expect(siteAPIURL("https://example.com:443/wp-json/wp/v2/posts") == "https://example.com/wp-json/wp/v2/posts")
    }

    // MARK: - A root that carries its route in the query

    @Test("continues the query of an API root that already carries one")
    func mergesIntoAQueryCarryingAPIRoot() {
        // Plain permalinks: the route and the other parameters have to make one
        // query string, not two — mirroring `createRootURLMiddleware`.
        #expect(
            siteAPIURL("https://example.com/?rest_route=/wp/v2/posts&_locale=user", root: Self.plainRoot)
                == "https://example.com/?rest_route=/wp/v2/posts&_locale=user"
        )
        #expect(
            siteAPIURL("https://example.com/?rest_route=/wp/v2/posts&a=1&b=2", root: Self.plainRoot)
                == "https://example.com/?rest_route=/wp/v2/posts&a=1&b=2"
        )
    }

    @Test("reads the route with its separators encoded")
    func readsEncodedRoute() {
        // The spelling every request arrives in: api-fetch's locale middleware
        // rebuilds the query through `addQueryArgs`, and WordPress builds `Link`
        // through `add_query_arg`. Both percent-encode the value.
        #expect(
            siteAPIURL("https://example.com/?rest_route=%2Fwp%2Fv2%2Fposts&page=2&_locale=user", root: Self.plainRoot)
                == "https://example.com/?rest_route=/wp/v2/posts&page=2&_locale=user"
        )
    }

    @Test("decodes the route of a root advertised with it encoded")
    func decodesAdvertisedPlainPermalinkRoot() {
        // The slash termination has to land inside the route value, since
        // WordPress reads `rest_route=%2F/wp/v2/posts` as the route `//wp/v2/posts`.
        #expect(
            siteAPIURL("https://example.com/index.php?rest_route=%2Fwp%2Fv2%2Fposts&_locale=user", root: Self.advertisedPlainRoot)
                == "https://example.com/index.php?rest_route=/wp/v2/posts&_locale=user"
        )
        #expect(
            siteAPIURL("https://example.com/index.php?rest_route=%2F", root: Self.advertisedPlainRoot)
                == "https://example.com/index.php?rest_route=/"
        )
    }

    @Test("continues a route that names a site")
    func continuesNamespacedRoute() {
        // A namespaced site's root carries more than `/` in the route, and every
        // request continues it.
        #expect(
            siteAPIURL(
                "https://public-api.example/wp-json/?rest_route=%2Fsites%2F1%2Fwp%2Fv2%2Fposts&_locale=user",
                root: URL(string: "https://public-api.example/wp-json/?rest_route=/sites/1/")!
            ) == "https://public-api.example/wp-json/?rest_route=/sites/1/wp/v2/posts&_locale=user"
        )
    }

    @Test("sends the same page without the route, or a route outside the root, where it was going")
    func queryRoutedRootContainsOnlyItsRoutes() {
        #expect(isOtherHost("https://example.com/index.php?p=1", root: Self.advertisedPlainRoot))
        #expect(isOtherHost(
            "https://public-api.example/wp-json/?rest_route=%2Fsites%2F2%2Fwp%2Fv2%2Fposts",
            root: URL(string: "https://public-api.example/wp-json/?rest_route=/sites/1/")!
        ))
    }

    // MARK: - Containment

    @Test("refuses a path that walks out of the API root")
    func refusesDotSegments() {
        #expect(isRefused("https://example.com/wp-json/../wp-admin/admin-ajax.php"))
        #expect(isRefused("https://example.com/wp-json/wp/v2/../../../wp-admin/"))
        #expect(isRefused("https://example.com/wp-json/wp/v2/./posts"))
        #expect(isRefused("https://example.com/?rest_route=%2F..%2Fwp-admin%2F", root: Self.plainRoot))
    }

    @Test("refuses percent-encoded dot segments")
    func refusesEncodedDotSegments() {
        // `URLSession` leaves these encoded, but the receiving server may decode
        // before resolving, so they are refused here rather than sent on.
        #expect(isRefused("https://example.com/wp-json/%2e%2e/wp-admin/"))
        #expect(isRefused("https://example.com/wp-json/wp/%2E%2E/%2e%2e/"))
    }

    @Test("refuses dot segments whose separators are encoded too")
    func refusesDotSegmentsWithEncodedSeparators() {
        // The whole traversal is one literal segment, so it is only a dot
        // segment to a server that decodes the separator before normalizing.
        #expect(isRefused("https://example.com/wp-json/%2e%2e%2f%2e%2e%2fwp-admin/admin-ajax.php"))
        #expect(isRefused("https://example.com/wp-json/wp%5C..%5Cwp-admin/"))
    }

    @Test("an encoded slash within a segment is not a dot segment")
    func allowsEncodedSlashesWithinSegments() {
        // A template ID is `theme//slug`, encoded into a single path segment.
        #expect(
            siteAPIURL("https://example.com/wp-json/wp/v2/templates/twentytwentyfour%2F%2Fsingle")
                == "https://example.com/wp-json/wp/v2/templates/twentytwentyfour%2F%2Fsingle"
        )
    }

    @Test("a dot inside a path segment is not a dot segment")
    func allowsDotsWithinSegments() {
        #expect(
            siteAPIURL("https://example.com/wp-json/oembed/1.0/embed?url=https%3A%2F%2Fexample.com")
                == "https://example.com/wp-json/oembed/1.0/embed?url=https%3A%2F%2Fexample.com"
        )
    }

    @Test("an absolute URL in the path stays under the API root")
    func absoluteURLInPathStaysContained() {
        // The path is appended to the root, not resolved, so a smuggled URL
        // becomes an ordinary (404ing) path segment rather than another host.
        #expect(siteAPIURL("https://example.com/wp-json/https://elsewhere.example/x")?.hasPrefix("https://example.com/wp-json/") == true)
        #expect(siteAPIURL("https://example.com/wp-json//elsewhere.example/x") == "https://example.com/wp-json/elsewhere.example/x")
    }

    @Test("forwards the query verbatim, rest_route included")
    func forwardsQueryVerbatim() {
        // WordPress prefers `$_GET['rest_route']` over the route the path
        // names, so the caller picks the route whichever way it spells the
        // parameter. Deliberately not filtered: see the type's Security notes.
        #expect(
            siteAPIURL("https://example.com/wp-json/wp/v2/posts?rest_route=/wp/v2/users&_locale=user")
                == "https://example.com/wp-json/wp/v2/posts?rest_route=/wp/v2/users&_locale=user"
        )
    }

    // MARK: - Other hosts

    @Test("sends a request for another host where it was going")
    func sendsOtherHostsWhereTheyWereGoing() {
        for url in [
            // Jetpack AI, on a site that isn't on WordPress.com.
            "https://public-api.wordpress.com/wpcom/v2/jetpack-ai-query?stream=true",
            // Another server on the site's host: another port is another server,
            // however its paths are shaped.
            "https://example.com:8443/wp-json/wp/v2/posts",
            // Another WordPress site whose path matches the root.
            "https://other-wp.example/wp-json/wp/v2/posts",
            // A sibling of the root: `/wp-json` must not match `/wp-jsonx/`.
            "https://example.com/wp-jsonx/secrets",
            // The same host outside the root.
            "https://example.com/wp-admin/admin-ajax.php",
        ] {
            #expect(isOtherHost(url), "\(url)")
        }
    }

    @Test("a different site in a subdirectory multisite is another host")
    func subdirectoryMultisiteIsAnotherHost() {
        // A path difference is a different site, not an alias.
        #expect(isOtherHost("https://example.com/b/wp-json/wp/v2/posts", root: URL(string: "https://example.com/a/wp-json/")!))
    }

    @Test("a host alias the canonical form doesn't cover is another host")
    func uncoveredAliasIsAnotherHost() {
        // A documented limitation, not a decision: a site reached by LAN IP
        // emits `localhost` URLs, which aren't recognized as the same host, so
        // the relay doesn't add the site credential to paginated `Link` targets.
        #expect(isOtherHost(
            "http://localhost:8888/wp-json/wp/v2/posts?page=2",
            root: URL(string: "http://192.168.1.50:8888/wp-json/")!
        ))
    }

    // MARK: - The relay's URL

    @Test("reads the URL a request is for out of the relay's URL, decoded once")
    func readsRequestedURL() {
        #expect(
            RestRelay.requestedURL(in: request("/fetch?url=https%3A%2F%2Fexample.org%2Fapi%3Fq%3Da%2520b%26x%3D1"))?.absoluteString
                == "https://example.org/api?q=a%20b&x=1"
        )
        #expect(
            RestRelay.requestedURL(in: request("/fetch?url=http%3A%2F%2F127.0.0.1%3A8888%2Fwp-json%2F"))?.absoluteString
                == "http://127.0.0.1:8888/wp-json/"
        )
    }

    @Test("keeps a requested URL's escapes when it also has characters to encode")
    func keepsEscapesBesideCharactersToEncode() {
        // `fetch` leaves `[]` in a query as written. `URL(string:)` would encode
        // them, and the `%` of the escapes beside them too.
        let target = RestRelayHandleTests.relayTarget("https://example.org/wp-json/wp/v2/posts?search=caf%C3%A9&include[]=1")

        #expect(
            RestRelay.requestedURL(in: request(target))?.absoluteString
                == "https://example.org/wp-json/wp/v2/posts?search=caf%C3%A9&include%5B%5D=1"
        )
    }

    @Test("relays only http and https URLs, on its own route")
    func relaysOnlyWebURLs() {
        for target in [
            "/fetch?url=file%3A%2F%2F%2Fetc%2Fhosts",
            "/fetch?url=gbk-upload%3A%2F%2Fupload%2Fsessions",
            "/fetch?url=https%3Ano-host",
            "/fetch?url=%2Frelative%2Fpath",
            "/fetch",
            "/fetch?other=https%3A%2F%2Fexample.org%2F",
            "/fetching?url=https%3A%2F%2Fexample.org%2F",
            "/proxy/wp/v2/posts",
        ] {
            #expect(RestRelay.requestedURL(in: request(target)) == nil, "should refuse \(target)")
        }
    }

    // MARK: - Redirects

    @Test("follows a redirect to any host for a request to another host")
    func followsEveryRedirectWithoutPrefix() {
        // The relay adds no site credential to a request for another host, so
        // there is none to keep in.
        let redirectGuard = RestRelay.RedirectGuard(root: nil)
        for target in [
            "https://elsewhere.example/wp-json/wp/v2/posts",
            "https://example.com/wp-login.php",
        ] {
            #expect(decide(redirectGuard, target: target)?.url?.absoluteString == target, "should follow \(target)")
        }
        #expect(redirectGuard.refusal == nil)
    }

    @Test("keeps a caller's Authorization on a redirect to the same origin")
    func keepsAuthorizationWithinOrigin() {
        // `URLSession` drops it on every redirect. WebKit's `fetch` keeps it
        // while the scheme, host, and port stay the same.
        for target in [
            "https://api.example/v1/query/",
            "https://API.example:443/v2/other",
        ] {
            let redirectGuard = RestRelay.RedirectGuard(root: nil, authorization: "Bearer jwt")
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
        ] {
            let redirectGuard = RestRelay.RedirectGuard(root: nil, authorization: "Bearer jwt")
            let followed = decide(redirectGuard, from: "https://api.example/v1/query", target: target)
            #expect(followed?.url?.absoluteString == target, "should follow \(target)")
            #expect(followed?.value(forHTTPHeaderField: "Authorization") == nil, "should drop it for \(target)")
        }

        let redirectGuard = RestRelay.RedirectGuard(root: nil, authorization: "Bearer jwt")
        let upgraded = decide(redirectGuard, from: "http://api.example/v1/query", target: "https://api.example/v1/query")
        #expect(upgraded?.url?.absoluteString == "https://api.example/v1/query")
        #expect(upgraded?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("removes Authorization on a redirect to another origin, whatever URLSession left")
    func removesAuthorizationAcrossOrigins() {
        // The guard enforces the rule itself rather than relying on `URLSession`
        // having dropped the header.
        let redirectGuard = RestRelay.RedirectGuard(root: nil, authorization: "Bearer jwt")
        let followed = decide(
            redirectGuard,
            from: "https://api.example/v1/query",
            target: "https://elsewhere.example/v1/query",
            carrying: "Bearer jwt"
        )

        #expect(followed?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("doesn't put a caller's Authorization back once a redirect has left its origin")
    func keepsAuthorizationOffAfterLeavingOrigin() {
        // WebKit's `fetch` reaches the original host without it after a
        // redirect away and another one back.
        let redirectGuard = RestRelay.RedirectGuard(root: nil, authorization: "Bearer jwt")
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
            let redirectGuard = RestRelay.RedirectGuard(root: root, authorization: "Bearer site")
            let followed = decide(redirectGuard, from: root + "wp/v2/posts", target: target)
            #expect(followed?.url?.absoluteString == target, "should follow \(target)")
            #expect(followed?.value(forHTTPHeaderField: "Authorization") == expected, "for \(target)")
        }
    }

    @Test("never follows a redirect from https to http")
    func refusesDowngrade() {
        // Wherever it goes: another host, the site itself, or back to an `http`
        // API root after the site's own upgrade.
        for (root, source, target) in [
            (nil, "https://api.example/v1", "http://192.168.1.1/admin"),
            (nil, "https://api.example/v1", "http://example.com/wp-admin/admin-ajax.php"),
            ("http://example.com/wp-json/", "https://example.com/wp-json/wp/v2/posts", "http://example.com/wp-json/wp/v2/posts"),
        ] as [(String?, String, String)] {
            let redirectGuard = RestRelay.RedirectGuard(root: root)

            #expect(decide(redirectGuard, from: source, target: target) == nil, "should refuse \(target)")
            #expect(redirectGuard.refusal?.reason == "would leave https", "\(target)")
        }
    }

    @Test("follows a redirect from http to http or https")
    func followsRedirectsFromHTTP() {
        // A request for another host reaches plain `http` only at the site's
        // own host, so a chain of `http` redirects started there.
        for target in ["http://192.168.1.50:8080/y", "http://192.168.1.60/y", "https://cdn.example/y"] {
            let redirectGuard = RestRelay.RedirectGuard(root: nil)

            #expect(decide(redirectGuard, from: "http://192.168.1.50/x", target: target)?.url?.absoluteString == target, "should follow \(target)")
        }
    }

    @Test("refuses a redirect to anything but an http or https URL")
    func refusesOtherSchemeRedirects() {
        // `URLSession` follows a redirect to a `data:` or `ftp:` URL.
        for target in ["data:text/plain,hello", "ftp://192.168.1.1/", "about:blank", "file:///etc/hosts"] {
            for prefix in [nil, "https://example.com/wp-json/"] as [String?] {
                let redirectGuard = RestRelay.RedirectGuard(root: prefix)

                #expect(decide(redirectGuard, target: target) == nil, "should refuse \(target)")
                #expect(redirectGuard.refusal?.reason == "isn't an http or https URL", "\(target)")
            }
        }
    }

    @Test("refuses a redirect to a URL with a user name or password, and doesn't repeat them")
    func refusesCredentialRedirects() {
        // `URLSession` would answer the host's challenge with them, then store
        // them for every later request to that host.
        for target in ["https://user:pass@api.example/v1", "https://user@api.example/v1"] {
            let redirectGuard = RestRelay.RedirectGuard(root: nil)

            #expect(decide(redirectGuard, target: target) == nil, "should refuse \(target)")
            #expect(redirectGuard.refusal == .init(target: "https://api.example/v1", reason: "has a user name or password in it"))
        }
    }

    @Test("follows a redirect that stays under the API root")
    func followsContainedRedirect() {
        let followed = redirectDecision(to: "https://example.com/wp-json/wp/v2/posts/1")

        #expect(followed?.url?.absoluteString == "https://example.com/wp-json/wp/v2/posts/1")
    }

    @Test("follows a redirect to an encoded route under a plain-permalink root")
    func followsEncodedPlainPermalinkRedirect() {
        // WordPress writes the route as `%2F…` through `add_query_arg`.
        // `destination(of:)` sends such a URL to the site, so the guard has to
        // follow a redirect to one too.
        let redirectGuard = RestRelay.RedirectGuard(root: "https://example.com/?rest_route=/")
        let target = "https://example.com/?rest_route=%2Fwp%2Fv2%2Fposts%2F2"
        let followed = decide(redirectGuard, from: "https://example.com/?rest_route=%2Fwp%2Fv2%2Fposts%2F1", target: target)

        #expect(followed?.url?.absoluteString == target)
        #expect(redirectGuard.refusal == nil)
    }

    @Test("refuses a redirect whose route walks out of the API root")
    func refusesDotSegmentRedirect() {
        // It starts with the root, but the server resolves the `..` and
        // reaches the rest of the site.
        for target in [
            "https://example.com/wp-json/../wp-login.php",
            "https://example.com/wp-json/%2e%2e/wp-login.php",
        ] {
            #expect(redirectDecision(to: target) == nil, "should refuse \(target)")
        }
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
        // A site whose `siteurl` is `http` but which answers on `https` is one
        // `destination(of:)` already sends to the site; refusing its redirect
        // here would fail every one of those requests.
        let redirectGuard = RestRelay.RedirectGuard(root: "http://example.com/wp-json/")
        let followed = decide(redirectGuard, target: "https://example.com/wp-json/wp/v2/posts")

        #expect(followed?.url?.absoluteString == "https://example.com/wp-json/wp/v2/posts")
        #expect(redirectGuard.refusal == nil)
    }

    @Test("the scheme upgrade admits nothing else")
    func schemeUpgradeStaysContained() {
        // Upgrading the scheme must not also relax the host or the path.
        for target in [
            "https://elsewhere.example/wp-json/wp/v2/posts",
            "https://example.com/wp-login.php",
            "https://example.com:8443/wp-json/wp/v2/posts",
        ] {
            let redirectGuard = RestRelay.RedirectGuard(root: "http://example.com/wp-json/")
            #expect(decide(redirectGuard, target: target) == nil, "should refuse \(target)")
        }
    }

    @Test("follows a redirect to an alias of the configured host")
    func followsHostAlias() {
        // The spellings `destination(of:)` tolerates, so the two agree: a site
        // whose canonical redirect names its `www.` alias, or
        // wp-env answering on `127.0.0.1` for a root configured as
        // `localhost`, would otherwise have every relayed request refused.
        for (root, target) in [
            ("https://example.com/wp-json/", "https://www.example.com/wp-json/wp/v2/posts"),
            ("https://www.example.com/wp-json/", "https://example.com/wp-json/wp/v2/posts"),
            ("http://localhost:8888/wp-json/", "http://127.0.0.1:8888/wp-json/wp/v2/posts"),
            ("http://example.com/wp-json/", "https://www.example.com/wp-json/wp/v2/posts"),
            ("https://example.com/wp-json/", "https://Example.com:443/wp-json/wp/v2/posts"),
        ] {
            let redirectGuard = RestRelay.RedirectGuard(root: root)
            #expect(decide(redirectGuard, from: root + "wp/v2/posts", target: target)?.url?.absoluteString == target, "should follow \(target)")
            #expect(redirectGuard.refusal == nil)
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
        let redirectGuard = RestRelay.RedirectGuard(root: "https://example.com/wp-json/")
        #expect(redirectGuard.refusal == nil)

        _ = decide(redirectGuard, target: "https://elsewhere.example/x")

        #expect(redirectGuard.refusal == .init(target: "https://elsewhere.example/x", reason: "is outside the site's configured REST API root"))
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
    /// `/fetch?url=…`.
    private func request(_ target: String) -> URL {
        URL(string: "gbk-rest://relay\(target)")!
    }

    /// The site API URL the relay sends a request for `url` to, or `nil` if it
    /// sends it elsewhere or refuses it.
    private func siteAPIURL(_ url: String, root: URL = RestRelayTests.prettyRoot) -> String? {
        guard case .siteAPI(let upstream) = makeRelay(apiRoot: root).destination(of: URL(string: url)!) else {
            return nil
        }
        return upstream.absoluteString
    }

    /// Whether the relay sends a request for `url` where it was going, as a
    /// request for another host.
    private func isOtherHost(_ url: String, root: URL = RestRelayTests.prettyRoot) -> Bool {
        makeRelay(apiRoot: root).destination(of: URL(string: url)!) == .otherHost(URL(string: url)!)
    }

    /// Whether the relay refuses a request for `url`.
    private func isRefused(_ url: String, root: URL = RestRelayTests.prettyRoot) -> Bool {
        makeRelay(apiRoot: root).destination(of: URL(string: url)!) == nil
    }

    /// The request a fresh guard would follow for a redirect to `target`, or
    /// `nil` if it refuses.
    private func redirectDecision(to target: String) -> URLRequest? {
        decide(
            RestRelay.RedirectGuard(root: "https://example.com/wp-json/"),
            target: target
        )
    }

    /// A task to pass the guard's `urlSession(_:task:…)` method, which never reads it.
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
    /// The new request has no `Authorization`, as `URLSession` hands it over,
    /// unless `authorization` is given.
    private func decide(
        _ redirectGuard: RestRelay.RedirectGuard,
        from source: String = "https://example.com/wp-json/wp/v2/posts",
        target: String,
        carrying authorization: String? = nil
    ) -> URLRequest? {
        let url = URL(string: target)!
        var newRequest = URLRequest(url: url)
        newRequest.setValue(authorization, forHTTPHeaderField: "Authorization")
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
            newRequest: newRequest,
            completionHandler: { followed = $0 }
        )
        return followed
    }
}

private extension RestRelay.RedirectGuard {
    /// A guard for a site API request under `root`, or, given `nil`, for a
    /// request to another host.
    convenience init(root: String?, authorization: String? = nil) {
        self.init(apiRoot: root.map { SiteAPIRoot(URL(string: $0)!) }, authorization: authorization)
    }
}
