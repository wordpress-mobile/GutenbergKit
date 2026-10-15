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

    /// Creates and starts a new upload server.
    ///
    /// - Parameters:
    ///   - processor: Optional processor that transforms the file before delivery.
    ///   - uploader: Optional host uploader that performs the upload on its own stack.
    ///   - internalClient: GutenbergKit's own client for the configured site. Delivers
    ///     uploads when no host uploader does, and every media delete.
    ///   - maxRequestBodySize: The maximum allowed request body size in bytes.
    ///     Requests exceeding this limit receive a 413 response. Defaults to 4 GB.
    static func start(
        processor: (any MediaProcessor)? = nil,
        uploader: (any MediaUploader)? = nil,
        internalClient: InternalMediaClient? = nil,
        maxRequestBodySize: Int64 = HTTPRequestParser.defaultMaxBodySize
    ) async throws -> MediaUploadServer {
        // Sweep temp files orphaned by a prior crash, off the editor-startup
        // path — the sweep only deletes stale files (>1 hour old), so it cannot
        // race this server's own in-flight uploads and nothing below depends on it.
        let cleanupTask = Task.detached(priority: .utility) {
            cleanOrphanedUploads()
        }

        let handler = Handler(processor: processor, uploader: uploader, internalClient: internalClient)

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
            maxRequestBodySize: maxRequestBodySize,
            bodyReadTimeout: bodyReadTimeout,
            cors: .permissive,
            delegate: ServerDelegate(),
            handler: handler
        )

        let uploadServer = MediaUploadServer(server: server, cleanupTask: cleanupTask)
        #if DEBUG
        countServerStarted(processor: processor, uploader: uploader)
        #endif
        return uploadServer
    }

#if DEBUG
    // MARK: - Leak Census (DEBUG)

    /// Counts live servers so a host that leaks editors finds out in its own debug build.
    ///
    /// Every live server is a bound loopback `NWListener`. There is one per editor and the
    /// editor stops it on `deinit`, so returning to zero is the normal outcome — monotone
    /// growth is the ownership cycle described on
    /// ``EditorViewController/stopMediaHandling()``. Nothing else produces it:
    /// `EditorViewController.warmup()` passes neither handler, so it never starts a server.
    ///
    /// This population is the only detectable symptom of that cycle. A `deinit` assertion
    /// on the editor cannot work — a cycle is precisely what stops `deinit` from running —
    /// and no UIKit callback distinguishes teardown from being covered or re-parented.
    ///
    /// Logged, never fatal. The threshold is a heuristic, and crashing a host's debug
    /// build over a heuristic is a worse trade than the leak it reports.
    private static let censusLock = NSLock()
    // Guarded by `censusLock` on every access.
    nonisolated(unsafe) private static var liveServerCount = 0

    /// Live servers tolerated before the count reads as a leak. Two editors can briefly
    /// overlap across a push or a modal transition; four is not a shape hosts produce.
    private static let liveServerLeakThreshold = 4

    private static func countServerStarted(
        processor: (any MediaProcessor)?,
        uploader: (any MediaUploader)?
    ) {
        let count = censusLock.withLock {
            liveServerCount += 1
            return liveServerCount
        }

        guard count >= liveServerLeakThreshold else { return }

        // Name every handler that was supplied, not just the first. With both set the
        // retainer is as likely to be the uploader, and naming only the processor sends
        // the reader to audit an object that may be a value type holding nothing at all.
        let names = [processor.map { String(describing: type(of: $0)) },
                     uploader.map { String(describing: type(of: $0)) }].compactMap { $0 }
        let name = names.isEmpty ? "the host's media handler" : names.joined(separator: ", ")
        Logger.uploadServer.fault(
            """
            \(count, privacy: .public) media upload servers are live, one bound loopback \
            listener each. Editors are leaking: a host that both owns EditorViewController \
            and is one of its own media handlers (\(name, privacy: .public)) forms a retain \
            cycle ARC cannot break, so the editor's deinit never runs. Call \
            EditorViewController.stopMediaHandling() when you are done with the editor, or \
            keep the handler a leaf object that doesn't reference the editor.
            """
        )
    }

    deinit {
        Self.censusLock.withLock { Self.liveServerCount -= 1 }
    }
#endif

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

    /// Serves the upload server's requests.
    ///
    /// A `struct` rather than a closure over a context object: the dependencies become
    /// stored properties and the request logic becomes instance methods, instead of
    /// statics threading a context parameter through every call. It stores no reference
    /// back to the `MediaUploadServer`, so it can't close the
    /// `MediaUploadServer -> HTTPServer -> handler -> MediaUploadServer` loop that
    /// would keep `deinit` — and therefore `stop()` — from ever running. Being a value
    /// type is not what buys that: a `struct` storing the server would close the loop
    /// just the same, which is why the statics above stay static.
    ///
    /// Everything here is held **strongly**, so a processor that admitted a file for
    /// processing will process it, and an upload gated on a host uploader will be
    /// delivered by it — the reads within a request can't disagree, and an in-flight
    /// upload keeps the host's handlers alive until it unwinds. This matches Android,
    /// which holds its `processor`/`uploader` as plain `val`s for the same reason.
    ///
    /// Strong is safe because `EditorViewController` owns `mediaProcessor` and
    /// `mediaUploader` strongly too. A host object that retains the view controller
    /// back already forms `EditorViewController -> mediaUploader ->
    /// EditorViewController`, a cycle this handler can neither create nor prevent.
    ///
    /// Implicitly `Sendable`: `MediaProcessor` and `MediaUploader` are `Sendable`
    /// protocols and `InternalMediaClient` is `@unchecked Sendable`.
    private struct Handler: HTTPRequestHandler {
        let processor: (any MediaProcessor)?
        let uploader: (any MediaUploader)?
        let internalClient: InternalMediaClient?

        func handle(_ request: HTTPServer.Request) async -> HTTPResponse {
            let parsed = request.parsed

            // Routes: POST /upload, and DELETE /media/<id> for the editor's orphan
            // cleanup. (OPTIONS preflight is answered by the HTTP library under its
            // permissive CORS policy.) Match on the path alone — the target carries
            // a query string (e.g. `?_embed`, `?force=true`) relayed to WordPress.
            let method = parsed.method.uppercased()

            if method == "POST", parsed.path == "/upload" {
                return await handleUpload(request)
            }

            if method == "DELETE", let attachmentId = Self.attachmentId(fromPath: parsed.path) {
                return await handleDelete(attachmentId, query: parsed.query)
            }

            return MediaUploadServer.errorResponse(status: 404, message: "Not found")
        }

        private func handleUpload(_ request: HTTPServer.Request) async -> HTTPResponse {
            let parts: [MultipartPart]
            do {
                parts = try request.parsed.multipartParts()
            } catch {
                Logger.uploadServer.error("Multipart parse failed: \(error)")
                return MediaUploadServer.errorResponse(status: 400, message: "Expected multipart/form-data")
            }

            // Find the file part (the first part with a filename).
            guard let filePart = parts.first(where: { $0.filename != nil }) else {
                return MediaUploadServer.errorResponse(status: 400, message: "No file found in request")
            }

            // The non-file parts (post, additionalData) and the original query
            // (e.g. ?_embed) must reach WordPress too — relay them alongside the file.
            let extraParts = parts.filter { $0.filename == nil }
            let query = request.parsed.query

            let filename = filePart.filename ?? "upload"
            let mimeType = filePart.contentType

            // Ask the processor — from metadata alone — whether it will touch a file like
            // this. If not, forward the original upload to WordPress directly, skipping a
            // full temp-file copy of a file the processor won't process (e.g. a video handed
            // to an image-only processor).
            //
            // An uploader takes over delivery for *every* file, so with one set there is
            // no passthrough to fall to and the gate can't decline the upload outright.
            // It still decides whether `processFile` runs, though — a declined file is
            // handed to the uploader unprocessed rather than to a processor that said it
            // won't touch it — so the answer is carried into `processAndUpload` rather
            // than discarded here. Asked exactly once per upload, matching Android.
            let processorWantsFile = processor?.handlesFile(ofType: mimeType, named: filename) ?? false
            guard uploader != nil || processorWantsFile else {
                do {
                    return try await passthroughResponse(request, query: query)
                } catch {
                    return Self.uploadErrorResponse(error)
                }
            }

            // Someone wants the file — the processor, the uploader, or both. Stream the
            // part body to a dedicated temp file for them: the library's RequestBody may
            // be a byte-range slice of a larger temp file whose lifecycle is tied to ARC,
            // so they need a standalone file that outlives the handler return.
            let tempDir = MediaUploadServer.uploadsTempDirectory
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let fileURL = tempDir.appending(component: "\(UUID().uuidString)-\(MediaUploadServer.sanitizeFilename(filename))")
            do {
                let inputStream = try filePart.body.makeInputStream()
                try MediaUploadServer.writeStream(inputStream, to: fileURL)
            } catch {
                try? FileManager.default.removeItem(at: fileURL)
                Logger.uploadServer.error("Failed to write upload to disk: \(error)")
                return MediaUploadServer.errorResponse(status: 500, message: "Failed to save file")
            }

            // From here on always clean up the original temp file. The processed
            // file (if the processor produced a new one) is cleaned up inside
            // processAndUpload so its throw paths are covered too.
            defer { try? FileManager.default.removeItem(at: fileURL) }

            do {
                let uploadResult = try await processAndUpload(
                        fileURL: fileURL, mimeType: mimeType, filename: filename,
                        extraParts: extraParts, query: query,
                        processorWantsFile: processorWantsFile
                    )
                switch uploadResult {
                case .uploaded(let uploaded):
                    Logger.uploadServer.debug("Uploaded file to WordPress")
                    return Self.relayResponse(uploaded)
                case .passthrough:
                    // The processor didn't modify the file — forward the original request
                    // body to WordPress without re-encoding.
                    return try await passthroughResponse(request, query: query)
                }
            } catch {
                return Self.uploadErrorResponse(error)
            }
        }

        /// Forwards the original request body to WordPress unchanged (no multipart
        /// re-encoding) and relays the response. Used when the processor won't touch
        /// the file — it declined by metadata (`handlesFile` returned false) or
        /// `processFile` returned `.original`.
        private func passthroughResponse(
            _ request: HTTPServer.Request, query: String
        ) async throws -> HTTPResponse {
            // As in `processAndUpload`: don't put bytes on the wire for a torn-down
            // editor, regardless of whether the HTTP client honors cancellation.
            try Task.checkCancellation()

            Logger.uploadServer.debug("Passthrough: forwarding original request body to WordPress")
            guard let body = request.parsed.body,
                  let contentType = request.parsed.header("Content-Type"),
                  let internalClient else {
                return MediaUploadServer.errorResponse(status: 500, message: UploadError.noUploader.localizedDescription)
            }
            let response = try await internalClient.passthroughUpload(body: body, contentType: contentType, query: query)
            return Self.relayResponse(response)
        }

        /// The attachment ID in a `/media/<id>` path, or `nil` if the path is not one.
        ///
        /// Deliberately narrow: this server relays media operations, not arbitrary
        /// REST requests, so only a numeric attachment ID under `/media/` matches.
        private static func attachmentId(fromPath path: String) -> String? {
            let components = path.split(separator: "/", omittingEmptySubsequences: true)
            guard components.count == 2, components[0] == "media" else { return nil }
            let id = String(components[1])
            guard !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
            return id
        }

        /// Relays the editor's orphan cleanup to WordPress.
        ///
        /// Core's media upload middleware deletes the attachment when every
        /// `post-process` retry fails. A cross-origin editor cannot issue that
        /// request directly — api-fetch tunnels `DELETE` as a `POST` carrying
        /// `X-HTTP-Method-Override`, which core's CORS allow-list omits, so the
        /// browser blocks it at preflight. Relaying it here lets the cleanup run.
        private func handleDelete(
            _ attachmentId: String, query: String
        ) async -> HTTPResponse {
            guard let internalClient else {
                return MediaUploadServer.errorResponse(status: 500, message: UploadError.noUploader.localizedDescription)
            }
            do {
                let response = try await internalClient.deleteMedia(attachmentId: attachmentId, query: query)
                return Self.relayResponse(response)
            } catch {
                return Self.uploadErrorResponse(error)
            }
        }

        /// Relays WordPress's exact status, body, and relayable headers to the editor
        /// so it sees the same attachment object (or error) as a direct upload.
        ///
        /// The headers matter for recovery: `x-wp-upload-attachment-id` is what lets
        /// the editor retry `post-process` for an upload whose metadata generation
        /// fataled server-side, rather than surfacing a permanent failure and
        /// leaving an orphaned attachment behind.
        ///
        /// The response's own `Content-Type` wins over the JSON default. `HTTPResponse`
        /// serializes every header it is given, so appending the default unconditionally
        /// would emit the name twice for a processor that sets it.
        private static func relayResponse(_ response: MediaUploadResponse) -> HTTPResponse {
            let hasContentType = response.headers.keys.contains { $0.lowercased() == "content-type" }
            return HTTPResponse(
                status: response.statusCode,
                headers: (hasContentType ? [] : [("Content-Type", "application/json")])
                    + response.headers.map { ($0.key, $0.value) },
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
            return MediaUploadServer.errorResponse(status: 500, message: error.localizedDescription)
        }

        // MARK: - Processor Pipeline

        /// Result of the processing + upload pipeline.
        private enum UploadResult {
            /// The uploader or internal media client completed the upload;
            /// carries the raw WordPress response to relay.
            case uploaded(MediaUploadResponse)
            /// The processor didn't modify the file, so the original body is forwarded.
            /// The caller should forward the original request body to WordPress.
            case passthrough
        }

        private func processAndUpload(
            fileURL: URL, mimeType: String, filename: String,
            extraParts: [MultipartPart], query: String, processorWantsFile: Bool
        ) async throws -> UploadResult {
            // Step 1: Process (resize, transcode, etc.) — but only for a file the
            // processor's metadata gate accepted. `handlesFile` returning false is the
            // processor saying it won't touch a file like this, so handing it one anyway
            // would break the contract the gate documents. With an uploader set the file
            // still gets delivered; it just skips processing on its way there.
            let processed: ProcessedProxyFile
            if let processor, processorWantsFile {
                processed = try await processor.processFile(at: fileURL, mimeType: mimeType, filename: filename)
            } else {
                processed = .original
            }

            // Resolve the file to upload and its metadata. `.processed` uses the
            // processor's values verbatim, so a format change is reported to WordPress.
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

            // The processed file (if the processor produced a new one) is ours to
            // clean up — on success it has been uploaded, on failure it is abandoned.
            // Cleaning up here rather than in the caller covers the throw paths too.
            defer {
                if uploadURL != fileURL {
                    try? FileManager.default.removeItem(at: uploadURL)
                }
            }

            // The editor was torn down (or the client disconnected) while we processed.
            // Don't start an outbound upload whose response nobody will read — it would
            // create an attachment neither GutenbergKit nor the host knows to clean up.
            // Checking here rather than relying on the HTTP client to notice cancellation
            // keeps this true for a host-injected `URLSessionProtocol` that doesn't.
            try Task.checkCancellation()

            // Step 2: deliver. An uploader owns delivery on the host's own stack and
            // returns the finished attachment JSON (or throws); GutenbergKit relays that
            // as a success and never runs its own recovery behind it.
            if let uploader {
                let upload = MediaUpload(
                    fileURL: uploadURL,
                    mimeType: uploadMimeType,
                    filename: uploadFilename,
                    fields: try await Self.formFields(from: extraParts),
                    query: query
                )
                let attachment = try await uploader.upload(upload)
                return .uploaded(MediaUploadResponse(statusCode: 201, body: attachment))
            }

            if let internalClient {
                // Unmodified — forward the original request body directly, skipping
                // multipart re-encoding.
                if case .original = processed {
                    return .passthrough
                }
                let result = try await internalClient.upload(fileURL: uploadURL, mimeType: uploadMimeType, filename: uploadFilename, extraParts: extraParts, query: query)
                return .uploaded(result)
            } else {
                throw UploadError.noUploader
            }
        }

        /// The editor's non-file form parts as ordered, UTF-8-decoded fields.
        ///
        /// A list rather than a dictionary so repeated names (e.g. a `field[]` array)
        /// survive verbatim, in the order the editor sent them.
        ///
        /// This decode can't mangle anything, but only because of who is on the other end —
        /// nothing in the code enforces it. Three things have to stay true:
        ///
        /// 1. Only the editor's own web page can reach this server. It listens on loopback,
        ///    and every request has to carry a per-session token.
        /// 2. Text the editor puts in a form field is already valid Unicode. The browser
        ///    guarantees that when the value is set, so it cannot hand us bad bytes.
        /// 3. The only way a browser can put *raw* bytes in a form is a file or a Blob, and
        ///    those always arrive with a filename. Anything with a filename is handled as
        ///    the file, never as a field — so raw bytes never reach this decode.
        ///
        /// If one of those stops being true, bad bytes quietly turn into replacement
        /// characters, and the platforms don't even agree on how many: `ED A0 80` becomes
        /// three of them here and one on Android. There is no single behavior worth
        /// documenting, so the tests pin rule 3 instead.
        private static func formFields(from parts: [MultipartPart]) async throws -> [MediaUploadField] {
            var fields: [MediaUploadField] = []
            for part in parts {
                fields.append(MediaUploadField(name: part.name, value: String(decoding: try await part.body.data, as: UTF8.self)))
            }
            return fields
        }
    }

    private static func errorResponse(status: Int, message: String) -> HTTPResponse {
        // Emit a WordPress-REST-style error object so the JS middleware normalizes
        // it (and surfaces `message`) the same way it does a relayed WordPress
        // error — the local server's own errors need no special-casing.
        let payload = ["code": "upload_error", "message": message]
        let body = (try? JSONSerialization.data(withJSONObject: payload))
            ?? Data(#"{"code":"upload_error","message":"Upload failed"}"#.utf8)
        return HTTPResponse(
            status: status,
            headers: [("Content-Type", "application/json")],
            body: body
        )
    }

    /// Answers the server's recoverable parse errors (e.g. an over-limit body)
    /// with the same JSON `{code, message}` shape the editor expects, so the
    /// middleware surfaces a real message ("The file is too large…") instead of a
    /// generic parse-failure. A leaf object — the HTTP server retains it.
    private final class ServerDelegate: HTTPServerDelegate {
        func response(forRecoverableParseError error: HTTPRequestParseError) -> HTTPResponse {
            let message: String = switch error {
            case .payloadTooLarge: "The file is too large to upload in the editor."
            default: "\(error.httpStatusText)"
            }
            return MediaUploadServer.errorResponse(status: error.httpStatus, message: message)
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
