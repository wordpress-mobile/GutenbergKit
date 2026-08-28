import Foundation
import OSLog

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
/// every response.
///
/// The relay sidesteps the problem: `api-fetch` addresses the editor's REST
/// traffic to the ``RestRelay/scheme`` scheme, ``RestSchemeHandler`` serves it
/// in-process, and this type forwards the request to the site's REST API with
/// the configured authorization header, answering with CORS headers we control.
///
/// ## Transport
///
/// A custom scheme is in-process: no listening socket, so nothing outside this
/// web view can reach it and no bearer token is needed. Media uploads stay on
/// ``MediaUploadServer`` instead — WebKit withholds blob-backed request bodies
/// from a scheme handler entirely (see ``bodyMarkerHeader``), and that server
/// exists to run the host's `MediaUploadDelegate` regardless.
struct RestRelay: Sendable {

    /// The URL scheme the editor addresses its REST traffic to.
    static let scheme = "gbk-rest"

    /// The root URL handed to `api-fetch`'s `createRootURLMiddleware`, so every
    /// request built from a `path` is addressed to the relay.
    ///
    /// The authority is deliberately empty (`gbk-rest:///…`), matching
    /// ``MediaFileManager``'s `gbk-media-file:///` URLs: the path carries the
    /// REST path, and there is no host to be mistaken for a forwarding target.
    static let rootURL = "\(scheme):///"

    /// Set by the editor's api-fetch middleware when it attached a request
    /// body, so a body WebKit withheld can be told apart from one that was
    /// never sent (see ``RelayResponse/bodyUnavailable``).
    static let bodyMarkerHeader = "X-GBK-Relay-Body"

    /// The site's REST API root that relayed paths resolve against.
    private let siteApiRoot: URL

    /// The authorization header injected into upstream requests.
    private let authHeader: String

    private let session: URLSession

    init(configuration: EditorConfiguration) {
        self.init(siteApiRoot: configuration.siteApiRoot, authHeader: configuration.authHeader)
    }

    init(siteApiRoot: URL, authHeader: String) {
        self.siteApiRoot = siteApiRoot
        self.authHeader = authHeader

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = 120
        sessionConfiguration.httpCookieStorage = nil
        self.session = URLSession(configuration: sessionConfiguration)
    }

    /// Forwards a relayed request to the site's REST API and returns the
    /// upstream response with the CORS headers the web view needs to read it.
    func response(for request: URLRequest) async -> RelayResponse {
        guard let relayURL = request.url,
              let upstreamURL = Self.upstreamURL(for: relayURL, siteApiRoot: siteApiRoot) else {
            return .error(status: 400, code: "relay_invalid_url", message: "The editor addressed a request the relay cannot resolve.")
        }

        // WebKit hands a scheme handler no bytes at all for a blob-backed body
        // (a `Blob`, or `FormData` containing a `File`), with no error. Left
        // alone, WordPress would accept the bodyless write as a no-op and the
        // editor would report success while losing the content. The marker says
        // a body was attached, so its absence here means the bytes were dropped.
        if request.value(forHTTPHeaderField: Self.bodyMarkerHeader) != nil,
           request.httpBody == nil, request.httpBodyStream == nil {
            Logger.restRelay.error("Request body was withheld by WebKit: \(request.httpMethod ?? "GET") \(relayURL.path)")
            return .bodyUnavailable
        }

        var upstreamRequest = URLRequest(url: upstreamURL)
        upstreamRequest.httpMethod = request.httpMethod ?? "GET"

        for (name, value) in request.allHTTPHeaderFields ?? [:] where !Self.requestHeadersToStrip.contains(name.lowercased()) {
            upstreamRequest.setValue(value, forHTTPHeaderField: name)
        }
        if !authHeader.isEmpty {
            upstreamRequest.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }
        upstreamRequest.httpBody = request.httpBody

        // `URLSession` follows redirects by default, which would carry the
        // injected `Authorization` to whatever host the response named and
        // relay that host's body back. The guard is per-request so its verdict
        // can be read once the task finishes.
        let redirectGuard = RedirectGuard(apiRoot: siteApiRoot)

        do {
            let (data, response) = try await session.data(for: upstreamRequest, delegate: redirectGuard)

            if let refusedURL = redirectGuard.refusedRedirectURL {
                Logger.restRelay.error("Refusing to follow a redirect off the site's host: \(refusedURL.host ?? "<no host>")")
                return .error(status: 502, code: "relay_redirect_refused", message: "The site redirected the request to another host.")
            }

            guard let upstream = response as? HTTPURLResponse else {
                return .error(status: 502, code: "relay_invalid_response", message: "The site did not return an HTTP response.")
            }

            return RelayResponse(
                statusCode: upstream.statusCode,
                headers: Self.responseHeaders(from: upstream),
                body: data
            )
        } catch {
            Logger.restRelay.error("Upstream request failed: \(error.localizedDescription)")
            return .error(status: 502, code: "relay_request_failed", message: error.localizedDescription)
        }
    }

    // MARK: - URLs

    /// The upstream URL a relayed request targets: the relay URL's own path and
    /// query, resolved against the site's API root.
    ///
    /// The path is the whole of the target — there is no client-supplied
    /// upstream URL to validate — so the relay cannot be pointed at another
    /// host by construction. A relay URL carrying an authority
    /// (`gbk-rest://elsewhere/…`) is rejected rather than reinterpreted.
    static func upstreamURL(for relayURL: URL, siteApiRoot: URL) -> URL? {
        let prefix = "\(scheme)://"
        // Work from `absoluteString` rather than `path`/`query`, which
        // percent-decode: the suffix is already encoded exactly as api-fetch
        // built it, and re-encoding it would corrupt values containing `%`.
        guard relayURL.absoluteString.hasPrefix(prefix) else { return nil }
        var suffix = relayURL.absoluteString.dropFirst(prefix.count)
        guard suffix.hasPrefix("/") else { return nil }
        suffix = suffix.dropFirst()

        var root = siteApiRoot.absoluteString
        if !root.hasSuffix("/") {
            root += "/"
        }

        // A site on plain permalinks has an API root that already carries a
        // query (`https://example.com/?rest_route=/`). `createRootURLMiddleware`
        // turns the path's first `?` into `&` for that case, but it cannot here
        // — the root it was given is the relay's, which has no query — so the
        // conversion happens natively instead.
        var path = String(suffix)
        if root.contains("?"), let separator = path.firstIndex(of: "?") {
            path.replaceSubrange(separator...separator, with: "&")
        }

        return URL(string: root + path)
    }

    // MARK: - Headers

    /// Request headers that must not be forwarded upstream.
    ///
    /// `host`/`content-length`/`accept-encoding` are recalculated by URLSession;
    /// `origin` and `referer` would leak the local page context to the server
    /// (and WordPress rejects `file://` origins — the exact problem the relay
    /// exists to solve); `authorization` is replaced by the natively injected
    /// value, so a client-supplied one is discarded; the body marker is
    /// relay-internal.
    private static let requestHeadersToStrip: Set<String> = [
        "host", "content-length", "accept-encoding", "connection",
        "origin", "referer", "authorization",
        bodyMarkerHeader.lowercased(),
    ]

    /// Upstream response headers dropped from relayed responses.
    ///
    /// The CORS strip is load-bearing: WordPress sends an empty
    /// `Access-Control-Allow-Origin` for origins it rejects, which would
    /// override the `*` this relay adds and make WebKit discard the response.
    ///
    /// `Content-Encoding` and `Content-Length` must go because URLSession
    /// already decompressed the body: advertising the upstream encoding would
    /// make WebKit decode the plain bytes a second time, and the upstream
    /// length no longer describes what the handler delivers.
    private static let responseHeadersToStrip: Set<String> = [
        "access-control-allow-origin", "access-control-allow-credentials",
        "access-control-allow-headers", "access-control-allow-methods",
        "access-control-expose-headers", "access-control-max-age", "vary",
        "content-encoding", "content-length", "transfer-encoding", "connection",
    ]

    /// CORS headers added to every relayed response, including errors.
    ///
    /// `Access-Control-Allow-Origin` is load-bearing and effectively must be
    /// `*`: WebKit enforces CORS on a custom scheme's *response* even though it
    /// never preflights the request, and a `file://` document's origin is
    /// `null`, which no named origin matches.
    ///
    /// Without `Access-Control-Expose-Headers` the body is readable while every
    /// response header reads back as null. These four are the only response
    /// headers read anywhere in the editor or in Gutenberg — `Allow` for
    /// `canUser`'s permission checks, the rest for pagination.
    private static let corsHeaders = [
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Expose-Headers": "Allow, Link, X-WP-Total, X-WP-TotalPages",
    ]

    /// The upstream response's headers, less the ones that no longer describe
    /// what the handler delivers, plus the CORS headers the web view needs.
    static func responseHeaders(from upstream: HTTPURLResponse) -> [String: String] {
        var headers = corsHeaders
        for (name, value) in upstream.allHeaderFields {
            guard let name = name as? String, let value = value as? String,
                  !responseHeadersToStrip.contains(name.lowercased()) else {
                continue
            }
            headers[name] = value
        }
        return headers
    }

    /// The CORS headers plus a content type, for responses the relay generates
    /// itself rather than forwards.
    static func responseHeaders(contentType: String) -> [String: String] {
        corsHeaders.merging(["Content-Type": contentType]) { _, new in new }
    }
}

// MARK: - Relay Response

/// The response ``RestRelay`` produces for a relayed request, ready for
/// ``RestSchemeHandler`` to hand to WebKit.
struct RelayResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data

    /// A relay failure, shaped like a WordPress REST error so `api-fetch`
    /// surfaces `message` the same way it does a real one. Emitting
    /// `text/plain` here instead is what makes Jetpack report `invalid_json`.
    static func error(status: Int, code: String, message: String) -> RelayResponse {
        let payload = ["code": code, "message": message]
        let body = (try? JSONSerialization.data(withJSONObject: payload))
            ?? Data(#"{"code":"relay_error","message":"The request could not be relayed."}"#.utf8)
        return RelayResponse(
            statusCode: status,
            headers: RestRelay.responseHeaders(contentType: "application/json"),
            body: body
        )
    }

    /// The response for a request whose body WebKit withheld. Reported as a
    /// server error rather than a client one because nothing about the request
    /// the editor made was wrong.
    static let bodyUnavailable = RelayResponse.error(
        status: 500,
        code: "relay_body_unavailable",
        message: "The editor could not send this file to your site."
    )
}

// MARK: - Redirect Guard

/// Refuses redirects that leave the site's host.
///
/// Without it the containment `RestRelay` gets from resolving every path
/// against the site API root would hold only for the first hop: `URLSession`
/// follows a 3xx on its own, carrying the injected `Authorization` to whatever
/// host the site named and relaying that host's response body back to the
/// editor.
final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {

    /// The site API root redirects are measured against.
    private let apiRoot: URL

    /// The target of the first refused redirect, if any. Written on the session
    /// delegate queue and read only after the task has finished.
    private(set) var refusedRedirectURL: URL?

    init(apiRoot: URL) {
        self.apiRoot = apiRoot
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, isAllowed(url) else {
            if refusedRedirectURL == nil {
                refusedRedirectURL = request.url
            }
            // Stop following. The 3xx itself is returned to `RestRelay`, which
            // reads `refusedRedirectURL` and answers with a real error instead.
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    /// A redirect is allowed only within the site's own host, and never down to
    /// a less secure scheme than the site API root already uses — the two ways
    /// a hop could hand the injected credentials somewhere they weren't meant
    /// to go.
    func isAllowed(_ url: URL) -> Bool {
        guard let allowedHost = apiRoot.host, let host = url.host,
              host.caseInsensitiveCompare(allowedHost) == .orderedSame else {
            return false
        }
        guard let scheme = url.scheme?.lowercased() else { return false }
        if apiRoot.scheme?.lowercased() == "https" {
            return scheme == "https"
        }
        return scheme == "https" || scheme == "http"
    }
}

extension Logger {
    static let restRelay = Logger(subsystem: "GutenbergKit", category: "rest-relay")
}
