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
    ///   - uploadDelegate: Optional delegate for customizing file processing and upload.
    ///   - defaultUploader: Fallback uploader used when no delegate provides `uploadFile`.
    ///   - maxRequestBodySize: The maximum allowed request body size in bytes.
    ///     Requests exceeding this limit receive a 413 response. Defaults to 4 GB.
    static func start(
        uploadDelegate: (any MediaUploadDelegate)? = nil,
        defaultUploader: DefaultMediaUploader? = nil,
        maxRequestBodySize: Int64 = HTTPRequestParser.defaultMaxBodySize
    ) async throws -> MediaUploadServer {
        // Sweep temp files orphaned by a prior crash, off the editor-startup
        // path — the sweep only deletes stale files (>1 hour old), so it cannot
        // race this server's own in-flight uploads and nothing below depends on it.
        let cleanupTask = Task.detached(priority: .utility) {
            cleanOrphanedUploads()
        }

        let context = UploadContext(uploadDelegate: uploadDelegate, defaultUploader: defaultUploader)

        let server = try await HTTPServer.start(
            name: "media-upload",
            requiresAuthentication: true,
            maxRequestBodySize: maxRequestBodySize,
            cors: .permissive,
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

        // Server-detected error (e.g., payload too large) — build the
        // error response here so it includes CORS headers.
        if let serverError = request.serverError {
            let message: String = switch serverError {
            case .payloadTooLarge: "The file is too large to upload in the editor."
            default: "\(serverError.httpStatusText)"
            }
            return errorResponse(status: serverError.httpStatus, message: message)
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

        // Write part body to a dedicated temp file for the delegate.
        //
        // The library's RequestBody may be a byte-range slice of a larger temp
        // file whose lifecycle is tied to ARC. The delegate needs a standalone
        // file that outlives the handler return, so we stream to our own file.
        let filename = sanitizeFilename(filePart.filename ?? "upload")
        let mimeType = filePart.contentType

        let tempDir = uploadsTempDirectory
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let fileURL = tempDir.appending(component: "\(UUID().uuidString)-\(filename)")
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
                fileURL: fileURL, mimeType: mimeType, filename: filePart.filename ?? "upload",
                extraParts: extraParts, query: query, context: context
            )
            let response: MediaUploadResponse
            switch uploadResult {
            case .uploaded(let uploaded):
                Logger.uploadServer.debug("Uploaded file to WordPress")
                response = uploaded
            case .passthrough:
                // Delegate didn't modify the file — forward the original
                // request body to WordPress without re-encoding.
                Logger.uploadServer.debug("Passthrough: forwarding original request body to WordPress")
                guard let body = request.parsed.body,
                      let contentType = request.parsed.header("Content-Type"),
                      let defaultUploader = context.defaultUploader else {
                    return errorResponse(status: 500, message: UploadError.noUploader.localizedDescription)
                }
                response = try await defaultUploader.passthroughUpload(body: body, contentType: contentType, query: query)
            }
            // Relay WordPress's exact status and body to the editor so it sees
            // the same attachment object (or error) as a direct upload.
            return HTTPResponse(
                status: response.statusCode,
                headers: [("Content-Type", "application/json")],
                body: response.body
            )
        } catch {
            Logger.uploadServer.error("Upload processing failed: \(error)")
            return errorResponse(status: 500, message: error.localizedDescription)
        }
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

/// Container for the upload delegate and default uploader, captured by the
/// HTTPServer handler closure and re-read on each request.
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

    init(uploadDelegate: (any MediaUploadDelegate)?, defaultUploader: DefaultMediaUploader?) {
        self.uploadDelegate = uploadDelegate
        self.defaultUploader = defaultUploader
    }
}

// MARK: - Default Media Uploader

/// Uploads files to the WordPress REST API using site credentials from EditorConfiguration.
class DefaultMediaUploader: @unchecked Sendable {
    private let httpClient: EditorHTTPClientProtocol
    private let siteApiRoot: URL
    private let siteApiNamespace: String?

    init(httpClient: EditorHTTPClientProtocol, siteApiRoot: URL, siteApiNamespace: [String] = []) {
        self.httpClient = httpClient
        self.siteApiRoot = siteApiRoot
        self.siteApiNamespace = siteApiNamespace.first
    }

    /// The WordPress media endpoint URL, built through the shared
    /// ``WordPressRESTURL`` namespacing (so it matches every other REST URL) and
    /// carrying the original request query (e.g. `?_embed`) through to WordPress.
    private func mediaEndpointURL(query: String) -> URL {
        let base = WordPressRESTURL.namespaced(apiRoot: siteApiRoot, path: "/wp/v2/media", namespace: siteApiNamespace)
        guard !query.isEmpty else { return base }
        // `query` is the raw request query in wire form (leading "?"). Set it via
        // `percentEncodedQuery` so a value that isn't URL-safe can't make
        // `URL(string:)` return nil and silently drop the query.
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.percentEncodedQuery = String(query.dropFirst())
        return components?.url ?? base
    }

    func upload(fileURL: URL, mimeType: String, filename: String, extraParts: [MultipartPart], query: String) async throws -> MediaUploadResponse {
        let boundary = UUID().uuidString

        // Read the (small, text) non-file parts up front so the body builder
        // stays synchronous — the file itself is still streamed from disk.
        var extraFields: [(name: String, value: Data)] = []
        for part in extraParts {
            extraFields.append((part.name, try await part.body.data))
        }

        let (bodyStream, contentLength) = try Self.multipartBodyStream(
            fileURL: fileURL, boundary: boundary, filename: filename, mimeType: mimeType, extraFields: extraFields
        )

        var request = URLRequest(url: mediaEndpointURL(query: query))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("\(contentLength)", forHTTPHeaderField: "Content-Length")
        request.httpBodyStream = bodyStream

        return try await performUpload(request)
    }

    /// Forwards the original request body to WordPress without re-encoding.
    ///
    /// Used when the delegate's `processFile` returned the file unchanged —
    /// the incoming multipart body is already valid for WordPress.
    func passthroughUpload(body: RequestBody, contentType: String, query: String) async throws -> MediaUploadResponse {
        var request = URLRequest(url: mediaEndpointURL(query: query))
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")
        request.httpBodyStream = try body.makeInputStream()

        return try await performUpload(request)
    }

    private func performUpload(_ request: URLRequest) async throws -> MediaUploadResponse {
        // Relay WordPress's response verbatim — including non-2xx statuses — so
        // the editor sees WordPress's real status and error body, exactly as a
        // direct upload would. `performRaw` does not throw on non-2xx.
        let (data, response) = try await httpClient.performRaw(request)
        return MediaUploadResponse(statusCode: response.statusCode, body: data)
    }

    // MARK: - Streaming Multipart Body

    /// Builds a multipart/form-data body as an `InputStream` that streams the
    /// file from disk without loading it into memory.
    ///
    /// Uses a bound stream pair with a background writer thread — the same
    /// pattern as `RequestBody.makePipedFileSliceStream`.
    ///
    /// - Returns: A tuple of the input stream and the total content length.
    static func multipartBodyStream(
        fileURL: URL,
        boundary: String,
        filename: String,
        mimeType: String,
        extraFields: [(name: String, value: Data)]
    ) throws -> (InputStream, Int) {
        // Serialize the non-file parts (post, additionalData) into the preamble
        // ahead of the streamed file. They are small, so keeping them in memory is
        // fine; `contentLength` counts them via `preamble.count`. Field values are
        // appended as raw bytes (not through String) so a non-UTF-8 value is
        // forwarded verbatim rather than coerced to empty.
        var preamble = Data()
        for field in extraFields {
            preamble.append(Data("--\(boundary)\r\n".utf8))
            preamble.append(Data("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n".utf8))
            preamble.append(field.value)
            preamble.append(Data("\r\n".utf8))
        }
        preamble.append(Data("--\(boundary)\r\n".utf8))
        preamble.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
        preamble.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        let epilogue = Data("\r\n--\(boundary)--\r\n".utf8)

        guard let fileSize = try FileManager.default.attributesOfItem(atPath: fileURL.path(percentEncoded: false))[.size] as? Int else {
            throw UploadError.streamReadFailed
        }
        let contentLength = preamble.count + fileSize + epilogue.count

        let fileHandle = try FileHandle(forReadingFrom: fileURL)

        var readStream: InputStream?
        var writeStream: OutputStream?
        Stream.getBoundStreams(withBufferSize: 65_536, inputStream: &readStream, outputStream: &writeStream)

        guard let inputStream = readStream, let outputStream = writeStream else {
            try? fileHandle.close()
            throw UploadError.streamReadFailed
        }

        outputStream.open()

        // OutputStream is not Sendable but is safely transferred to the
        // writer thread — only the thread accesses it after this point.
        nonisolated(unsafe) let output = outputStream

        Thread.detachNewThread {
            defer {
                output.close()
                try? fileHandle.close()
            }

            // Write preamble (multipart headers).
            guard Self.writeAll(preamble, to: output) else { return }

            // Stream file content in chunks.
            var remaining = fileSize
            while remaining > 0 {
                let chunkSize = min(65_536, remaining)
                guard let chunk = try? fileHandle.read(upToCount: chunkSize),
                      !chunk.isEmpty else {
                    break
                }
                guard Self.writeAll(chunk, to: output) else { return }
                remaining -= chunk.count
            }

            // Write epilogue (closing boundary).
            _ = Self.writeAll(epilogue, to: output)
        }

        return (inputStream, contentLength)
    }

    /// Writes all bytes of `data` to the output stream, handling partial writes.
    private static func writeAll(_ data: Data, to output: OutputStream) -> Bool {
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
            var written = 0
            while written < data.count {
                let result = output.write(base.advanced(by: written), maxLength: data.count - written)
                if result <= 0 { return false }
                written += result
            }
            return true
        }
    }
}
