#if canImport(Network)

import Foundation
import OSLog
import GutenbergKitHTTP

/// Relays editor REST API requests through the native networking stack.
///
/// ## Why this exists
///
/// The editor web view is a `file://` page. Its REST API requests normally
/// bypass CORS thanks to the `allowUniversalAccessFromFileURLs` preference,
/// but iOS Lockdown Mode stops honoring that exemption while still making the
/// page send `Origin: file://`. WordPress core and WordPress.com sanitize that
/// value through a URL-protocol allowlist that doesn't include `file`, so they
/// respond with an empty `Access-Control-Allow-Origin` and WebKit rejects
/// every response — most visibly media uploads (`POST /wp/v2/media`).
///
/// The relay sidesteps the problem: the web view fetches the local
/// ``MediaUploadServer`` and this handler forwards the request to the site's
/// REST API with the configured authorization header, responding with CORS
/// headers we control.
///
/// ## Security
///
/// - Requests reach the relay only through the local server's loopback
///   listener and per-session bearer token.
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
///   through the relay directly. Filtering the parameter would have to
///   reproduce PHP's `$_GET` name mangling — `.`, space and `+` all become `_`
///   — and a filter that misses a spelling reads as a guarantee it does not
///   provide.
/// - The upstream `Authorization` header is injected natively from the editor
///   configuration; any client-supplied value is discarded.
struct RestRelay: Sendable {

    /// The local server route the relay answers. Everything after it is the
    /// upstream path, relative to the site API root — `/proxy/wp/v2/posts?…`
    /// relays to `<site API root>wp/v2/posts?…`.
    ///
    /// A path rather than an absolute URL in a query parameter: there is no
    /// caller-supplied URL to contain in the first place, and each request
    /// identifies itself in a network log instead of every row reading
    /// `/proxy`.
    static let route = "/proxy"

    /// The URL the web view appends an upstream path to, slash-terminated.
    ///
    /// Built here rather than in JavaScript so ``route`` is spelled once. The
    /// address is literal `127.0.0.1` rather than `localhost`: the server binds
    /// the IPv4 loopback only, and a name that may resolve to `::1` first would
    /// have to fall back.
    static func baseURL(port: UInt16) -> String {
        "http://127.0.0.1:\(port)\(route)/"
    }

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
    /// is built on every editor load under Lockdown Mode, so one session each
    /// would accumulate for the life of the process. Nothing about the session
    /// is per-relay, and a relayed request is cancelled through its own task
    /// rather than by tearing the session down.
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

    /// Whether a request targets the relay.
    static func handles(_ request: ParsedHTTPRequest) -> Bool {
        request.path == route || request.path.hasPrefix("\(route)/")
    }

    /// Forwards a relayed request to the site's REST API and returns the
    /// upstream response with permissive CORS headers.
    func handle(_ request: HTTPServer.Request) async -> HTTPResponse {
        let parsed = request.parsed

        guard let upstreamURL = upstreamURL(for: parsed) else {
            Logger.restRelay.error("Refusing to relay a request outside the site API root")
            return Self.errorResponse(
                status: 403,
                code: "relay_forbidden_path",
                message: "The requested path is outside the site API root."
            )
        }

        var upstreamRequest = parsed.urlRequest(url: upstreamURL, stripping: Self.requestHeadersToStrip)
        if !authHeader.isEmpty {
            upstreamRequest.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }

        var streamedBody: RequestBody?
        if let body = parsed.body {
            if let data = body.inMemoryData {
                upstreamRequest.httpBody = data
            } else {
                // Large bodies are buffered to disk by the request parser;
                // stream them to avoid loading uploads fully into memory.
                //
                // `count` is the length the parser recorded for the slice, not
                // a file-system lookup, so it cannot fail here.
                do {
                    upstreamRequest.httpBodyStream = try body.makeInputStream()
                    upstreamRequest.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")
                    streamedBody = body
                } catch {
                    Logger.restRelay.error("Failed to open request body stream: \(error)")
                    return Self.errorResponse(status: 500, code: "relay_body_unreadable", message: "Failed to read the request body.")
                }
            }
        }

        do {
            // The redirect guard is a per-task delegate: `URLSession` follows
            // 3xx responses on its own, which would carry the site credential
            // to whatever host the `Location` header names and relay that
            // response back. See ``RedirectGuard``.
            let redirectGuard = RedirectGuard(allowedPrefix: apiRoot, streamedBody: streamedBody)
            let upstream = HTTPResponse(try await session.data(for: upstreamRequest, delegate: redirectGuard))

            // A refused redirect leaves `URLSession` holding the 3xx itself.
            // Relaying that would undo the refusal: the response carries the
            // `Location` the guard just declined, and `fetch` follows redirects
            // by default, so the web view would chase it to the very host the
            // guard exists to keep the request away from — arriving as an
            // opaque CORS failure rather than as this.
            if let refused = redirectGuard.refusedTarget {
                Logger.restRelay.error("Refused a relay redirect outside the site API root")
                return Self.errorResponse(
                    status: 502,
                    code: "relay_redirect_refused",
                    message: "The site redirected this request to \(refused), which is outside its configured REST API root. The editor did not follow it."
                )
            }

            return HTTPResponse(
                status: upstream.status,
                statusText: upstream.statusText,
                headers: Self.merged(upstream.headers),
                body: upstream.body
            )
        } catch {
            Logger.restRelay.error("Upstream request failed: \(error.localizedDescription)")
            return Self.errorResponse(status: 502, code: "relay_upstream_failed", message: error.localizedDescription)
        }
    }

    // MARK: - Upstream URL

    /// Builds the upstream URL for a relayed request, or `nil` if the result
    /// would address anything outside the site API root.
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
    func upstreamURL(for request: ParsedHTTPRequest) -> URL? {
        guard Self.handles(request) else { return nil }
        let path = request.path

        // Strip the route and any leading slashes, so the remainder appends to
        // the API root rather than resolving against the site root.
        let relativePath = path.dropFirst(Self.route.count).drop(while: { $0 == "/" })
        guard !Self.containsDotSegment(relativePath) else { return nil }

        var suffix = String(relativePath) + request.query
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
    /// A redirect the guard follows is also its job to make work. A `307` or
    /// `308` has `URLSession` resend the body, and a body the parser spilled
    /// to disk went out as a one-shot stream, so the resend needs a fresh one
    /// from ``urlSession(_:task:needNewBodyStream:)``. Without it the task
    /// fails with `requestBodyStreamExhausted` — and only for bodies over the
    /// in-memory threshold, since `URLSession` replays a `Data` body itself:
    /// every JSON save would succeed while every photo upload failed.
    ///
    /// `@unchecked Sendable`: the prefixes and the body are `let`s set at
    /// init; the refusal is recorded under a lock.
    final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        /// The API root, in the form ``normalized(_:)`` gives a target.
        private let allowedPrefix: String

        /// `allowedPrefix` under `https`, when the configured root is `http`.
        private let upgradedPrefix: String?

        /// The body sent as a one-shot stream, reopened when a followed
        /// redirect resends it. `nil` when `URLSession` holds the bytes itself.
        private let streamedBody: RequestBody?

        private let lock = NSLock()
        private var _refusedTarget: String?

        /// The redirect target that was refused, or `nil` if none was.
        var refusedTarget: String? {
            lock.withLock { _refusedTarget }
        }

        init(allowedPrefix: String, streamedBody: RequestBody? = nil) {
            let root = Self.normalized(allowedPrefix) ?? allowedPrefix
            self.allowedPrefix = root
            let insecureScheme = "http://"
            self.upgradedPrefix = root.hasPrefix(insecureScheme)
                ? "https://" + root.dropFirst(insecureScheme.count)
                : nil
            self.streamedBody = streamedBody
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            needNewBodyStream completionHandler: @escaping (InputStream?) -> Void
        ) {
            // `makeInputStream()` opens a fresh read of the parser's file on
            // each call, so the resend carries the whole body again.
            completionHandler(try? streamedBody?.makeInputStream())
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

    // MARK: - CORS

    /// Response headers the editor may read off a relayed response. The
    /// library's permissive CORS policy stamps `Access-Control-Allow-Origin`
    /// and friends; this governs what JavaScript can see.
    ///
    /// A name missing from an expose list does not fail loudly: `headers.get()`
    /// returns `null`, so the feature behind it reads as absent rather than
    /// broken. `canUser` reads `Allow` to decide whether the user may create a
    /// page, update settings, or edit global styles, so without it every such
    /// capability reads as false with no error surfaced. Hence the leading
    /// `*`, which covers whatever a plugin or a core update reads next. It is
    /// valid because relayed requests are sent `credentials: 'omit'`, and it
    /// withholds nothing that was not already the editor's: the response comes
    /// from the site it is authenticated to, over loopback.
    ///
    /// The four names stay listed behind the wildcard because `*` is ignored
    /// for a *credentialed* request — treated as a literal header name, not a
    /// wildcard. `createRelayFetch` sends `credentials: 'omit'`, so the
    /// wildcard applies today; if that ever changes, these keep working rather
    /// than every capability silently reading false again. They are the names
    /// whose absence is known to break a feature: `Allow` for capabilities,
    /// `Link` for `fetchAllMiddleware`'s pagination, `X-WP-Total`/
    /// `X-WP-TotalPages` for list counts.
    private static let corsHeaders: [(String, String)] = [
        ("Access-Control-Expose-Headers", "*, Allow, Link, X-WP-Total, X-WP-TotalPages"),
    ]

    /// Request headers the relay strips beyond what
    /// ``ParsedHTTPRequest/urlRequest(url:stripping:)`` already drops.
    ///
    /// That method removes the RFC 9110 §7.6.1 hop-by-hop set — including the
    /// headers this request's own `Connection` names — along with `host` and the
    /// proxy credentials. These are the rest: `content-length` and
    /// `accept-encoding` are recalculated by `URLSession`; `origin`, `referer`
    /// and `sec-fetch-*` describe the web view's fetch context and would leak
    /// the local page to the site (and WordPress rejects a `file://` origin —
    /// the exact problem the relay exists to solve); `authorization` is the
    /// caller's, replaced below by the natively held site credential.
    private static let requestHeadersToStrip: Set<String> = [
        "content-length", "accept-encoding",
        "origin", "referer",
        "sec-fetch-site", "sec-fetch-mode", "sec-fetch-dest", "sec-fetch-user",
        "authorization",
    ]

    /// Upstream response headers dropped from relayed responses.
    ///
    /// The CORS strip is load-bearing: the library adds its permissive CORS
    /// headers with `addingHeadersIfAbsent`, so an upstream
    /// `Access-Control-Allow-Origin` (WordPress sends an empty one for origins
    /// it rejects) would otherwise survive and be honored by WebKit over the
    /// policy's `*`.
    ///
    /// `Content-Encoding` must go because URLSession already decompressed the
    /// body: advertising the upstream encoding would make WebKit decode the
    /// plain bytes a second time, corrupting every gzipped JSON response.
    ///
    /// `Set-Cookie` is the site's, scoped to the site. Passing it on would
    /// store the site's session cookies against `127.0.0.1:<port>` instead —
    /// a different origin, and one whose port belongs to another process after
    /// this server stops. A proxy consumes the upstream's cookies; the relay
    /// carries the site credential natively and never needs them.
    private static let responseHeadersToStrip: Set<String> = [
        "access-control-allow-origin", "access-control-allow-credentials",
        "access-control-allow-headers", "access-control-allow-methods",
        "access-control-expose-headers", "access-control-max-age", "vary",
        "content-encoding",
        "set-cookie", "set-cookie2",
    ]

    /// The upstream response's headers as the editor should see them: the
    /// relay's own CORS headers appended, and the upstream's CORS and
    /// transport-encoding headers dropped (see `responseHeadersToStrip`).
    private static func merged(_ upstream: [(String, String)]) -> [(String, String)] {
        upstream.filter { !responseHeadersToStrip.contains($0.0.lowercased()) } + corsHeaders
    }

    /// Emits a WordPress-REST-style error object rather than plain text, so the
    /// editor decodes a relay failure the same way it decodes WordPress's own —
    /// a `text/plain` body reaches JavaScript as an unparseable `invalid_json`
    /// with the real reason lost.
    static func errorResponse(status: Int, code: String, message: String) -> HTTPResponse {
        .wordPressError(status: status, code: code, message: message, headers: corsHeaders)
    }
}

#endif // canImport(Network)
