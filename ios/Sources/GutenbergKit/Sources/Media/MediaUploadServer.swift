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

    /// Creates and starts a new upload server.
    ///
    /// - Parameters:
    ///   - uploadDelegate: Optional delegate for customizing file processing and upload.
    ///   - defaultUploader: Fallback uploader used when no delegate provides `uploadFile`.
    static func start(
        uploadDelegate: (any MediaUploadDelegate)? = nil,
        defaultUploader: DefaultMediaUploader? = nil
    ) async throws -> MediaUploadServer {
        let context = UploadContext(uploadDelegate: uploadDelegate, defaultUploader: defaultUploader)

        let server = try await HTTPServer.start(
            name: "media-upload",
            requiresAuthentication: true,
            errorResponseHeaders: corsHeaders,
            handler: { request in
                await Self.handleRequest(request, context: context)
            }
        )

        return MediaUploadServer(server: server)
    }

    private init(server: HTTPServer) {
        self.server = server
        self.port = server.port
        self.token = server.token
    }

    /// Stops the server and releases resources.
    func stop() {
        server.stop()
    }

    // MARK: - Request Handling

    private static func handleRequest(_ request: HTTPServer.Request, context: UploadContext) async -> HTTPResponse {
        let parsed = request.parsed

        // CORS preflight — the library exempts OPTIONS from auth, so this is
        // reached without a token.
        if parsed.method.uppercased() == "OPTIONS" {
            return corsPreflightResponse()
        }

        // Route: only POST /upload is handled.
        guard parsed.method.uppercased() == "POST", parsed.target == "/upload" else {
            return errorResponse(status: 404, body: "Not found")
        }

        return await handleUpload(request, context: context)
    }

    private static func handleUpload(_ request: HTTPServer.Request, context: UploadContext) async -> HTTPResponse {
        let parts: [MultipartPart]
        do {
            parts = try request.parsed.multipartParts()
        } catch {
            Logger.uploadServer.error("Multipart parse failed: \(error)")
            return errorResponse(status: 400, body: "Expected multipart/form-data")
        }

        // Find the file part (the first part with a filename).
        guard let filePart = parts.first(where: { $0.filename != nil }) else {
            return errorResponse(status: 400, body: "No file found in request")
        }

        // Write part body to a dedicated temp file for the delegate.
        //
        // The library's RequestBody may be a byte-range slice of a larger temp
        // file whose lifecycle is tied to ARC. The delegate needs a standalone
        // file that outlives the handler return, so we stream to our own file.
        let filename = sanitizeFilename(filePart.filename ?? "upload")
        let mimeType = filePart.contentType

        let tempDir = FileManager.default.temporaryDirectory
            .appending(component: "GutenbergKit-uploads", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let fileURL = tempDir.appending(component: "\(UUID().uuidString)-\(filename)")
        do {
            let inputStream = try filePart.body.makeInputStream()
            try writeStream(inputStream, to: fileURL)
        } catch {
            Logger.uploadServer.error("Failed to write upload to disk: \(error)")
            return errorResponse(status: 500, body: "Failed to save file")
        }

        // Process and upload through the delegate pipeline.
        let result: Result<MediaUploadResult, Error>
        var processedURL: URL?
        do {
            let (media, processed) = try await processAndUpload(
                fileURL: fileURL, mimeType: mimeType, filename: filePart.filename ?? "upload", context: context
            )
            processedURL = processed
            result = .success(media)
        } catch {
            result = .failure(error)
        }

        // Clean up temp files (success or failure).
        try? FileManager.default.removeItem(at: fileURL)
        if let processedURL, processedURL != fileURL {
            try? FileManager.default.removeItem(at: processedURL)
        }

        switch result {
        case .success(let media):
            do {
                let json = try JSONEncoder().encode(media)
                return HTTPResponse(
                    status: 200,
                    headers: corsHeaders + [("Content-Type", "application/json")],
                    body: json
                )
            } catch {
                return errorResponse(status: 500, body: "Failed to encode response")
            }
        case .failure(let error):
            Logger.uploadServer.error("Upload processing failed: \(error)")
            return errorResponse(status: 500, body: error.localizedDescription)
        }
    }

    // MARK: - Delegate Pipeline

    private static func processAndUpload(
        fileURL: URL, mimeType: String, filename: String, context: UploadContext
    ) async throws -> (MediaUploadResult, URL) {
        // Step 1: Process (resize, transcode, etc.)
        let processedURL: URL
        if let delegate = context.uploadDelegate {
            processedURL = try await delegate.processFile(at: fileURL, mimeType: mimeType)
        } else {
            processedURL = fileURL
        }

        // Step 2: Upload to remote WordPress
        if let delegate = context.uploadDelegate,
           let result = try await delegate.uploadFile(at: processedURL, mimeType: mimeType, filename: filename) {
            return (result, processedURL)
        } else if let defaultUploader = context.defaultUploader {
            return (try await defaultUploader.upload(fileURL: processedURL, mimeType: mimeType, filename: filename), processedURL)
        } else {
            throw UploadError.noUploader
        }
    }

    // MARK: - CORS

    private static let corsHeaders: [(String, String)] = [
        ("Access-Control-Allow-Origin", "*"),
        ("Access-Control-Allow-Headers", "Relay-Authorization, Content-Type"),
    ]

    private static func corsPreflightResponse() -> HTTPResponse {
        HTTPResponse(
            status: 204,
            headers: corsHeaders + [
                ("Access-Control-Allow-Methods", "POST, OPTIONS"),
                ("Access-Control-Max-Age", "86400"),
            ],
            body: Data()
        )
    }

    private static func errorResponse(status: Int, body: String) -> HTTPResponse {
        HTTPResponse(
            status: status,
            headers: corsHeaders + [("Content-Type", "text/plain")],
            body: Data(body.utf8)
        )
    }

    // MARK: - Helpers

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

        let outputStream = OutputStream(url: url, append: false)!
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

    // MARK: - Errors

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
}

// MARK: - Upload Context

/// Thread-safe container for the upload delegate and default uploader,
/// captured by the HTTPServer handler closure.
private struct UploadContext: Sendable {
    let uploadDelegate: (any MediaUploadDelegate)?
    let defaultUploader: DefaultMediaUploader?
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

    func upload(fileURL: URL, mimeType: String, filename: String) async throws -> MediaUploadResult {
        let fileData = try Data(contentsOf: fileURL)
        let boundary = UUID().uuidString

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n")

        // When a site API namespace is configured (e.g. "sites/12345/"), insert
        // it into the media endpoint path so the request reaches the correct site.
        let mediaPath = if let siteApiNamespace {
            "wp/v2/\(siteApiNamespace)media"
        } else {
            "wp/v2/media"
        }
        let uploadURL = siteApiRoot.appending(path: mediaPath)
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await httpClient.perform(request)

        guard (200...299).contains(response.statusCode) else {
            let preview = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
            throw MediaUploadError.uploadFailed(statusCode: response.statusCode, preview: preview)
        }

        // Parse the WordPress media response into our result type
        let wpMedia: WPMediaResponse
        do {
            wpMedia = try JSONDecoder().decode(WPMediaResponse.self, from: data)
        } catch {
            let preview = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
            throw MediaUploadError.unexpectedResponse(preview: preview, underlyingError: error)
        }

        return MediaUploadResult(
            id: wpMedia.id,
            url: wpMedia.source_url,
            alt: wpMedia.alt_text ?? "",
            caption: wpMedia.caption?.rendered ?? "",
            title: wpMedia.title.rendered,
            mime: wpMedia.mime_type,
            type: wpMedia.media_type,
            width: wpMedia.media_details?.width,
            height: wpMedia.media_details?.height
        )
    }
}

/// WordPress REST API media response (subset of fields).
private struct WPMediaResponse: Decodable {
    let id: Int
    let source_url: String
    let alt_text: String?
    let caption: RenderedField?
    let title: RenderedField
    let mime_type: String
    let media_type: String
    let media_details: MediaDetails?

    struct RenderedField: Decodable {
        let rendered: String
    }

    struct MediaDetails: Decodable {
        let width: Int?
        let height: Int?
    }
}

/// Errors specific to the native media upload pipeline.
enum MediaUploadError: Error, LocalizedError {
    /// The WordPress REST API returned a non-success HTTP status code.
    case uploadFailed(statusCode: Int, preview: String)

    /// The WordPress REST API returned a non-JSON response (e.g. HTML error page).
    case unexpectedResponse(preview: String, underlyingError: Error)

    var errorDescription: String? {
        switch self {
        case .uploadFailed(let statusCode, let preview):
            return "Upload failed (\(statusCode)): \(preview)"
        case .unexpectedResponse(let preview, _):
            return "WordPress returned an unexpected response: \(preview)"
        }
    }
}

// MARK: - Helpers

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
