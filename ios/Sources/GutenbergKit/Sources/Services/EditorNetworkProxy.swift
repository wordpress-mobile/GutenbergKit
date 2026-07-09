#if canImport(Network)

import Foundation
import OSLog
import GutenbergKitHTTP

/// A loopback HTTP proxy that relays editor REST API requests through the
/// native networking stack.
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
/// The proxy sidesteps the problem: the web view fetches `127.0.0.1` and this
/// server forwards the request to the site's REST API with the configured
/// authorization header, echoing the page's `Origin` in the CORS response
/// headers it controls. WebKit accepts an echoed `file://` origin.
///
/// ## Security
///
/// - The underlying ``HTTPServer`` binds to `127.0.0.1` only and requires a
///   random per-session bearer token (`Relay-Authorization`) on every
///   non-preflight request.
/// - Forwarding is restricted to URLs under the configured site API root,
///   so the proxy cannot be used to reach arbitrary hosts.
/// - The upstream `Authorization` header is injected natively from the editor
///   configuration; any client-supplied value is discarded.
@MainActor
final class EditorNetworkProxy {

    /// Connection details the web view needs to route requests through the proxy.
    struct Info: Sendable {
        let port: UInt16
        let token: String
    }

    /// Header carrying the absolute upstream URL to forward the request to.
    static let upstreamURLHeader = "X-GBK-Upstream-URL"

    private var server: HTTPServer?

    private(set) var info: Info?

    /// Starts the proxy for the given configuration.
    ///
    /// - Returns: The connection info to expose to the web view.
    @discardableResult
    func start(configuration: EditorConfiguration) async throws -> Info {
        if let info {
            return info
        }

        let allowedPrefix = Self.normalizedPrefix(configuration.siteApiRoot)
        let authHeader = configuration.authHeader
        let session = Self.makeSession()

        let server = try await HTTPServer.start(
            name: "editor-network-proxy",
            handler: { request in
                await Self.handle(
                    request,
                    allowedPrefix: allowedPrefix,
                    authHeader: authHeader,
                    session: session
                )
            }
        )

        let info = Info(port: server.port, token: server.token)
        self.server = server
        self.info = info
        Logger.networkProxy.info("Editor network proxy listening on 127.0.0.1:\(info.port)")
        return info
    }

    func stop() {
        server?.stop()
        server = nil
        info = nil
    }

    deinit {
        server?.stop()
    }

    // MARK: - Request Handling

    private static func handle(
        _ request: HTTPServer.Request,
        allowedPrefix: String,
        authHeader: String,
        session: URLSession
    ) async -> HTTPResponse {
        let parsed = request.parsed
        let corsHeaders = Self.corsHeaders(for: parsed)

        // CORS preflight: the Relay-Authorization and upstream-URL headers make
        // every proxied request non-simple, so preflights are guaranteed.
        if parsed.method.uppercased() == "OPTIONS" {
            return HTTPResponse(status: 204, headers: corsHeaders, body: Data())
        }

        guard let upstreamString = parsed.header(upstreamURLHeader),
              let upstreamURL = URL(string: upstreamString) else {
            return HTTPResponse(
                status: 400,
                headers: corsHeaders + [("Content-Type", "text/plain")],
                body: Data("Missing or invalid \(upstreamURLHeader) header".utf8)
            )
        }

        // SSRF guard: only forward to the configured site API root.
        guard upstreamURL.absoluteString.hasPrefix(allowedPrefix) else {
            Logger.networkProxy.error("Refusing to proxy request outside the site API root")
            return HTTPResponse(
                status: 403,
                headers: corsHeaders + [("Content-Type", "text/plain")],
                body: Data("Upstream URL is outside the allowed API root".utf8)
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
                do {
                    upstreamRequest.httpBodyStream = try body.makeInputStream()
                    upstreamRequest.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")
                } catch {
                    Logger.networkProxy.error("Failed to open request body stream: \(error)")
                    return HTTPResponse(
                        status: 500,
                        headers: corsHeaders + [("Content-Type", "text/plain")],
                        body: Data("Failed to read request body".utf8)
                    )
                }
            }
        }

        do {
            let upstream = HTTPResponse(try await session.data(for: upstreamRequest))
            return HTTPResponse(
                status: upstream.status,
                statusText: upstream.statusText,
                headers: Self.merge(upstream.headers, adding: corsHeaders),
                body: upstream.body
            )
        } catch {
            Logger.networkProxy.error("Upstream request failed: \(error.localizedDescription)")
            return HTTPResponse(
                status: 502,
                statusText: "Bad Gateway",
                headers: corsHeaders + [("Content-Type", "text/plain")],
                body: Data("Upstream request failed: \(error.localizedDescription)".utf8)
            )
        }
    }

    // MARK: - CORS

    /// Builds the CORS headers for a proxied response.
    ///
    /// The page's `Origin` is echoed verbatim: under Lockdown Mode the editor
    /// page sends the non-standard `Origin: file://`, which WebKit accepts as
    /// long as the response echoes it exactly.
    private static func corsHeaders(for request: ParsedHTTPRequest) -> [(String, String)] {
        var headers: [(String, String)] = [
            ("Access-Control-Allow-Origin", request.header("Origin") ?? "*"),
            ("Vary", "Origin"),
            ("Access-Control-Expose-Headers", "X-WP-Total, X-WP-TotalPages, Link"),
        ]
        if request.parsedMethodIsOptions {
            headers.append(("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS"))
            let requestedHeaders = request.header("Access-Control-Request-Headers")
                ?? "Relay-Authorization, \(upstreamURLHeader), Authorization, Content-Type, Content-Disposition, X-WP-Nonce"
            headers.append(("Access-Control-Allow-Headers", requestedHeaders))
            headers.append(("Access-Control-Max-Age", "600"))
        }
        return headers
    }

    /// Request headers that must not be forwarded upstream.
    ///
    /// `host`/`content-length`/`accept-encoding` are recalculated by URLSession;
    /// `origin` and `referer` would leak the local page context to the server
    /// (and WordPress rejects `file://` origins — the exact problem this proxy
    /// exists to solve); the rest are proxy-internal.
    private static let requestHeadersToStrip: Set<String> = [
        "host", "content-length", "accept-encoding", "connection",
        "origin", "referer",
        "authorization", "relay-authorization", "proxy-authorization",
        upstreamURLHeader.lowercased(),
    ]

    /// Appends CORS headers to upstream headers, dropping any CORS headers the
    /// upstream may have sent so the echoed values win.
    private static func merge(
        _ upstream: [(String, String)],
        adding cors: [(String, String)]
    ) -> [(String, String)] {
        let corsNames = Set(cors.map { $0.0.lowercased() })
        return upstream.filter { !corsNames.contains($0.0.lowercased()) } + cors
    }

    private static func normalizedPrefix(_ url: URL) -> String {
        var prefix = url.absoluteString
        if !prefix.hasSuffix("/") {
            prefix += "/"
        }
        return prefix
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }
}

private extension ParsedHTTPRequest {
    var parsedMethodIsOptions: Bool {
        method.uppercased() == "OPTIONS"
    }
}

extension Logger {
    static let networkProxy = Logger(subsystem: "GutenbergKit", category: "network-proxy")
}

#endif // canImport(Network)
