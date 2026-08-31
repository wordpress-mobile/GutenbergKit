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

    /// The session every relay shares.
    ///
    /// A `URLSession` holds its resources until it is invalidated, and a relay
    /// is built on every editor load under Lockdown Mode, so one session each
    /// would accumulate for the life of the process. Nothing about the session
    /// is per-relay, and a relayed request is cancelled through its own task
    /// rather than by tearing the session down.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }()

    init(configuration: EditorConfiguration) {
        var root = configuration.siteApiRoot.absoluteString
        if !root.hasSuffix("/") {
            root += "/"
        }
        self.apiRoot = root
        self.authHeader = configuration.authHeader
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

        var upstreamRequest = URLRequest(url: upstreamURL)
        upstreamRequest.httpMethod = parsed.method

        for (name, value) in parsed.allHeaders where !Self.requestHeadersToStrip.contains(name.lowercased()) {
            upstreamRequest.setValue(value, forHTTPHeaderField: name)
        }
        if !authHeader.isEmpty {
            upstreamRequest.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }

        if let body = parsed.body {
            if let data = body.inMemoryData {
                upstreamRequest.httpBody = data
            } else {
                // Large bodies are buffered to disk by the request parser;
                // stream them to avoid loading uploads fully into memory.
                //
                // `count` is a file-size lookup, and reports zero when it
                // fails. Sending that as the `Content-Length` of a body the
                // parser says exists would upload nothing, and WordPress
                // answers a no-op with a 2xx the editor would take for success.
                do {
                    let length = body.count
                    guard length > 0 else {
                        Logger.restRelay.error("Refusing to relay a request body whose length could not be read")
                        return Self.errorResponse(status: 500, code: "relay_body_unreadable", message: "Failed to read the request body.")
                    }
                    upstreamRequest.httpBodyStream = try body.makeInputStream()
                    upstreamRequest.setValue("\(length)", forHTTPHeaderField: "Content-Length")
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
            let redirectGuard = RedirectGuard(allowedPrefix: apiRoot)
            let upstream = HTTPResponse(try await Self.session.data(for: upstreamRequest, delegate: redirectGuard))

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
                headers: Self.merge(upstream.headers, adding: Self.corsHeaders),
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
        let path = request.path
        guard path == Self.route || path.hasPrefix("\(Self.route)/") else { return nil }

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
    /// The comparison is a prefix match on the whole URL, not just its host,
    /// so a redirect to another path on the same site — `/wp-login.php` for a
    /// request to `/wp-json/…` — is refused too. The site credential should
    /// follow the request only to the API it was configured for. It also means
    /// a scheme downgrade fails without a rule of its own, since `http://…`
    /// cannot prefix-match an `https://` root.
    ///
    /// The known cost: a redirect that changes permalink structure — pretty
    /// REST URLs to `?rest_route=`, or the reverse after a permalink change —
    /// is a legitimate redirect that this refuses. Refusing is the right
    /// default because it cannot hand the credential somewhere unverified, and
    /// the response says so specifically enough to find.
    ///
    /// The comparison is origin-exact, unlike the JavaScript side's, which
    /// tolerates host aliases when recognizing a site URL. That asymmetry is
    /// deliberate: recognizing an alias decides where a request is *sent*,
    /// while this decides whether the site credential *follows* a redirect
    /// somewhere we did not choose. A canonical redirect onto an alias host is
    /// refused here rather than followed.
    ///
    /// `@unchecked Sendable`: `allowedPrefix` is a `let` set at init; the
    /// refusal is recorded under a lock.
    final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let allowedPrefix: String
        private let lock = NSLock()
        private var _refusedTarget: String?

        /// The redirect target that was refused, or `nil` if none was.
        var refusedTarget: String? {
            lock.withLock { _refusedTarget }
        }

        init(allowedPrefix: String) {
            self.allowedPrefix = allowedPrefix
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            guard let url = request.url, url.absoluteString.hasPrefix(allowedPrefix) else {
                lock.withLock { _refusedTarget = request.url?.absoluteString ?? "an unreadable URL" }
                completionHandler(nil)
                return
            }
            completionHandler(request)
        }
    }

    // MARK: - CORS

    /// Response headers added to every relayed response. The library's
    /// permissive CORS policy stamps `Access-Control-Allow-Origin` and friends;
    /// the exposed headers keep paginated REST responses readable to
    /// `api-fetch` callers.
    ///
    /// `Allow` is what `canUser` reads off an `OPTIONS` response to decide
    /// whether the user may create a page, update settings, upload media, or
    /// edit global styles; without it every such capability reads as false with
    /// no error surfaced. `Link` backs `fetchAllMiddleware`'s pagination and
    /// `X-WP-Total`/`X-WP-TotalPages` back list counts. Nothing else in the
    /// editor reads a response header.
    private static let corsHeaders: [(String, String)] = [
        ("Access-Control-Expose-Headers", "Allow, Link, X-WP-Total, X-WP-TotalPages"),
    ]

    /// Request headers that must not be forwarded upstream.
    ///
    /// `host`/`content-length`/`accept-encoding` are recalculated by URLSession;
    /// `origin`, `referer`, and `sec-fetch-*` describe the web view's fetch
    /// context and would leak the local page to the server (and WordPress
    /// rejects `file://` origins — the exact problem the relay exists to
    /// solve); the rest are relay-internal.
    private static let requestHeadersToStrip: Set<String> = [
        "host", "content-length", "accept-encoding", "connection",
        "origin", "referer",
        "sec-fetch-site", "sec-fetch-mode", "sec-fetch-dest", "sec-fetch-user",
        "authorization", "relay-authorization", "proxy-authorization",
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
    private static let responseHeadersToStrip: Set<String> = [
        "access-control-allow-origin", "access-control-allow-credentials",
        "access-control-allow-headers", "access-control-allow-methods",
        "access-control-expose-headers", "access-control-max-age", "vary",
        "content-encoding",
    ]

    /// Appends local response headers to upstream headers, dropping the
    /// upstream's own CORS and transport-encoding headers (see
    /// `responseHeadersToStrip`).
    private static func merge(
        _ upstream: [(String, String)],
        adding cors: [(String, String)]
    ) -> [(String, String)] {
        upstream.filter { !Self.responseHeadersToStrip.contains($0.0.lowercased()) } + cors
    }

    /// Emits a WordPress-REST-style error object rather than plain text, so the
    /// editor decodes a relay failure the same way it decodes WordPress's own —
    /// a `text/plain` body reaches JavaScript as an unparseable `invalid_json`
    /// with the real reason lost.
    static func errorResponse(status: Int, code: String, message: String) -> HTTPResponse {
        let payload = ["code": code, "message": message]
        let body = (try? JSONSerialization.data(withJSONObject: payload))
            ?? Data(#"{"code":"relay_error","message":"The editor could not reach the site."}"#.utf8)
        return HTTPResponse(
            status: status,
            headers: corsHeaders + [("Content-Type", "application/json")],
            body: body
        )
    }
}

extension Logger {
    static let restRelay = Logger(subsystem: "GutenbergKit", category: "rest-relay")
}

#endif // canImport(Network)
