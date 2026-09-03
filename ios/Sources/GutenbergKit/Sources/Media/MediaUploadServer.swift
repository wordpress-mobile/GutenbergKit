import Foundation
import GutenbergKitHTTP
import OSLog

/// A local HTTP server that receives file uploads from the WebView and routes
/// them through the native media processing pipeline.
///
/// Built on ``HTTPServer`` from `GutenbergKitHTTP`, which handles TCP binding,
/// HTTP parsing, bearer token authentication, and multipart form-data parsing.
/// This class provides the upload-specific handler: receiving a file, delegating
/// to the host app for processing/upload, and returning the result as JSON.
///
/// Lifecycle is tied to `EditorViewController` — start when the editor loads,
/// stop on deinit.
final class MediaUploadServer: Sendable {

    /// The port the server is listening on.
    let port: UInt16

    /// Per-session auth token for validating incoming requests.
    let token: String

    private let server: HTTPServer

    /// Sweeps crash-orphaned upload temp files off the editor-startup path.
    /// Exposed so tests can await completion. (Mirrors Android's `cleanupJob`.)
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
        // Sweep temp files orphaned by a prior crash, off the editor-startup
        // path — the sweep only deletes stale files (>1 hour old), so it cannot
        // race this server's own in-flight uploads and nothing below depends on it.
        let cleanupTask = Task.detached(priority: .utility) {
            cleanOrphanedUploads()
        }

        let context = UploadContext(uploadDelegate: uploadDelegate, defaultUploader: defaultUploader, restRelay: restRelay)

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
                await Self.handleRequest(request, context: context)
            }
        )

        return MediaUploadServer(server: server, cleanupTask: cleanupTask)
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

    private static func handleRequest(_ request: HTTPServer.Request, context: UploadContext) async -> HTTPResponse {
        let parsed = request.parsed

        // REST relay route: `/proxy/…` requests are forwarded to the site's REST
        // API (Lockdown Mode support), the path after the route resolving
        // against the site API root.
        if let restRelay = context.restRelay, RestRelay.handles(parsed) {
            return await restRelay.handle(request)
        }

        // Route: only POST /upload is handled. (OPTIONS preflight is answered by
        // the HTTP library under its permissive CORS policy.) Match on the path
        // alone — the target carries a query string (e.g. `?_embed`) that the
        // upload handler relays on to WordPress.
        guard parsed.method.uppercased() == "POST", parsed.path == "/upload" else {
            return errorResponse(status: 404, message: "Not found")
        }

        return await handleUpload(request, context: context)
    }

    private static func handleUpload(_ request: HTTPServer.Request, context: UploadContext) async -> HTTPResponse {
        let parts: [MultipartPart]
        do {
            parts = try request.parsed.multipartParts()
        } catch {
            Logger.uploadServer.error("Multipart parse failed: \(error)")
            return errorResponse(status: 400, message: "Expected multipart/form-data")
        }

        // Find the file part (the first part with a filename).
        guard let filePart = parts.first(where: { $0.filename != nil }) else {
            return errorResponse(status: 400, message: "No file found in request")
        }

        // The non-file parts (post, additionalData) and the original query
        // (e.g. ?_embed) must reach WordPress too — relay them alongside the file.
        let extraParts = parts.filter { $0.filename == nil }
        let query = request.parsed.query

        let filename = filePart.filename ?? "upload"
        let mimeType = filePart.contentType

        // Ask the delegate — from metadata alone — whether it will touch a file
        // like this. If not, forward the original upload to WordPress directly,
        // skipping a full temp-file copy of a file the delegate won't process or
        // upload (e.g. a video handed to an image-only delegate).
        guard context.uploadDelegate?.handlesFile(ofType: mimeType, named: filename) ?? false else {
            do {
                return try await passthroughResponse(request, query: query, context: context)
            } catch {
                return uploadErrorResponse(error)
            }
        }

        // The delegate wants the file. Stream the part body to a dedicated temp
        // file for it — the library's RequestBody may be a byte-range slice of a
        // larger temp file whose lifecycle is tied to ARC, so the delegate needs a
        // standalone file that outlives the handler return.
        let tempDir = uploadsTempDirectory
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let fileURL = tempDir.appending(component: "\(UUID().uuidString)-\(sanitizeFilename(filename))")
        do {
            let inputStream = try filePart.body.makeInputStream()
            try writeStream(inputStream, to: fileURL)
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            Logger.uploadServer.error("Failed to write upload to disk: \(error)")
            return errorResponse(status: 500, message: "Failed to save file")
        }

        // From here on always clean up the original temp file. The processed
        // file (if the delegate produced a new one) is cleaned up inside
        // processAndUpload so its throw paths are covered too.
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            let uploadResult = try await processAndUpload(
                fileURL: fileURL, mimeType: mimeType, filename: filename,
                extraParts: extraParts, query: query, context: context
            )
            switch uploadResult {
            case .uploaded(let uploaded):
                Logger.uploadServer.debug("Uploaded file to WordPress")
                return relayResponse(uploaded)
            case .passthrough:
                // Delegate didn't modify the file — forward the original request
                // body to WordPress without re-encoding.
                return try await passthroughResponse(request, query: query, context: context)
            }
        } catch {
            return uploadErrorResponse(error)
        }
    }

    /// Forwards the original request body to WordPress unchanged (no multipart
    /// re-encoding) and relays the response. Used when the delegate won't touch
    /// the file — it declined by metadata (`handlesFile` returned false) or
    /// `processFile` returned `.original`.
    private static func passthroughResponse(
        _ request: HTTPServer.Request, query: String, context: UploadContext
    ) async throws -> HTTPResponse {
        Logger.uploadServer.debug("Passthrough: forwarding original request body to WordPress")
        guard let body = request.parsed.body,
              let contentType = request.parsed.header("Content-Type"),
              let defaultUploader = context.defaultUploader else {
            return errorResponse(status: 500, message: UploadError.noUploader.localizedDescription)
        }
        let response = try await defaultUploader.passthroughUpload(body: body, contentType: contentType, query: query)
        return relayResponse(response)
    }

    /// Relays WordPress's exact status and body to the editor so it sees the same
    /// attachment object (or error) as a direct upload.
    private static func relayResponse(_ response: MediaUploadResponse) -> HTTPResponse {
        HTTPResponse(
            status: response.statusCode,
            headers: [("Content-Type", "application/json")],
            body: response.body
        )
    }

    /// Builds the 500 response for a failed upload. A cancelled connection task
    /// (editor abort / server stop) surfaces here too — as CancellationError or
    /// URLError.cancelled — but isn't a failure and the server closes the
    /// connection without sending this response (see HTTPServer's cancellation
    /// check), so log that quietly.
    private static func uploadErrorResponse(_ error: any Error) -> HTTPResponse {
        if Task.isCancelled {
            Logger.uploadServer.debug("Upload cancelled")
        } else {
            Logger.uploadServer.error("Upload processing failed: \(error)")
        }
        return errorResponse(status: 500, message: error.localizedDescription)
    }

    // MARK: - Delegate Pipeline

    /// Result of the delegate processing + upload pipeline.
    private enum UploadResult {
        /// The delegate (or default uploader) completed the upload; carries the
        /// raw WordPress response to relay.
        case uploaded(MediaUploadResponse)
        /// The delegate didn't modify the file and `uploadFile` returned nil.
        /// The caller should forward the original request body to WordPress.
        case passthrough
    }

    private static func processAndUpload(
        fileURL: URL, mimeType: String, filename: String,
        extraParts: [MultipartPart], query: String, context: UploadContext
    ) async throws -> UploadResult {
        // Step 1: Process (resize, transcode, etc.)
        let processed: ProcessedProxyFile
        if let delegate = context.uploadDelegate {
            processed = try await delegate.processFile(at: fileURL, mimeType: mimeType, filename: filename)
        } else {
            processed = .original
        }

        // Resolve the file to upload and its metadata. `.processed` uses the
        // delegate's values verbatim, so a format change is reported to WordPress.
        let uploadURL: URL
        let uploadMimeType: String
        let uploadFilename: String
        switch processed {
        case .original:
            uploadURL = fileURL
            uploadMimeType = mimeType
            uploadFilename = filename
        case let .processed(url, processedMimeType, processedFilename):
            uploadURL = url
            uploadMimeType = processedMimeType
            uploadFilename = processedFilename
        }

        // The processed file (if the delegate produced a new one) is ours to
        // clean up — on success it has been uploaded, on failure it is abandoned.
        // Cleaning up here rather than in the caller covers the throw paths too.
        defer {
            if uploadURL != fileURL {
                try? FileManager.default.removeItem(at: uploadURL)
            }
        }

        // Step 2: Upload to remote WordPress
        if let delegate = context.uploadDelegate,
           let result = try await delegate.uploadFile(at: uploadURL, mimeType: uploadMimeType, filename: uploadFilename) {
            return .uploaded(result)
        } else if let defaultUploader = context.defaultUploader {
            // Unmodified — forward the original request body directly, skipping
            // multipart re-encoding.
            if case .original = processed {
                return .passthrough
            }
            let result = try await defaultUploader.upload(fileURL: uploadURL, mimeType: uploadMimeType, filename: uploadFilename, extraParts: extraParts, query: query)
            return .uploaded(result)
        } else {
            throw UploadError.noUploader
        }
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

    // MARK: - Helpers

    /// Directory for staging uploaded files, under the system temp dir.
    private static var uploadsTempDirectory: URL {
        FileManager.default.temporaryDirectory
            .appending(component: "GutenbergKit-uploads", directoryHint: .isDirectory)
    }

    /// Deletes upload temp files left behind by a prior crash. Files still in
    /// flight (only seconds old) are preserved by the age threshold, so this is
    /// safe even if another editor instance is mid-upload.
    private static func cleanOrphanedUploads() {
        let cutoff = Date(timeIntervalSinceNow: -3600) // 1 hour ago
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: uploadsTempDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Sanitizes a filename to prevent path traversal.
    private static func sanitizeFilename(_ name: String) -> String {
        let safe = (name as NSString).lastPathComponent
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "\\", with: "")
        return safe.isEmpty ? "upload" : safe
    }

    /// Streams an InputStream to a file URL.
    private static func writeStream(_ inputStream: InputStream, to url: URL) throws {
        inputStream.open()
        defer { inputStream.close() }

        // `OutputStream(url:append:)` returns nil if the file can't be opened for
        // writing (e.g. the uploads directory was removed after it was created, or
        // a permissions/sandbox failure). Throw rather than force-unwrap so the
        // caller returns a clean 500 instead of trapping the process.
        guard let outputStream = OutputStream(url: url, append: false) else {
            throw UploadError.streamWriteFailed
        }
        outputStream.open()
        defer { outputStream.close() }

        let bufferSize = 65_536
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        // Use read() return value as the sole termination signal. Do NOT check
        // hasBytesAvailable — for piped streams (used by file-slice RequestBody),
        // it can return false before the writer thread has pumped the next chunk,
        // causing an early exit and a truncated file.
        while true {
            let bytesRead = inputStream.read(buffer, maxLength: bufferSize)
            if bytesRead < 0 {
                throw inputStream.streamError ?? UploadError.streamReadFailed
            }
            if bytesRead == 0 { break }

            var totalWritten = 0
            while totalWritten < bytesRead {
                let written = outputStream.write(buffer.advanced(by: totalWritten), maxLength: bytesRead - totalWritten)
                if written < 0 {
                    throw outputStream.streamError ?? UploadError.streamWriteFailed
                }
                totalWritten += written
            }
        }
    }
}

// MARK: - Errors

/// Errors from the native media upload pipeline.
enum UploadError: Error, LocalizedError {
    case noUploader
    case streamReadFailed
    case streamWriteFailed

    var errorDescription: String? {
        switch self {
        case .noUploader: "No upload delegate or default uploader configured"
        case .streamReadFailed: "Failed to read upload stream"
        case .streamWriteFailed: "Failed to write upload to disk"
        }
    }
}

// MARK: - Upload Context

/// Container for the upload delegate, default uploader, and REST relay,
/// captured by the HTTPServer handler closure and re-read on each request.
///
/// The delegate is held **weakly**. `EditorViewController.mediaUploadDelegate` is
/// declared `weak` — the host owns the delegate's lifetime. Capturing it strongly
/// here would silently defeat that contract and, worse, risk a retain cycle
/// (`EditorViewController → uploadServer → HTTPServer → handler → UploadContext →
/// delegate → EditorViewController`) that would keep the view controller — and
/// therefore the server — alive forever, so `deinit` would never stop it.
///
/// `@unchecked Sendable`: `uploadDelegate` is assigned once at init and only read
/// afterwards; weak-reference reads are thread-safe at runtime.
private final class UploadContext: @unchecked Sendable {
    weak var uploadDelegate: (any MediaUploadDelegate)?
    let defaultUploader: DefaultMediaUploader?
    let restRelay: RestRelay?

    init(uploadDelegate: (any MediaUploadDelegate)?, defaultUploader: DefaultMediaUploader?, restRelay: RestRelay?) {
        self.uploadDelegate = uploadDelegate
        self.defaultUploader = defaultUploader
        self.restRelay = restRelay
    }
}
