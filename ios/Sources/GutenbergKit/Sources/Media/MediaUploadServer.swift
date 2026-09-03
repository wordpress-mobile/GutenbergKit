import Foundation
import GutenbergKitHTTP
import OSLog

/// A local HTTP server that receives file uploads from the WebView and routes
/// them through the native media processing pipeline.
///
/// Built on ``HTTPServer`` from `GutenbergKitHTTP`, which handles TCP binding,
/// HTTP parsing, bearer token authentication, and multipart form-data parsing.
/// The routes it hosts — ``MediaUploadRoute`` and, under Lockdown Mode,
/// ``RestRelay`` — answer the requests; this class owns what they share: the
/// listener, its limits, and the shape of its own refusals.
///
/// Lifecycle is tied to `EditorViewController` — start when the editor loads,
/// stop on deinit.
final class MediaUploadServer: Sendable {

    /// The port the server is listening on.
    let port: UInt16

    /// Per-session auth token for validating incoming requests.
    let token: String

    private let server: HTTPServer

    /// The upload route's startup sweep of crash-orphaned temp files.
    /// Exposed so tests can await completion.
    let cleanupTask: Task<Void, Never>

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

    /// Creates and starts a new upload server.
    ///
    /// - Parameters:
    ///   - uploadDelegate: Optional delegate for customizing file processing and upload.
    ///   - defaultUploader: Fallback uploader used when no delegate provides `uploadFile`.
    ///   - restRelay: Optional ``RestRelay``. When present, this server also
    ///     answers the relay's route, becoming the transport for every REST
    ///     request the editor makes under iOS Lockdown Mode — which is what
    ///     `GBKit.networkProxy` advertises to the web view. When `nil`, the
    ///     server serves only the upload route and the editor calls the site
    ///     directly.
    ///   - maxRequestBodySize: The maximum allowed request body size in bytes.
    ///     Requests exceeding this limit receive a 413 response. Defaults to 4 GB.
    static func start(
        uploadDelegate: (any MediaUploadDelegate)? = nil,
        defaultUploader: DefaultMediaUploader? = nil,
        restRelay: RestRelay? = nil,
        maxRequestBodySize: Int64 = HTTPRequestParser.defaultMaxBodySize
    ) async throws -> MediaUploadServer {
        let uploadRoute = MediaUploadRoute(uploadDelegate: uploadDelegate, defaultUploader: defaultUploader)

        // Checked in order: the relay's `/proxy/…` prefix ahead of the upload
        // route's exact path.
        let routes: [any LocalServerRoute] = restRelay.map { [$0, uploadRoute] } ?? [uploadRoute]

        // A generous ceiling for receiving the upload body. The body read is
        // primarily bounded by the per-read idle timeout (which reaps a stalled
        // connection in seconds); this absolute backstop ensures a slow-but-steady
        // client can't hold a connection slot indefinitely. Ten minutes is far
        // beyond any realistic media upload over loopback while still bounding a
        // wedged one.
        let bodyReadTimeout: Duration = .seconds(600)

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

        return MediaUploadServer(server: server, cleanupTask: uploadRoute.cleanupTask)
    }

    private init(server: HTTPServer, cleanupTask: Task<Void, Never>) {
        self.server = server
        self.port = server.port
        self.token = server.token
        self.cleanupTask = cleanupTask
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
            return MediaUploadServer.errorResponse(status: error.httpStatus, message: message)
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
