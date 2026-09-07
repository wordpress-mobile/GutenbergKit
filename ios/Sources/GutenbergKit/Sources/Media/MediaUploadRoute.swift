import Foundation
import GutenbergKitHTTP
import OSLog

/// The local server route that receives file uploads from the WebView and
/// routes them through the native media processing pipeline: receiving a
/// file, delegating to the host app for processing/upload, and returning the
/// result as JSON.
///
/// The delegate is held **weakly**. `EditorViewController.mediaUploadDelegate` is
/// declared `weak` — the host owns the delegate's lifetime. Capturing it strongly
/// here would silently defeat that contract and, worse, risk a retain cycle
/// (`EditorViewController → server → HTTPServer → handler → route → delegate →
/// EditorViewController`) that would keep the view controller — and therefore
/// the server — alive forever, so `deinit` would never stop it.
///
/// `@unchecked Sendable`: `uploadDelegate` is assigned once at init and only read
/// afterwards; weak-reference reads are thread-safe at runtime.
final class MediaUploadRoute: LocalServerRoute, @unchecked Sendable {
    private weak var uploadDelegate: (any MediaUploadDelegate)?
    private let defaultUploader: DefaultMediaUploader?

    /// Sweeps crash-orphaned upload temp files off the editor-startup path.
    /// Exposed so tests can await completion. (Mirrors Android's `cleanupJob`.)
    let cleanupTask: Task<Void, Never>

    /// - Parameters:
    ///   - uploadDelegate: Optional delegate for customizing file processing and upload.
    ///   - defaultUploader: Fallback uploader used when no delegate provides `uploadFile`.
    init(uploadDelegate: (any MediaUploadDelegate)? = nil, defaultUploader: DefaultMediaUploader? = nil) {
        self.uploadDelegate = uploadDelegate
        self.defaultUploader = defaultUploader

        // Sweep temp files orphaned by a prior crash, off the editor-startup
        // path — the sweep only deletes stale files (>1 hour old), so it cannot
        // race this route's own in-flight uploads and nothing below depends on it.
        cleanupTask = Task.detached(priority: .utility) {
            Self.cleanOrphanedUploads()
        }
    }

    /// Only POST /upload is handled. (OPTIONS preflight is answered by the HTTP
    /// library under its permissive CORS policy.) Match on the path alone — the
    /// target carries a query string (e.g. `?_embed`) that the upload handler
    /// relays on to WordPress.
    func handles(_ request: ParsedHTTPRequest) -> Bool {
        request.method.uppercased() == "POST" && request.path == "/upload"
    }

    func handle(_ request: HTTPServer.Request) async -> HTTPResponse {
        let parts: [MultipartPart]
        do {
            parts = try request.parsed.multipartParts()
        } catch {
            Logger.uploadServer.error("Multipart parse failed: \(error)")
            return Self.errorResponse(status: 400, message: "Expected multipart/form-data")
        }

        // Find the file part (the first part with a filename).
        guard let filePart = parts.first(where: { $0.filename != nil }) else {
            return Self.errorResponse(status: 400, message: "No file found in request")
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
        guard uploadDelegate?.handlesFile(ofType: mimeType, named: filename) ?? false else {
            do {
                return try await passthroughResponse(request, query: query)
            } catch {
                return Self.uploadErrorResponse(error)
            }
        }

        // The delegate wants the file. Stream the part body to a dedicated temp
        // file for it — the library's RequestBody may be a byte-range slice of a
        // larger temp file whose lifecycle is tied to ARC, so the delegate needs a
        // standalone file that outlives the handler return.
        let tempDir = Self.uploadsTempDirectory
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let fileURL = tempDir.appending(component: "\(UUID().uuidString)-\(Self.sanitizeFilename(filename))")
        do {
            let inputStream = try filePart.body.makeInputStream()
            try Self.writeStream(inputStream, to: fileURL)
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            Logger.uploadServer.error("Failed to write upload to disk: \(error)")
            return Self.errorResponse(status: 500, message: "Failed to save file")
        }

        // From here on always clean up the original temp file. The processed
        // file (if the delegate produced a new one) is cleaned up inside
        // processAndUpload so its throw paths are covered too.
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            let uploadResult = try await processAndUpload(
                fileURL: fileURL, mimeType: mimeType, filename: filename,
                extraParts: extraParts, query: query
            )
            switch uploadResult {
            case .uploaded(let uploaded):
                Logger.uploadServer.debug("Uploaded file to WordPress")
                return Self.relayResponse(uploaded)
            case .passthrough:
                // Delegate didn't modify the file — forward the original request
                // body to WordPress without re-encoding.
                return try await passthroughResponse(request, query: query)
            }
        } catch {
            return Self.uploadErrorResponse(error)
        }
    }

    /// Forwards the original request body to WordPress unchanged (no multipart
    /// re-encoding) and relays the response. Used when the delegate won't touch
    /// the file — it declined by metadata (`handlesFile` returned false) or
    /// `processFile` returned `.original`.
    private func passthroughResponse(_ request: HTTPServer.Request, query: String) async throws -> HTTPResponse {
        Logger.uploadServer.debug("Passthrough: forwarding original request body to WordPress")
        guard let body = request.parsed.body,
              let contentType = request.parsed.header("Content-Type"),
              let defaultUploader else {
            return Self.errorResponse(status: 500, message: UploadError.noUploader.localizedDescription)
        }
        let response = try await defaultUploader.passthroughUpload(body: body, contentType: contentType, query: query)
        return Self.relayResponse(response)
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

    private func processAndUpload(
        fileURL: URL, mimeType: String, filename: String,
        extraParts: [MultipartPart], query: String
    ) async throws -> UploadResult {
        // Step 1: Process (resize, transcode, etc.)
        let processed: ProcessedProxyFile
        if let delegate = uploadDelegate {
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
        if let delegate = uploadDelegate,
           let result = try await delegate.uploadFile(at: uploadURL, mimeType: uploadMimeType, filename: uploadFilename) {
            return .uploaded(result)
        } else if let defaultUploader {
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
