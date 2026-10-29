import Foundation
import OSLog

/// Relays the editor's requests through the native networking stack.
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
/// view serves (``RestRelaySchemeHandler``), and this sends the request on,
/// responding with CORS headers we control. Every request takes this path,
/// Lockdown Mode or not, so there is one path to keep working.
///
/// The page sends every request to one route, ``route``, with the URL it was
/// going to fetch. Native code decides how to send it (``destination(of:)``):
///
/// - A URL below the site's REST API root goes to the site, and gets the site
///   credential when the caller sent no `Authorization` of its own.
/// - Any other URL — a plugin calling its own service, for example — goes
///   where it was going. The relay never adds the site credential to it.
///
/// A caller's own `Authorization` is always sent as it arrived. See
/// ``authorization(sentByCaller:toSiteAPI:)``.
///
/// ## Security
///
/// - The scheme doesn't check who is calling. Every frame in the editor's web
///   view can load it, including sandboxed frames that can't reach the page,
///   and the relay attaches the site credential to what they send to the
///   site's REST API. Why that is left as it is: "Who can use the schemes" in
///   `docs/code/media-uploads.md`.
/// - The relay adds the site credential only to a URL it builds itself, from
///   the configured API root and the path below it. The page's URL is matched
///   against the root but never sent with the added credential, so a mistake
///   in the matching can send a request to the user's own site, but can't make
///   the relay send the credential to another host. The built URL is
///   re-checked against the root, and redirects away from it are refused.
/// - Which route *within* the site is reached is the caller's to choose. The
///   query is forwarded as-is, and WordPress registers `rest_route` as a public
///   query variable that `WP::parse_request()` prefers over the route the path
///   names, so a caller-supplied one wins. There is no boundary here to
///   defend: every route reachable that way is one the editor may request
///   through the relay directly.
/// - A caller's own `Authorization` is sent as it is, wherever the request
///   goes, even when it is the site credential. Jetpack AI signs its requests
///   to WordPress.com with a token of its own, and the editor's jQuery AJAX setup
///   sends the site credential to the site's `admin-ajax.php`. Which hosts the page sends the site
///   credential to is decided on the page, before the request reaches the
///   relay. Removing it here would protect nothing: the page already holds the
///   credential, so it can send it anywhere.
/// - The relay reaches any `https` URL, so any frame in the web view can read
///   another host's response without CORS. Without Lockdown Mode the editor
///   page can do that anyway; a sandboxed frame couldn't before.
/// - A request for another host goes over `https`, or over plain `http` only to
///   the site's own host. A device on the local network or this device itself
///   can't present a valid certificate for another host's name, so a name
///   pointed at one fails before anything is sent. Local hosts that do have a
///   valid certificate for their own name stay reachable.
/// - A redirect is followed only to an `http` or `https` URL, never from `https`
///   to `http`. So a request that starts over `https` stays on it.
/// - A URL with a user name or password is refused, as `fetch` refuses one.
///   `URLSession` would store the credential and send it on later requests to
///   that host.
struct RestRelay: Sendable {

    /// The relay's route. Its `url` query parameter is the URL the page was
    /// going to fetch: `/fetch?url=https%3A%2F%2Fexample.org%2Fapi` is a
    /// request for `https://example.org/api`.
    static let route = "/fetch"

    /// Where a relayed request goes.
    enum Destination: Equatable {
        /// The site's REST API, at a URL built from the configured root.
        case siteAPI(URL)

        /// Any other host, at the URL the page asked for.
        case otherHost(URL)
    }

    /// The site's REST API root. A site API request goes to a URL built from
    /// it, and every redirect it follows must stay inside it.
    private let apiRoot: SiteAPIRoot

    /// The site credential: added to a site API request that has no
    /// `Authorization` of its own, and never added to any other request.
    private let authHeader: String

    /// The session upstream requests are sent on.
    private let session: URLSession

    /// Told about each upstream request's task: the host's
    /// ``EditorHTTPClientDelegate``, so relayed requests are observed with the
    /// editor's own.
    private let observer: (any EditorHTTPClientDelegate)?

    /// The hosts of the API root and the site URL, in
    /// ``SiteAPIRoot/canonicalHost(_:)`` form: the only hosts a request may
    /// reach over plain `http`.
    ///
    /// Both, because they can differ: a Jetpack site reached through
    /// WordPress.com has the API root `public-api.wordpress.com`, while its
    /// plugins call the site's own host.
    private let siteHosts: Set<String>

    /// The session every relay shares.
    ///
    /// A `URLSession` holds its resources until it is invalidated, and a relay
    /// is built on every editor load, so one session each would accumulate for
    /// the life of the process. A relayed request is cancelled through its own
    /// task rather than by tearing the session down.
    ///
    /// A relayed request waits as long as an upload: ten minutes without data
    /// (``EditorHTTPClient/uploadInactivityTimeout``). Without the relay, WebKit
    /// sends these requests, and on iOS it gives them no practical timeout: its
    /// per-request value is `INT_MAX` seconds. A shorter limit here fails a slow
    /// post save or plugin endpoint that WebKit would have waited for. Against
    /// a server that never answered (iOS 27.0 Simulator), a 120-second limit
    /// gave the page a `502` while the page's own `fetch` was still waiting
    /// eleven minutes later. Ten minutes outlasts the gateway timeouts hosts
    /// put in front of PHP, so the host's limit is the one that ends a request
    /// that is really stuck.
    ///
    /// It is set on the session, not on each request: a request's own
    /// `timeoutInterval` overrides the session's only once it is set, and
    /// `URLRequest(url:)` doesn't set it.
    ///
    /// The session has no cache. An ephemeral session still caches in memory,
    /// and `URLCache` looks a response up by its URL, not by who asked for it.
    /// Every frame shares this session, and callers send their own tokens, so
    /// a response cached for one caller would answer another. The page can't
    /// opt out either: a `fetch`'s `cache` option never reaches the relay.
    static let sharedSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = EditorHTTPClient.uploadInactivityTimeout
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    /// - Parameters:
    ///   - session: The session to send upstream requests on. Defaults to the
    ///     shared one; tests substitute a stubbed session to exercise
    ///     ``handle(_:)`` without a site.
    ///   - observer: Told about each upstream request's task, or `nil`.
    init(
        configuration: EditorConfiguration,
        session: URLSession? = nil,
        observer: (any EditorHTTPClientDelegate)? = nil
    ) {
        self.apiRoot = SiteAPIRoot(configuration.siteApiRoot)
        self.authHeader = configuration.authHeader
        self.session = session ?? Self.sharedSession
        self.observer = observer
        self.siteHosts = Set(
            [configuration.siteApiRoot.host(), configuration.siteURL.host()].compactMap { $0.map(SiteAPIRoot.canonicalHost) }
        )
    }

    /// Sends a relayed request on. Returns as soon as the response's status and
    /// headers arrive, with CORS headers the page accepts. The body follows in
    /// chunks as the server sends it.
    ///
    /// Throws when the server can't be reached — offline, DNS, TLS, a timeout —
    /// so the scheme handler fails the page's `fetch` the way a network failure
    /// does without the relay. api-fetch turns that into `offline_error` or
    /// `fetch_error`, which Gutenberg's notices key off: a save while offline
    /// says so. Answered with a `502` instead, the failure would read as the
    /// site's error. The relay's own refusals — a URL it can't send, a path
    /// outside the API root, a redirect away from it — are still answered, with
    /// a message the editor shows. If the connection fails after the status and
    /// headers have arrived, the body throws instead.
    ///
    /// - Parameter request: The page's request to the relay scheme. WebKit
    ///   delivers a string or `ArrayBuffer` body as `httpBody` and drops some
    ///   others without an error, so the page reads every body that is not a
    ///   string into an `ArrayBuffer` first (`bufferedBody` in `fetch-relay.js`).
    ///   The table of what was measured is in `docs/code/media-uploads.md`.
    func handle(_ request: URLRequest) async throws -> Response {
        guard let requestedURL = request.url.flatMap(Self.requestedURL(in:)) else {
            Logger.restRelay.error("Refusing to relay a request without an http or https URL")
            return Response(Self.errorResponse(
                status: 400,
                code: "relay_invalid_url",
                message: "The relay can only send a request to an http or https URL."
            ))
        }
        guard !requestedURL.hasCredentials else {
            Logger.restRelay.error("Refusing to relay a request whose URL holds credentials")
            return Response(Self.errorResponse(
                status: 400,
                code: "relay_credentials_in_url",
                message: "The relay can't send a request to a URL with a user name or password in it."
            ))
        }
        guard let destination = destination(of: requestedURL) else {
            Logger.restRelay.error("Refusing to relay a request outside the site API root")
            return Response(Self.errorResponse(
                status: 403,
                code: "relay_forbidden_path",
                message: "The requested path is outside the site API root."
            ))
        }
        let (upstreamURL, isSiteAPI) = switch destination {
        case .siteAPI(let url): (url, true)
        case .otherHost(let url): (url, false)
        }

        if !isSiteAPI, upstreamURL.scheme?.lowercased() == "http", !isSiteHost(upstreamURL) {
            Logger.restRelay.error("Refusing to relay a plain http request to another host")
            return Response(Self.httpsRequired())
        }

        var upstreamRequest = URLRequest(url: upstreamURL)
        upstreamRequest.httpMethod = request.httpMethod
        for (name, value) in request.allHTTPHeaderFields ?? [:] where !Self.requestHeadersToStrip.contains(name.lowercased()) {
            upstreamRequest.setValue(value, forHTTPHeaderField: name)
        }
        upstreamRequest.setValue(
            authorization(sentByCaller: request.value(forHTTPHeaderField: "Authorization"), toSiteAPI: isSiteAPI),
            forHTTPHeaderField: "Authorization"
        )
        upstreamRequest.httpBody = request.httpBody

        // `URLSession` follows redirects on its own. Without `RedirectGuard`, a
        // site API request could be redirected to any host, and the relay would
        // pass that host's response back. The guard keeps a site API request
        // inside the API root, lets a request for another host follow a
        // redirect to any host, and handles `Authorization` on each redirect as
        // `fetch` does. It never follows a redirect from `https` to `http`.
        let redirectGuard = RedirectGuard(
            apiRoot: isSiteAPI ? apiRoot : nil,
            authorization: upstreamRequest.value(forHTTPHeaderField: "Authorization")
        )
        let upstream = UpstreamTask(upstreamRequest, redirectGuard: redirectGuard, observer: observer)
        let (response, body): (URLResponse, AsyncThrowingStream<Data, any Error>)
        do {
            (response, body) = try await upstream.start(on: session)
        } catch {
            Logger.restRelay.error("Upstream request failed: \(error.localizedDescription)")
            throw error
        }

        // Returning a refusal below drops `body`, which cancels the upstream
        // request.
        //
        // When the guard refuses a redirect, `URLSession` returns the 3xx
        // response itself. Don't pass it on: its `Location` header names the
        // refused target, and the page's `fetch` would follow it there.
        if let refusal = redirectGuard.refusal {
            Logger.restRelay.error("Refused a relay redirect")
            return Response(Self.errorResponse(
                status: 502,
                code: "relay_redirect_refused",
                message: "The server redirected this request to \(refusal.target), which \(refusal.reason). The editor did not follow it."
            ))
        }
        guard let response = response as? HTTPURLResponse else {
            return Response(Self.errorResponse(status: 502, code: "relay_upstream_failed", message: "The server did not answer over HTTP."))
        }
        return Response(status: response.statusCode, headers: Self.merged(response.allHeaderFields), body: body)
    }

    /// Whether `url` is on the site's own host, whatever its port.
    private func isSiteHost(_ url: URL) -> Bool {
        url.host().map { siteHosts.contains(SiteAPIRoot.canonicalHost($0)) } ?? false
    }

    /// The answer to a plain `http` request for another host.
    ///
    /// `426 Upgrade Required` is the status for a request that "can't be
    /// completed without TLS" (RFC 2817, section 4.2), and it must name the
    /// protocol to switch to in an `Upgrade` header (RFC 9110, section 15.5.22).
    private static func httpsRequired() -> SchemeResponse {
        var response = errorResponse(
            status: 426,
            code: "relay_https_required",
            message: "The editor only sends a plain http request to the site itself. Use https for any other host."
        )
        response.headers["Upgrade"] = "TLS/1.2, HTTP/1.1"
        return response
    }

    // MARK: - Destination

    /// The URL a request to the relay is for: its `url` query parameter, if
    /// that is an `http` or `https` URL with a host. `nil` otherwise.
    ///
    /// The value is read as written. A URL can hold characters `URL(string:)`
    /// doesn't allow, such as `[]` or `|`. `URL(string:)` percent-encodes them,
    /// but it also encodes the `%` of every escape the URL already had, so
    /// `caf%C3%A9` would reach the server as `caf%25C3%25A9`.
    /// `URL(dataRepresentation:)` encodes only the characters that need it.
    static func requestedURL(in relayURL: URL) -> URL? {
        guard let components = URLComponents(url: relayURL, resolvingAgainstBaseURL: false),
              components.percentEncodedPath == route,
              let value = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let url = URL(dataRepresentation: Data(value.utf8), relativeTo: nil, isAbsolute: true),
              ["http", "https"].contains(url.scheme?.lowercased()),
              url.host() != nil else {
            return nil
        }
        return url
    }

    /// Where a request for `url` goes: the site's REST API when `url` is below
    /// the API root, another host otherwise. `nil` when `url` is below the root
    /// but its path walks out of it. What counts as below the root, host
    /// aliases included, is ``SiteAPIRoot/path(below:)``'s to say.
    ///
    /// Anything else goes where it was going, and the relay doesn't add the
    /// site credential to it. The cost is an alias this can't recognize — a
    /// site reached by LAN IP whose `home_url()` says `localhost`, a mapped
    /// domain, a migration — where a paginated `Link` target the caller sent
    /// without a credential reaches the site without one.
    func destination(of url: URL) -> Destination? {
        guard let path = apiRoot.path(below: url) else {
            return .otherHost(url)
        }
        return apiRoot.url(forPath: path).map(Destination.siteAPI)
    }

    // MARK: - Authorization

    /// The `Authorization` header to send upstream, or `nil` for none.
    ///
    /// The caller's own header is sent as it arrived, wherever the request
    /// goes. It is never removed or replaced, even when it is the site
    /// credential, or the site credential joined to another value. A request
    /// that arrives without one gets the site credential if it is for the
    /// site's REST API, and nothing otherwise.
    func authorization(sentByCaller callerValue: String?, toSiteAPI: Bool) -> String? {
        if let callerValue {
            return callerValue
        }
        return toSiteAPI && !authHeader.isEmpty ? authHeader : nil
    }

    /// Refuses redirects that leave the site API root.
    ///
    /// `URLSession` follows 3xx responses automatically, so without this the
    /// containment check would only ever apply to the first hop: a site that
    /// redirected `/wp-json/wp/v2/posts` elsewhere would have the request
    /// followed to that host, and its response relayed back to the editor.
    /// Refusing hands the 3xx itself back instead.
    ///
    /// A target is inside the root when ``SiteAPIRoot/contains(_:)`` says so,
    /// the same check ``destination(of:)`` makes, so the two agree. Another
    /// path on the same site (`/wp-login.php`), another port, and another host
    /// are refused: a site API request reaches only the API it was configured
    /// for. The site's other spellings of its own host, such as its `www.`
    /// name, are followed. Otherwise a site whose canonical redirect names one
    /// would have every relayed request refused. The cost is that a legitimate
    /// permalink-structure redirect is refused too, which the response says
    /// specifically enough to diagnose.
    ///
    /// A `307` or `308` it follows has `URLSession` resend the body, which it can:
    /// a scheme request's body is `Data`, held in memory.
    ///
    /// Without an API root it follows a redirect to any host. That is the
    /// guard for a request to another host, which the relay adds no site
    /// credential to.
    ///
    /// Every request, with a root or without, follows a redirect only to an
    /// `http` or `https` URL without a user name or password, and never from
    /// `https` to `http`. `URLSession` would follow a redirect to a `data:` or
    /// `ftp:` URL, and to `http` from `https`. A request for another host may go
    /// over plain `http` only to the site's own host, so a chain of plain `http`
    /// redirects can only start at the site.
    ///
    /// `URLSession` drops `Authorization` on every redirect it follows, even one to
    /// the same server. Given the request's `Authorization` — the site credential
    /// or the caller's own — the guard puts it back the way WebKit's `fetch` does:
    /// on a redirect to the same scheme, host, and port. Once a redirect goes
    /// anywhere else the guard removes the header, and it stays off even if a
    /// later redirect comes back. So the `www.` alias and the `https` upgrade it
    /// follows within the API root arrive without it, as they would from `fetch`.
    ///
    /// ``UpstreamTask`` is the task's delegate, and forwards each redirect to it.
    /// The guard isn't a delegate itself: given to a task directly, it would
    /// replace ``UpstreamTask``: the response would stop streaming, and the
    /// observer would hear nothing.
    ///
    /// `@unchecked Sendable`: the root is a `let` set at init; the refusal
    /// and the request's `Authorization` are kept under a lock.
    final class RedirectGuard: @unchecked Sendable {
        /// A redirect the guard refused.
        struct Refusal: Equatable {
            /// Where the redirect went, without any user name or password.
            let target: String

            /// Why it was refused, worded to follow "which".
            let reason: String
        }

        /// The site's API root, or `nil` to follow a redirect to any host.
        private let apiRoot: SiteAPIRoot?

        private let lock = NSLock()
        private var _refusal: Refusal?

        /// The request's `Authorization`, until a redirect leaves its origin.
        private var _authorization: String?

        /// The redirect that was refused, or `nil` if none was.
        var refusal: Refusal? {
            lock.withLock { _refusal }
        }

        init(apiRoot: SiteAPIRoot?, authorization: String? = nil) {
            self.apiRoot = apiRoot
            self._authorization = authorization
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            guard let url = request.url else {
                lock.withLock { _refusal = Refusal(target: "an unreadable URL", reason: "the editor can't read") }
                completionHandler(nil)
                return
            }
            if let reason = refusalReason(from: response.url, to: url) {
                let target = url.removingCredentials()?.absoluteString ?? "a URL with a user name or password in it"
                lock.withLock { _refusal = Refusal(target: target, reason: reason) }
                completionHandler(nil)
                return
            }
            var request = request
            // Set either way: `nil` removes the header, rather than relying on
            // `URLSession` having dropped it.
            request.setValue(authorization(redirectingFrom: response.url, to: url), forHTTPHeaderField: "Authorization")
            completionHandler(request)
        }

        /// Why a redirect from `source` to `target` can't be followed, worded to
        /// follow "which", or `nil` if it can.
        private func refusalReason(from source: URL?, to target: URL) -> String? {
            switch target.scheme?.lowercased() {
            case "https":
                break
            case "http":
                if source?.scheme?.lowercased() == "https" {
                    return "would leave https"
                }
            default:
                return "isn't an http or https URL"
            }
            if target.hasCredentials {
                return "has a user name or password in it"
            }
            if let apiRoot, !apiRoot.contains(target) {
                return "is outside the site's configured REST API root"
            }
            return nil
        }

        /// The request's `Authorization` to send on a redirect from `source` to
        /// `target`, or `nil` once a redirect has left the original origin.
        private func authorization(redirectingFrom source: URL?, to target: URL) -> String? {
            lock.withLock {
                let sameOrigin = source?.origin.map { $0 == target.origin } ?? false
                if !sameOrigin {
                    _authorization = nil
                }
                return _authorization
            }
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
    /// the relay carries the site credential itself; `authorization` is set on
    /// its own, by ``authorization(sentByCaller:toSiteAPI:)``.
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
