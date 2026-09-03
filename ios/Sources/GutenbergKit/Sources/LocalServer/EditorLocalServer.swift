import Foundation
import GutenbergKitHTTP
import OSLog

/// The editor's local HTTP server: the loopback endpoint the web view reaches
/// for whatever the native side answers on the page's behalf.
///
/// Built on ``HTTPServer`` from `GutenbergKitHTTP`, which handles TCP binding,
/// HTTP parsing, bearer token authentication, and multipart form-data parsing.
/// The routes it hosts — ``MediaUploadRoute`` and, under Lockdown Mode,
/// ``RestRelay`` — answer the requests; this class owns what they share: the
/// listener, its limits, and the shape of its own refusals.
///
/// Lifecycle is tied to `EditorViewController` — start when the editor loads,
/// stop on deinit.
final class EditorLocalServer: Sendable {

    /// The port the server is listening on.
    let port: UInt16

    /// Per-session auth token for validating incoming requests.
    let token: String

    private let server: HTTPServer
    private let routes: [any LocalServerRoute]

    /// The concurrent connection ceiling for the local server.
    ///
    /// The library's default of 5 suits a server that only ever receives one
    /// upload at a time. This one also carries every REST request the editor
    /// makes under Lockdown Mode (see ``RestRelay``), and editor boot fans out
    /// well past five: each connection serves exactly one request
    /// (`Connection: close`), and a connection past the limit is closed
    /// immediately, surfacing in JavaScript as an unretried `fetch_error`.
    /// WebKit caps its own concurrency per host well below this, so the ceiling
    /// exists to bound a runaway, not to schedule normal traffic.
    static let maxConnections = 32

    /// Creates and starts a new server.
    ///
    /// - Parameters:
    ///   - routes: The routes to serve, checked in this order. A request no
    ///     route claims is answered 404.
    ///   - maxRequestBodySize: The maximum allowed request body size in bytes.
    ///     Requests exceeding this limit receive a 413 response. Defaults to
    ///     4 GB, and applies to every route: under Lockdown Mode the relay
    ///     carries the editor's media uploads too.
    static func start(
        routes: [any LocalServerRoute],
        maxRequestBodySize: Int64 = HTTPRequestParser.defaultMaxBodySize
    ) async throws -> EditorLocalServer {
        // A generous ceiling for receiving the upload body. The body read is
        // primarily bounded by the per-read idle timeout (which reaps a stalled
        // connection in seconds); this absolute backstop ensures a slow-but-steady
        // client can't hold a connection slot indefinitely. Ten minutes is far
        // beyond any realistic media upload over loopback while still bounding a
        // wedged one.
        let bodyReadTimeout: Duration = .seconds(600)

        // The name scopes the library's temp directory and its orphan sweep.
        // It predates the server hosting anything but uploads and is kept so
        // an upgrade does not strand the directory it was already using.
        let server = try await HTTPServer.start(
            name: "media-upload",
            requiresAuthentication: true,
            // The editor web view is this server's only legitimate client, and
            // every request it makes carries these headers.
            requiresBrowserOrigin: true,
            maxRequestBodySize: maxRequestBodySize,
            maxConnections: maxConnections,
            bodyReadTimeout: bodyReadTimeout,
            cors: .permissive,
            delegate: ServerDelegate(),
            handler: { request in
                await Self.handleRequest(request, routes: routes)
            }
        )

        return EditorLocalServer(server: server, routes: routes)
    }

    private init(server: HTTPServer, routes: [any LocalServerRoute]) {
        self.server = server
        self.routes = routes
        self.port = server.port
        self.token = server.token
    }

    /// Whether a route of type `R` is registered — what decides whether the
    /// port and token are advertised to the web view for that route's use.
    func hosts<R: LocalServerRoute>(_ route: R.Type) -> Bool {
        routes.contains { $0 is R }
    }

    /// Stops the server and releases resources.
    func stop() {
        server.stop()
    }

    // MARK: - Request Handling

    /// Hands the request to the first route that claims it.
    private static func handleRequest(_ request: HTTPServer.Request, routes: [any LocalServerRoute]) async -> HTTPResponse {
        for route in routes where route.handles(request.parsed) {
            return await route.handle(request)
        }
        return errorResponse(status: 404, message: "Not found")
    }

    private static func errorResponse(status: Int, message: String) -> HTTPResponse {
        .wordPressError(status: status, code: "upload_error", message: message)
    }

    /// Answers the errors the HTTP server raises itself with the same JSON
    /// `{code, message}` shape the editor expects, so the middleware surfaces a
    /// real message instead of a generic parse failure.
    ///
    /// Every response on this server reaches `@wordpress/api-fetch`, which parses
    /// all of them as JSON: a `text/plain` refusal arrives as `invalid_json`
    /// ("The response is not a valid JSON response."), losing the reason. Under
    /// the relay that covers every REST request the editor makes, so these are
    /// the failures a user actually sees.
    ///
    /// A leaf object — the HTTP server retains it.
    private final class ServerDelegate: HTTPServerDelegate {
        func response(forRecoverableParseError error: HTTPRequestParseError) -> HTTPResponse {
            let message: String = switch error {
            case .payloadTooLarge: "The file is too large to upload in the editor."
            default: "\(error.httpStatusText)"
            }
            return EditorLocalServer.errorResponse(status: error.httpStatus, message: message)
        }

        func errorBody(for error: HTTPServerError) -> HTTPErrorBody? {
            let (code, message): (String, String) = switch error {
            case .authenticationFailed:
                ("server_unauthorized", "The editor's credential for the local server was missing or stale.")
            case .forbiddenOrigin:
                ("server_forbidden_origin", "The local server accepts requests from the editor only.")
            case .lengthRequired:
                ("server_length_required", "The request did not declare its content length.")
            case .unexpectedBody:
                ("server_unexpected_body", "A preflight request carried a body.")
            case .readTimeout:
                ("server_timeout", "The local server timed out before the request finished arriving.")
            default:
                ("server_error", error.localizedDescription)
            }
            return .wordPressError(code: code, message: message)
        }
    }
}
