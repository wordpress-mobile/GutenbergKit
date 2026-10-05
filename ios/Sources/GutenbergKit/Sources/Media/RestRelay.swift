import Foundation
import OSLog

/// Relays the editor's REST API requests through the native networking stack.
///
/// ## Why this exists
///
/// The editor web view is a `file://` page. Its REST API requests normally
/// bypass CORS thanks to the `allowUniversalAccessFromFileURLs` preference,
/// but iOS Lockdown Mode stops honoring that exemption while still making the
/// page send `Origin: file://`. WordPress sanitizes that value through a
/// URL-protocol allowlist that doesn't include `file`, so it responds with an
/// empty `Access-Control-Allow-Origin` and WebKit rejects every response.
///
/// The relay sidesteps the problem: the page fetches a URL scheme its own web
/// view serves (``RestRelaySchemeHandler``), and this forwards the request to
/// the site's REST API with the configured authorization header, responding
/// with CORS headers we control. Every request takes this path, Lockdown Mode
/// or not, so there is one path to keep working.
///
/// ## Security
///
/// - Only the editor's own web view can load the scheme, so there is no token
///   to check.
/// - The caller supplies a **path**, not a URL: everything after `/proxy/` is
///   resolved natively against the configured site API root, so the relay
///   cannot be pointed at another host by construction rather than by string
///   matching. The resolved URL is re-checked against the root, and redirects
///   away from it are refused.
/// - Which route *within* the site is reached is the caller's to choose. The
///   query is forwarded as-is, and WordPress registers `rest_route` as a public
///   query variable that `WP::parse_request()` prefers over the route the path
///   names, so a caller-supplied one wins. There is no boundary here to
///   defend: every route reachable that way is one the editor may request
///   through the relay directly.
/// - The upstream `Authorization` header is injected natively from the editor
///   configuration; any client-supplied value is discarded.
struct RestRelay: Sendable {

    /// The route the relay answers. Everything after it is the upstream path,
    /// relative to the site API root — `/proxy/wp/v2/posts?…` relays to
    /// `<site API root>wp/v2/posts?…`.
    static let route = "/proxy"

    /// The site's API root, slash-terminated. Upstream paths are appended to
    /// it, and every resulting URL — including redirect targets — must still
    /// start with it.
    ///
    /// Held as a string rather than a `URL` because the root is not always
    /// directory-shaped: a site on plain permalinks has
    /// `https://example.com/?rest_route=/`, where relative URL resolution would
    /// discard the query.
    private let apiRoot: String

    /// The authorization header injected into upstream requests.
    private let authHeader: String

    /// The session upstream requests are sent on.
    private let session: URLSession

    /// The session every relay shares.
    ///
    /// A `URLSession` holds its resources until it is invalidated, and a relay
    /// is built on every editor load, so one session each would accumulate for
    /// the life of the process. A relayed request is cancelled through its own
    /// task rather than by tearing the session down.
    private static let sharedSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }()

    /// - Parameter session: The session to send upstream requests on. Defaults
    ///   to the shared one; tests substitute a stubbed session to exercise
    ///   ``handle(_:)`` without a site.
    init(configuration: EditorConfiguration, session: URLSession? = nil) {
        self.apiRoot = Self.normalizedRoot(configuration.siteApiRoot.absoluteString)
        self.authHeader = configuration.authHeader
        self.session = session ?? Self.sharedSession
    }

    /// The configured root, slash-terminated, with the route value of a
    /// plain-permalink root decoded.
    ///
    /// WordPress advertises that root through `add_query_arg`, which
    /// percent-encodes the value: `index.php?rest_route=%2F`. The separators
    /// are decoded before the slash is added so it lands inside the route
    /// value. Appended after `%2F`, it would make a root no path can extend:
    /// WordPress reads `rest_route=%2F/wp/v2/posts` as the route
    /// `//wp/v2/posts` and answers `rest_no_route`. `createRelayFetch`
    /// normalizes the same way, so both sides agree on what the root is.
    private static func normalizedRoot(_ configured: String) -> String {
        var root = configured
        if let query = root.firstIndex(of: "?") {
            let decoded = root[query...].replacingOccurrences(of: "%2f", with: "/", options: .caseInsensitive)
            root = String(root[..<query]) + decoded
        }
        return root.hasSuffix("/") ? root : root + "/"
    }

    /// Forwards a relayed request to the site's REST API and returns the
    /// upstream response with permissive CORS headers.
    ///
    /// - Parameter request: The page's request to the relay scheme. WebKit
    ///   delivers a string or `ArrayBuffer` body as `httpBody`; the page reads
    ///   anything else into one first (`bufferedBody` in `fetch-relay.js`).
    func handle(_ request: URLRequest) async -> SchemeResponse {
        guard let upstreamURL = request.url.flatMap(upstreamURL(for:)) else {
            Logger.restRelay.error("Refusing to relay a request outside the site API root")
            return Self.errorResponse(
                status: 403,
                code: "relay_forbidden_path",
                message: "The requested path is outside the site API root."
            )
        }

        var upstreamRequest = URLRequest(url: upstreamURL)
        upstreamRequest.httpMethod = request.httpMethod
        for (name, value) in request.allHTTPHeaderFields ?? [:] where !Self.requestHeadersToStrip.contains(name.lowercased()) {
            upstreamRequest.setValue(value, forHTTPHeaderField: name)
        }
        if !authHeader.isEmpty {
            upstreamRequest.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }
        upstreamRequest.httpBody = request.httpBody

        do {
            // The redirect guard is a per-task delegate: `URLSession` follows
            // 3xx responses on its own, which would carry the site credential
            // to whatever host the `Location` header names and relay that
            // response back. See ``RedirectGuard``.
            let redirectGuard = RedirectGuard(allowedPrefix: apiRoot)
            let (body, response) = try await session.data(for: upstreamRequest, delegate: redirectGuard)

            // A refused redirect leaves `URLSession` holding the 3xx itself.
            // Relaying that would undo the refusal: the response carries the
            // `Location` the guard just declined, and `fetch` follows redirects
            // by default, so the web view would chase it to the very host the
            // guard exists to keep the request away from.
            if let refused = redirectGuard.refusedTarget {
                Logger.restRelay.error("Refused a relay redirect outside the site API root")
                return Self.errorResponse(
                    status: 502,
                    code: "relay_redirect_refused",
                    message: "The site redirected this request to \(refused), which is outside its configured REST API root. The editor did not follow it."
                )
            }
            guard let response = response as? HTTPURLResponse else {
                return Self.errorResponse(status: 502, code: "relay_upstream_failed", message: "The site did not answer over HTTP.")
            }

            return SchemeResponse(
                status: response.statusCode,
                headers: Self.merged(response.allHeaderFields),
                body: body
            )
        } catch {
            Logger.restRelay.error("Upstream request failed: \(error.localizedDescription)")
            return Self.errorResponse(status: 502, code: "relay_upstream_failed", message: error.localizedDescription)
        }
    }

    // MARK: - Upstream URL

    /// Builds the upstream URL for a request to the relay scheme, or `nil` if
    /// the result would address anything outside the site API root.
    ///
    /// Everything after the ``route`` prefix is treated as a path relative to
    /// the API root and appended to it. Appending rather than resolving is what
    /// `createRootURLMiddleware` does on the JavaScript side, and it is the only
    /// approach that works for both root shapes WordPress produces: pretty
    /// permalinks give `https://example.com/wp-json/`, plain permalinks give
    /// `https://example.com/?rest_route=/`, where the path has to merge into an
    /// existing query string.
    ///
    /// Dot segments — literal or percent-encoded — are refused rather than
    /// normalized. A REST path never contains one, `URLSession` resolves them
    /// before sending, and a normalized `..` is the one thing that could walk
    /// out of the API root and reach the rest of the site with the credential
    /// attached.
    func upstreamURL(for relayURL: URL) -> URL? {
        guard let components = URLComponents(url: relayURL, resolvingAgainstBaseURL: false) else { return nil }
        let path = components.percentEncodedPath
        guard path == Self.route || path.hasPrefix("\(Self.route)/") else { return nil }

        // Strip the route and any leading slashes, so the remainder appends to
        // the API root rather than resolving against the site root.
        let relativePath = path.dropFirst(Self.route.count).drop(while: { $0 == "/" })
        guard !Self.containsDotSegment(relativePath) else { return nil }

        var suffix = String(relativePath) + (components.percentEncodedQuery.map { "?\($0)" } ?? "")
        // A root that already carries a query (plain permalinks) continues it
        // rather than starting a second one — mirroring `createRootURLMiddleware`.
        if apiRoot.contains("?"), let separator = suffix.firstIndex(of: "?") {
            suffix.replaceSubrange(separator...separator, with: "&")
        }

        guard let url = URL(string: apiRoot + suffix),
              url.absoluteString.hasPrefix(apiRoot) else {
            return nil
        }
        return url
    }

    /// Whether `path` contains a `.` or `..` segment, including the
    /// percent-encoded spellings a server may decode before resolving it.
    ///
    /// The separators are decoded alongside the dots. A server that decodes
    /// `%2f` before normalizing — nginx normalizes the request URI ahead of
    /// location matching — reads `%2e%2e%2fwp-admin` as `../wp-admin`, which
    /// splitting on literal slashes alone would pass through. `%5c` is decoded
    /// too because Windows-hosted servers treat a backslash as a separator.
    private static func containsDotSegment(_ path: some StringProtocol) -> Bool {
        let decoded = path.lowercased()
            .replacingOccurrences(of: "%2e", with: ".")
            .replacingOccurrences(of: "%2f", with: "/")
            .replacingOccurrences(of: "%5c", with: "/")
            .replacingOccurrences(of: "\\", with: "/")
        guard decoded.contains(".") else { return false }
        return decoded.split(separator: "/", omittingEmptySubsequences: false).contains {
            $0 == "." || $0 == ".."
        }
    }

    /// Refuses redirects that leave the site API root.
    ///
    /// `URLSession` follows 3xx responses automatically, so without this the
    /// containment check would only ever apply to the first hop: a site that
    /// redirected `/wp-json/wp/v2/posts` elsewhere would have the request —
    /// carrying the site credential — followed to that host, and its response
    /// relayed back to the editor. Refusing hands the 3xx itself back instead.
    ///
    /// The comparison is a prefix match on the whole URL, read through the
    /// host spellings `relayUpstreamPath` tolerates — `www.` versus bare, the
    /// loopback names — and an `http`→`https` upgrade. So another path on the
    /// same site (`/wp-login.php`), another port, another host, and a scheme
    /// downgrade are refused: the site credential follows the request only to
    /// the API it was configured for. The cost is that a legitimate
    /// permalink-structure redirect is refused too, which the response says
    /// specifically enough to diagnose.
    ///
    /// The tolerances are the layer above's so that the two agree. A `Link`
    /// target on the `www.` alias is relayed by `createRelayFetch`, and a site
    /// whose canonical redirect names that alias — or whose `siteurl` is `http`
    /// behind a TLS-terminating proxy — would otherwise have every relayed
    /// request refused here. Containment holds: the same site under another
    /// of its own names, and a strictly stronger scheme.
    ///
    /// A `307` or `308` it follows has `URLSession` resend the body, which it can:
    /// a scheme request's body is `Data`, held in memory.
    ///
    /// `@unchecked Sendable`: the prefixes are `let`s set at init; the refusal is
    /// recorded under a lock.
    final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        /// The API root, in the form ``normalized(_:)`` gives a target.
        private let allowedPrefix: String

        /// `allowedPrefix` under `https`, when the configured root is `http`.
        private let upgradedPrefix: String?

        private let lock = NSLock()
        private var _refusedTarget: String?

        /// The redirect target that was refused, or `nil` if none was.
        var refusedTarget: String? {
            lock.withLock { _refusedTarget }
        }

        init(allowedPrefix: String) {
            let root = Self.normalized(allowedPrefix) ?? allowedPrefix
            self.allowedPrefix = root
            let insecureScheme = "http://"
            self.upgradedPrefix = root.hasPrefix(insecureScheme)
                ? "https://" + root.dropFirst(insecureScheme.count)
                : nil
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            guard let url = request.url, contains(url.absoluteString) else {
                lock.withLock { _refusedTarget = request.url?.absoluteString ?? "an unreadable URL" }
                completionHandler(nil)
                return
            }
            completionHandler(request)
        }

        /// Whether `target` is inside the API root, allowing only the host
        /// spelling and a scheme upgrade to differ.
        private func contains(_ target: String) -> Bool {
            guard let target = Self.normalized(target) else { return false }
            if target.hasPrefix(allowedPrefix) {
                return true
            }
            guard let upgradedPrefix else { return false }
            return target.hasPrefix(upgradedPrefix)
        }

        /// `url` with its host in the form its aliases share and a default
        /// port dropped, so that a prefix comparison reads through the
        /// spellings the layer above tolerates. `nil` for a URL without a host.
        private static func normalized(_ url: String) -> String? {
            guard var components = URLComponents(string: url), let host = components.host else {
                return nil
            }
            components.host = canonicalHost(host)
            if let port = components.port, port == defaultPort(for: components.scheme) {
                components.port = nil
            }
            return components.string
        }

        private static func defaultPort(for scheme: String?) -> Int? {
            switch scheme?.lowercased() {
            case "http": return 80
            case "https": return 443
            default: return nil
            }
        }

        /// A host reduced to the form its aliases share: every loopback
        /// spelling collapses to one, and a `www.` prefix is dropped.
        ///
        /// Mirrors `canonicalHost` in `fetch-relay.js`, and the two must stay
        /// the same: a spelling the web view relays and this refuses fails
        /// every request on a site whose canonical redirect uses it.
        private static func canonicalHost(_ host: String) -> String {
            let lowercased = host.lowercased()
            if ["localhost", "127.0.0.1", "::1", "[::1]"].contains(lowercased) {
                return "localhost"
            }
            return lowercased.hasPrefix("www.") ? String(lowercased.dropFirst(4)) : lowercased
        }
    }

    // MARK: - Headers

    /// Headers every relayed response carries.
    ///
    /// Under Lockdown Mode WebKit enforces CORS on a scheme response too, and
    /// the page only sees the response headers the expose list names. A name
    /// missing from it does not fail loudly: `headers.get()` returns `null`, so
    /// the feature behind it reads as absent rather than broken. `canUser`
    /// reads `Allow`, and a block's own uploader reads whatever its endpoint
    /// answers with. Hence the leading `*`, which is valid because relayed
    /// requests are sent `credentials: 'omit'`.
    ///
    /// The four names stay listed behind the wildcard because `*` is ignored
    /// for a *credentialed* request. They are the names whose absence is known
    /// to break a feature: `Allow` for capabilities, `Link` for
    /// `fetchAllMiddleware`'s pagination, `X-WP-Total`/`X-WP-TotalPages` for
    /// list counts.
    static let corsHeaders: [String: String] = [
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "*",
        "Access-Control-Allow-Headers": "*",
        "Access-Control-Expose-Headers": "*, Allow, Link, X-WP-Total, X-WP-TotalPages",
    ]

    /// Request headers that stay behind.
    ///
    /// `host`, `connection` and `content-length` belong to the hop;
    /// `accept-encoding` is `URLSession`'s to set; `origin`, `referer` and
    /// `sec-fetch-*` describe the web view's fetch context and would leak the
    /// local page to the site (and WordPress rejects a `file://` origin — the
    /// exact problem the relay exists to solve); `cookie` is the page's, and
    /// the relay carries the site credential itself; `authorization` is the
    /// caller's, replaced by the natively held site credential.
    private static let requestHeadersToStrip: Set<String> = [
        "host", "connection", "content-length", "accept-encoding",
        "origin", "referer",
        "sec-fetch-site", "sec-fetch-mode", "sec-fetch-dest", "sec-fetch-user",
        "cookie", "authorization",
    ]

    /// Upstream response headers dropped from relayed responses.
    ///
    /// The CORS strip is load-bearing: an upstream
    /// `Access-Control-Allow-Origin` (WordPress sends an empty one for origins
    /// it rejects) would otherwise replace the relay's own.
    ///
    /// `Content-Encoding` and `Content-Length` must go because `URLSession`
    /// already decompressed the body: advertising the upstream encoding would
    /// make WebKit decode the plain bytes a second time, and the upstream
    /// length is the compressed one.
    ///
    /// `Set-Cookie` is the site's, scoped to the site. The relay carries the
    /// site credential natively and never needs it.
    private static let responseHeadersToStrip: Set<String> = [
        "access-control-allow-origin", "access-control-allow-credentials",
        "access-control-allow-headers", "access-control-allow-methods",
        "access-control-expose-headers", "access-control-max-age", "vary",
        "content-encoding", "content-length",
        "set-cookie", "set-cookie2",
    ]

    /// The upstream response's headers as the editor should see them: the
    /// upstream's CORS and transport-encoding headers dropped (see
    /// `responseHeadersToStrip`), and the relay's own CORS headers added.
    private static func merged(_ upstream: [AnyHashable: Any]) -> [String: String] {
        var headers: [String: String] = [:]
        for (name, value) in upstream {
            guard let name = name as? String, let value = value as? String,
                  !responseHeadersToStrip.contains(name.lowercased()) else { continue }
            headers[name] = value
        }
        return headers.merging(corsHeaders) { _, relay in relay }
    }

    /// A WordPress-REST-style error rather than plain text, so the editor
    /// decodes a relay failure the same way it decodes WordPress's own.
    static func errorResponse(status: Int, code: String, message: String) -> SchemeResponse {
        var response = SchemeResponse.error(status, code: code, message: message)
        response.headers.merge(corsHeaders) { _, relay in relay }
        return response
    }
}
