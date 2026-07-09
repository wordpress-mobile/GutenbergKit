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
/// - Forwarding is restricted to URLs under the configured site API root,
///   so the relay cannot be used to reach arbitrary hosts.
/// - The upstream `Authorization` header is injected natively from the editor
///   configuration; any client-supplied value is discarded.
struct RestRelay: Sendable {

    /// Query parameter carrying the absolute upstream URL to forward to.
    ///
    /// The URL rides in the query string rather than a custom header so the
    /// HTTP library's permissive CORS policy (which enumerates allowed
    /// headers) covers the preflight without additions.
    static let upstreamURLQueryItem = "url"

    /// The URL prefix (the site's API root) that forwarded requests must match.
    private let allowedPrefix: String

    /// The authorization header injected into upstream requests.
    private let authHeader: String

    private let session: URLSession

    init(configuration: EditorConfiguration) {
        var prefix = configuration.siteApiRoot.absoluteString
        if !prefix.hasSuffix("/") {
            prefix += "/"
        }
        self.allowedPrefix = prefix
        self.authHeader = configuration.authHeader

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = 120
        sessionConfiguration.httpCookieStorage = nil
        self.session = URLSession(configuration: sessionConfiguration)
    }

    /// Forwards a relayed request to the site's REST API and returns the
    /// upstream response with permissive CORS headers.
    func handle(_ request: HTTPServer.Request) async -> HTTPResponse {
        let parsed = request.parsed

        guard let upstreamURL = Self.upstreamURL(from: parsed.query) else {
            return Self.errorResponse(status: 400, body: "Missing or invalid `\(Self.upstreamURLQueryItem)` query parameter")
        }

        // SSRF guard: only forward to the configured site API root.
        guard upstreamURL.absoluteString.hasPrefix(allowedPrefix) else {
            Logger.restRelay.error("Refusing to relay request outside the site API root")
            return Self.errorResponse(status: 403, body: "Upstream URL is outside the allowed API root")
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
                do {
                    upstreamRequest.httpBodyStream = try body.makeInputStream()
                    upstreamRequest.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")
                } catch {
                    Logger.restRelay.error("Failed to open request body stream: \(error)")
                    return Self.errorResponse(status: 500, body: "Failed to read request body")
                }
            }
        }

        do {
            let upstream = HTTPResponse(try await session.data(for: upstreamRequest))
            return HTTPResponse(
                status: upstream.status,
                statusText: upstream.statusText,
                headers: Self.merge(upstream.headers, adding: Self.corsHeaders),
                body: upstream.body
            )
        } catch {
            Logger.restRelay.error("Upstream request failed: \(error.localizedDescription)")
            return Self.errorResponse(status: 502, body: "Upstream request failed: \(error.localizedDescription)")
        }
    }

    // MARK: - CORS

    /// Response headers added to every relayed response. The library's
    /// permissive CORS policy stamps `Access-Control-Allow-Origin` and friends;
    /// the exposed headers keep paginated REST responses readable to
    /// `api-fetch` callers.
    private static let corsHeaders: [(String, String)] = [
        ("Access-Control-Expose-Headers", "X-WP-Total, X-WP-TotalPages, Link"),
    ]

    /// Request headers that must not be forwarded upstream.
    ///
    /// `host`/`content-length`/`accept-encoding` are recalculated by URLSession;
    /// `origin` and `referer` would leak the local page context to the server
    /// (and WordPress rejects `file://` origins — the exact problem the relay
    /// exists to solve); the rest are relay-internal.
    private static let requestHeadersToStrip: Set<String> = [
        "host", "content-length", "accept-encoding", "connection",
        "origin", "referer",
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

    /// Extracts the upstream URL from the relay request's query string.
    private static func upstreamURL(from query: String) -> URL? {
        var components = URLComponents()
        components.percentEncodedQuery = query
        guard let value = components.queryItems?.first(where: { $0.name == upstreamURLQueryItem })?.value,
              let url = URL(string: value) else {
            return nil
        }
        return url
    }

    private static func errorResponse(status: Int, body: String) -> HTTPResponse {
        HTTPResponse(
            status: status,
            headers: corsHeaders + [("Content-Type", "text/plain")],
            body: Data(body.utf8)
        )
    }
}

extension Logger {
    static let restRelay = Logger(subsystem: "GutenbergKit", category: "rest-relay")
}

#endif // canImport(Network)
