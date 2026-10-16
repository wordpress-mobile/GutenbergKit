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
///   where it was going, and never carries the site credential.
///
/// ## Security
///
/// - The scheme doesn't check who is calling. Every frame in the editor's web
///   view can load it, including sandboxed frames that can't reach the page,
///   and the relay attaches the site credential to what they send to the
///   site's REST API. Why that is left as it is: "Who can use the schemes" in
///   `docs/code/media-uploads.md`.
/// - The site credential only goes to a URL the relay builds itself, from the
///   configured API root and the path below it. The page's URL is matched
///   against the root but never sent with the credential, so a mistake in the
///   matching can send a request to the user's own site, but can't send the
///   credential to another host. The built URL is re-checked against the
///   root, and redirects away from it are refused.
/// - Which route *within* the site is reached is the caller's to choose. The
///   query is forwarded as-is, and WordPress registers `rest_route` as a public
///   query variable that `WP::parse_request()` prefers over the route the path
///   names, so a caller-supplied one wins. There is no boundary here to
///   defend: every route reachable that way is one the editor may request
///   through the relay directly.
/// - A caller's own `Authorization` is sent as it is, wherever the request
///   goes. It is the caller's credential, to send where it likes — Jetpack AI
///   signs its requests to WordPress.com with a token of its own. The site
///   credential is the relay's to guard: see
///   ``authorization(sentByCaller:toSiteAPI:)``.
/// - The relay reaches any `http` or `https` URL, so any frame in the web view
///   can read another host's response without CORS, a local network address
///   included. Without Lockdown Mode the editor page can do that anyway; a
///   sandboxed frame couldn't before.
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

    /// The site's API root, slash-terminated. Upstream paths are appended to
    /// it, and every resulting URL — including redirect targets — must still
    /// start with it.
    ///
    /// Held as a string rather than a `URL` because the root is not always
    /// directory-shaped: a site on plain permalinks has
    /// `https://example.com/?rest_route=/`, where relative URL resolution would
    /// discard the query.
    private let apiRoot: String

    /// The site credential: added to a site API request that has no
    /// `Authorization` of its own, and never sent to another host.
    private let authHeader: String

    /// The session upstream requests are sent on.
    private let session: URLSession

    /// Told about each upstream request's task: the host's
    /// ``EditorHTTPClientDelegate``, so relayed requests are observed with the
    /// editor's own.
    private let observer: (any EditorHTTPClientDelegate)?

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
    static let sharedSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = EditorHTTPClient.uploadInactivityTimeout
        configuration.httpCookieStorage = nil
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
        self.apiRoot = Self.normalizedRoot(configuration.siteApiRoot.absoluteString)
        self.authHeader = configuration.authHeader
        self.session = session ?? Self.sharedSession
        self.observer = observer
    }

    /// The configured root, slash-terminated, with the route value of a
    /// plain-permalink root decoded.
    ///
    /// WordPress advertises that root through `add_query_arg`, which
    /// percent-encodes the value: `index.php?rest_route=%2F`. The separators
    /// are decoded before the slash is added so it lands inside the route
    /// value. Appended after `%2F`, it would make a root no path can extend:
    /// WordPress reads `rest_route=%2F/wp/v2/posts` as the route
    /// `//wp/v2/posts` and answers `rest_no_route`.
    private static func normalizedRoot(_ configured: String) -> String {
        var root = configured
        if let query = root.firstIndex(of: "?") {
            root = String(root[..<query]) + decodingSlashes(root[query...])
        }
        return root.hasSuffix("/") ? root : root + "/"
    }

    /// `component` with its percent-encoded slashes decoded, and nothing else.
    ///
    /// Only the separators are decoded, so any other encoded byte reaches the
    /// site exactly as it was sent, rather than decoded once here and once more
    /// by PHP.
    private static func decodingSlashes(_ component: some StringProtocol) -> String {
        component.replacingOccurrences(of: "%2f", with: "/", options: .caseInsensitive)
    }

    /// Sends a relayed request on and returns the upstream response with
    /// permissive CORS headers.
    ///
    /// Throws when the server can't be reached — offline, DNS, TLS, a timeout —
    /// so the scheme handler fails the page's `fetch` the way a network failure
    /// does without the relay. api-fetch turns that into `offline_error` or
    /// `fetch_error`, which Gutenberg's notices key off: a save while offline
    /// says so. Answered with a `502` instead, the failure would read as the
    /// site's error. The relay's own refusals — a URL it can't send, a path
    /// outside the API root, a redirect away from it — are still answered, with
    /// a message the editor shows.
    ///
    /// - Parameter request: The page's request to the relay scheme. WebKit
    ///   delivers a string or `ArrayBuffer` body as `httpBody` and drops some
    ///   others without an error, so the page reads every body that is not a
    ///   string into an `ArrayBuffer` first (`bufferedBody` in `fetch-relay.js`).
    ///   The table of what was measured is in `docs/code/media-uploads.md`.
    func handle(_ request: URLRequest) async throws -> SchemeResponse {
        guard let requestedURL = request.url.flatMap(Self.requestedURL(in:)) else {
            Logger.restRelay.error("Refusing to relay a request without an http or https URL")
            return Self.errorResponse(
                status: 400,
                code: "relay_invalid_url",
                message: "The relay can only send a request to an http or https URL."
            )
        }
        guard let destination = destination(of: requestedURL) else {
            Logger.restRelay.error("Refusing to relay a request outside the site API root")
            return Self.errorResponse(
                status: 403,
                code: "relay_forbidden_path",
                message: "The requested path is outside the site API root."
            )
        }
        let (upstreamURL, isSiteAPI) = switch destination {
        case .siteAPI(let url): (url, true)
        case .otherHost(let url): (url, false)
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

        let reporter = observer.map(NetworkTaskReporter.init(reportingTo:))
        do {
            // The redirect guard is a per-task delegate: `URLSession` follows
            // 3xx responses on its own, which would carry a site API request
            // to whatever host the `Location` header names and relay that
            // response back. See ``RedirectGuard``. A request for another host
            // follows every redirect. Either keeps its `Authorization` on a
            // redirect the way `fetch` would.
            let redirectGuard = RedirectGuard(
                allowedPrefix: isSiteAPI ? apiRoot : nil,
                authorization: upstreamRequest.value(forHTTPHeaderField: "Authorization"),
                reporter: reporter
            )
            let (body, response) = try await session.data(for: upstreamRequest, delegate: redirectGuard)
            reporter?.complete(with: .bytes(body), error: nil)

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
                return Self.errorResponse(status: 502, code: "relay_upstream_failed", message: "The server did not answer over HTTP.")
            }
            observer?.didPerformRequest(upstreamRequest, response: response, data: .bytes(body))

            return SchemeResponse(
                status: response.statusCode,
                headers: Self.merged(response.allHeaderFields),
                body: body
            )
        } catch {
            reporter?.complete(with: nil, error: error)
            Logger.restRelay.error("Upstream request failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Destination

    /// The URL a request to the relay is for: its `url` query parameter, if
    /// that is an `http` or `https` URL with a host. `nil` otherwise.
    static func requestedURL(in relayURL: URL) -> URL? {
        guard let components = URLComponents(url: relayURL, resolvingAgainstBaseURL: false),
              components.percentEncodedPath == route,
              let value = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased()),
              url.host() != nil else {
            return nil
        }
        return url
    }

    /// Where a request for `url` goes: the site's REST API when `url` is below
    /// the API root, another host otherwise. `nil` when `url` is below the root
    /// but its path walks out of it.
    ///
    /// **Host aliases are tolerated; other hosts and path differences are
    /// not.** WordPress builds `Link` headers and `_links` hrefs from
    /// `home_url()`, which need not spell the host the app was configured with
    /// — `www.` versus bare, or wp-env's `localhost` versus the `127.0.0.1` its
    /// runtime writes into `WP_SITEURL`. The scheme may differ too — an `http`
    /// `siteurl` behind a TLS-terminating proxy — since the request is sent to
    /// the configured root whichever it names. The port has to match: another
    /// port on the same host is another server, and answering its request with
    /// the site's response is a different bug from the one this tolerance
    /// exists to fix. A *path* difference is likewise a different resource: in
    /// a subdirectory multisite `https://site/a/wp-json/` and
    /// `https://site/b/wp-json/` are separate sites.
    ///
    /// Anything else goes where it was going, without the site credential. The
    /// cost is an alias this can't recognize — a site reached by LAN IP whose
    /// `home_url()` says `localhost`, a mapped domain, a migration — where a
    /// paginated `Link` target reaches the site without the credential.
    func destination(of url: URL) -> Destination? {
        guard let path = pathBelowRoot(of: url) else {
            return .otherHost(url)
        }
        return upstreamURL(forPath: path).map(Destination.siteAPI)
    }

    /// The part of `url` below the site API root — its path and query, without
    /// a leading slash — or `nil` when `url` isn't below the root.
    private func pathBelowRoot(of url: URL) -> String? {
        guard let target = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let root = URLComponents(string: apiRoot),
              let targetHost = target.host, let rootHost = root.host,
              Self.canonicalHost(targetHost) == Self.canonicalHost(rootHost),
              Self.explicitPort(of: target) == Self.explicitPort(of: root) else {
            return nil
        }

        if root.percentEncodedQuery != nil {
            return Self.queryRoutedPath(of: target, below: root)
        }

        let rootPath = Self.path(of: root)
        let targetPath = Self.path(of: target)
        guard targetPath.hasPrefix(rootPath) else { return nil }
        return String(targetPath.dropFirst(rootPath.count)) + (target.percentEncodedQuery.map { "?\($0)" } ?? "")
    }

    /// The port `components` names, or `nil` when it names none or its scheme's
    /// default — so `https://example.com:443` and `http://example.com` agree.
    private static func explicitPort(of components: URLComponents) -> Int? {
        guard let port = components.port, port != defaultPort(for: components.scheme) else { return nil }
        return port
    }

    /// The path below a root that carries its route in the query — plain
    /// permalinks, `https://site/index.php?rest_route=/` — or `nil` when
    /// `target` isn't below it.
    ///
    /// A prefix match can't decide this shape: the root spells the route `/`,
    /// and every request spells it `%2F`. api-fetch's locale middleware
    /// rebuilds the query through `addQueryArgs`, and WordPress builds
    /// pagination `Link` URLs through `add_query_arg`; both percent-encode every
    /// value. So the route is read out of the query by name, its separators
    /// decoded, and the other parameters are carried verbatim after a `?`.
    /// ``upstreamURL(forPath:)`` merges them into the root's query.
    private static func queryRoutedPath(of target: URLComponents, below root: URLComponents) -> String? {
        guard path(of: target) == path(of: root), let rootQuery = root.percentEncodedQuery else { return nil }

        // The root's query is the single `rest_route=/` pair `get_rest_url()`
        // emits; on a namespaced site the value is longer (`/sites/1/`), but it
        // is still the one parameter every request continues.
        let rootRoute = queryPair(rootQuery)
        var pairs = (target.percentEncodedQuery ?? "")
            .split(separator: "&", omittingEmptySubsequences: false)
            .map(String.init)
        guard let index = pairs.firstIndex(where: { queryPair($0).name == rootRoute.name }) else { return nil }

        let route = decodingSlashes(queryPair(pairs.remove(at: index)).value)
        guard route.hasPrefix(rootRoute.value) else { return nil }

        let path = route.dropFirst(rootRoute.value.count)
        let query = pairs.joined(separator: "&")
        return query.isEmpty ? String(path) : "\(path)?\(query)"
    }

    /// `components`' path, `/` when it has none.
    private static func path(of components: URLComponents) -> String {
        components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
    }

    /// A `name=value` query pair split at its first `=`, verbatim.
    private static func queryPair(_ pair: String) -> (name: String, value: String) {
        guard let separator = pair.firstIndex(of: "=") else { return (pair, "") }
        return (String(pair[..<separator]), String(pair[pair.index(after: separator)...]))
    }

    /// The site API URL for `path` — a path and query below the API root — or
    /// `nil` if the result would address anything outside the root.
    ///
    /// The path is appended to the API root. Appending rather than resolving is
    /// what `createRootURLMiddleware` does on the JavaScript side, and it is the
    /// only approach that works for both root shapes WordPress produces: pretty
    /// permalinks give `https://example.com/wp-json/`, plain permalinks give
    /// `https://example.com/?rest_route=/`, where the path has to merge into an
    /// existing query string.
    ///
    /// Dot segments — literal or percent-encoded — are refused rather than
    /// normalized. A REST path never contains one, `URLSession` resolves them
    /// before sending, and a normalized `..` is the one thing that could walk
    /// out of the API root and reach the rest of the site with the credential
    /// attached.
    private func upstreamURL(forPath path: String) -> URL? {
        let separator = path.firstIndex(of: "?")
        // Leading slashes are dropped, so the path appends to the API root
        // rather than resolving against the site root.
        let relativePath = path[..<(separator ?? path.endIndex)].drop(while: { $0 == "/" })
        guard !Self.containsDotSegment(relativePath) else { return nil }

        var suffix = String(relativePath) + (separator.map { String(path[$0...]) } ?? "")
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

    /// A host reduced to the form its aliases share: every loopback spelling
    /// collapses to one, and a `www.` prefix is dropped.
    ///
    /// ``destination(of:)`` and ``RedirectGuard`` both read hosts through this,
    /// so a spelling one accepts as the site, the other does too. Otherwise a
    /// site whose canonical redirect uses that spelling would have every
    /// request refused.
    private static func canonicalHost(_ host: String) -> String {
        let lowercased = host.lowercased()
        if ["localhost", "127.0.0.1", "::1", "[::1]"].contains(lowercased) {
            return "localhost"
        }
        return lowercased.hasPrefix("www.") ? String(lowercased.dropFirst(4)) : lowercased
    }

    private static func defaultPort(for scheme: String?) -> Int? {
        switch scheme?.lowercased() {
        case "http": return 80
        case "https": return 443
        default: return nil
        }
    }

    // MARK: - Authorization

    /// The `Authorization` header to send upstream, or `nil` for none.
    ///
    /// The caller's own header is sent as it is. The site credential is added
    /// to a request for the site's REST API that has none, and removed from a
    /// request for any other host. The page can put it there: api-fetch's
    /// `tokenAuthMiddleware` adds it to every request it makes, whatever the
    /// host.
    func authorization(sentByCaller callerValue: String?, toSiteAPI: Bool) -> String? {
        let siteCredential = authHeader.isEmpty ? nil : authHeader
        if toSiteAPI {
            return callerValue ?? siteCredential
        }
        return callerValue == siteCredential ? nil : callerValue
    }

    /// Refuses redirects that leave the site API root.
    ///
    /// `URLSession` follows 3xx responses automatically, so without this the
    /// containment check would only ever apply to the first hop: a site that
    /// redirected `/wp-json/wp/v2/posts` elsewhere would have the request
    /// followed to that host, and its response relayed back to the editor.
    /// Refusing hands the 3xx itself back instead.
    ///
    /// The comparison is a prefix match on the whole URL, read through the
    /// host spellings ``destination(of:)`` tolerates — `www.` versus bare, the
    /// loopback names — and an `http`→`https` upgrade. So another path on the
    /// same site (`/wp-login.php`), another port, another host, and a scheme
    /// downgrade are refused: a site API request reaches only the API it was
    /// configured for. The cost is that a legitimate
    /// permalink-structure redirect is refused too, which the response says
    /// specifically enough to diagnose.
    ///
    /// The host spellings are the ones ``destination(of:)`` accepts, so that the
    /// two agree. A `Link` target on the `www.` alias goes to the site, and a
    /// site whose canonical redirect names that alias — or whose `siteurl` is
    /// `http` behind a TLS-terminating proxy — would otherwise have every
    /// relayed request refused here. Containment holds: the same site under
    /// another of its own names, and a strictly stronger scheme.
    ///
    /// A `307` or `308` it follows has `URLSession` resend the body, which it can:
    /// a scheme request's body is `Data`, held in memory.
    ///
    /// Without an allowed prefix it follows every redirect. That is the guard for a
    /// request to another host, which carries no site credential.
    ///
    /// `URLSession` drops `Authorization` on every redirect it follows, even one to
    /// the same server. Given the request's `Authorization` — the site credential
    /// or the caller's own — the guard puts it back the way WebKit's `fetch` does:
    /// on a redirect to the same scheme, host, and port. Once a redirect goes
    /// anywhere else the header stays off, even if a later redirect comes back. So
    /// the `www.` alias and the `https` upgrade it follows within the API root
    /// arrive without it, as they would from `fetch`.
    ///
    /// `@unchecked Sendable`: the prefixes are `let`s set at init; the refusal and
    /// the request's `Authorization` are kept under a lock.
    final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        /// The API root, in the form ``normalized(_:)`` gives a target, or `nil`
        /// to follow every redirect.
        private let allowedPrefix: String?

        /// `allowedPrefix` under `https`, when the configured root is `http`.
        private let upgradedPrefix: String?

        /// Reports the task, which this delegate sees as the task's only one.
        private let reporter: NetworkTaskReporter?

        private let lock = NSLock()
        private var _refusedTarget: String?

        /// The request's `Authorization`, until a redirect leaves its origin.
        private var _authorization: String?

        /// The redirect target that was refused, or `nil` if none was.
        var refusedTarget: String? {
            lock.withLock { _refusedTarget }
        }

        init(allowedPrefix: String?, authorization: String? = nil, reporter: NetworkTaskReporter? = nil) {
            self.reporter = reporter
            self._authorization = authorization
            let root = allowedPrefix.map { Self.normalized($0) ?? $0 }
            self.allowedPrefix = root
            let insecureScheme = "http://"
            self.upgradedPrefix = root.flatMap {
                $0.hasPrefix(insecureScheme) ? "https://" + $0.dropFirst(insecureScheme.count) : nil
            }
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
            var request = request
            if let authorization = authorization(redirectingFrom: response.url, to: url) {
                request.setValue(authorization, forHTTPHeaderField: "Authorization")
            }
            completionHandler(request)
        }

        func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
            reporter?.urlSession(session, didCreateTask: task)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
            reporter?.urlSession(session, task: task, didFinishCollecting: metrics)
        }

        /// Whether `target` is inside the API root, allowing only the host
        /// spelling and a scheme upgrade to differ. Always `true` without an
        /// allowed prefix.
        private func contains(_ target: String) -> Bool {
            guard let allowedPrefix else { return true }
            guard let target = Self.normalized(target) else { return false }
            if target.hasPrefix(allowedPrefix) {
                return true
            }
            guard let upgradedPrefix else { return false }
            return target.hasPrefix(upgradedPrefix)
        }

        /// The request's `Authorization` to send on a redirect from `source` to
        /// `target`, or `nil` once a redirect has left the original origin.
        private func authorization(redirectingFrom source: URL?, to target: URL) -> String? {
            lock.withLock {
                let sameOrigin = Self.origin(of: source).map { $0 == Self.origin(of: target) } ?? false
                if !sameOrigin {
                    _authorization = nil
                }
                return _authorization
            }
        }

        /// `url`'s scheme, host, and port, with a default port filled in. `nil` for a
        /// URL without a host.
        private static func origin(of url: URL?) -> String? {
            guard let url,
                  let scheme = url.scheme?.lowercased(),
                  let host = url.host()?.lowercased(),
                  let port = url.port ?? RestRelay.defaultPort(for: scheme) else {
                return nil
            }
            return "\(scheme)://\(host):\(port)"
        }

        /// `url` with its host in the form its aliases share and a default
        /// port dropped, so that a prefix comparison reads through the
        /// spellings ``RestRelay/destination(of:)`` tolerates. `nil` for a URL
        /// without a host.
        private static func normalized(_ url: String) -> String? {
            guard var components = URLComponents(string: url), let host = components.host else {
                return nil
            }
            components.host = RestRelay.canonicalHost(host)
            if let port = components.port, port == RestRelay.defaultPort(for: components.scheme) {
                components.port = nil
            }
            return components.string
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
