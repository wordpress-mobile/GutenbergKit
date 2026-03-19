import Foundation
import OSLog
import GutenbergKitHTTP

/// A lightweight local HTTP server that receives file uploads from the WebView
/// and routes them through the native media processing pipeline.
///
/// The server binds to `127.0.0.1` on a random available port and validates
/// all requests using a per-session Bearer token in the `Relay-Authorization`
/// header. It handles:
/// - `OPTIONS` preflight requests (CORS)
/// - `POST /upload` multipart form-data uploads
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
    init(
        uploadDelegate: (any MediaUploadDelegate)? = nil,
        defaultUploader: DefaultMediaUploader? = nil
    ) async throws {
        let delegate = uploadDelegate
        let uploader = defaultUploader
        let httpServer = try await HTTPServer.start(
            name: "media-upload",
            maxRequestBodySize: Int64(250 * 1024 * 1024)
        ) { request in
            await Self.handleRequest(
                request.parsed,
                uploadDelegate: delegate,
                defaultUploader: uploader
            )
        }
        self.port = httpServer.port
        self.token = httpServer.token
        self.server = httpServer
        Logger.uploadServer.info("Upload server started on port \(httpServer.port)")
    }

    /// Stops the server and releases resources.
    func stop() {
        server.stop()
        Logger.uploadServer.info("Upload server stopped")
    }

    deinit {
        server.stop()
    }

    // MARK: - Request Handling

    private static func handleRequest(
        _ request: ParsedHTTPRequest,
        uploadDelegate: (any MediaUploadDelegate)?,
        defaultUploader: DefaultMediaUploader?
    ) async -> HTTPResponse {
        // Route
        guard request.method == "POST", request.target == "/upload" else {
            return HTTPResponse(
                status: 404,
                headers: corsHeaders + [("Content-Type", "text/plain")],
                body: Data("Not found".utf8)
            )
        }

        return await handleUpload(request, uploadDelegate: uploadDelegate, defaultUploader: defaultUploader)
    }

    private static func handleUpload(
        _ request: ParsedHTTPRequest,
        uploadDelegate: (any MediaUploadDelegate)?,
        defaultUploader: DefaultMediaUploader?
    ) async -> HTTPResponse {
        // Parse multipart body using GutenbergKitHTTP
        let parts: [MultipartPart]
        do {
            parts = try request.multipartParts()
        } catch {
            Logger.uploadServer.error("Multipart parse failed: \(error)")
            return HTTPResponse(
                status: 400,
                headers: corsHeaders + [("Content-Type", "text/plain")],
                body: Data("Expected multipart/form-data".utf8)
            )
        }

        guard let filePart = parts.first(where: { $0.filename != nil }) else {
            Logger.uploadServer.error("No file found in multipart request")
            return HTTPResponse(
                status: 400,
                headers: corsHeaders + [("Content-Type", "text/plain")],
                body: Data("No file found in request".utf8)
            )
        }

        let filename = filePart.filename!
        let mimeType = filePart.contentType

        // Sanitize the filename to prevent path traversal from malicious Content-Disposition values.
        let safeFilename = (filename as NSString).lastPathComponent
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "\\", with: "")
        let sanitizedFilename = safeFilename.isEmpty ? "upload" : safeFilename

        // Write file to temp directory.
        let tempDir = FileManager.default.temporaryDirectory
            .appending(component: "GutenbergKit-uploads", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let fileURL = tempDir.appending(component: "\(UUID().uuidString)-\(sanitizedFilename)")
        do {
            let fileData = try await filePart.body.data
            try fileData.write(to: fileURL)
        } catch {
            Logger.uploadServer.error("Failed to write upload to disk: \(error)")
            return HTTPResponse(
                status: 500,
                headers: corsHeaders + [("Content-Type", "text/plain")],
                body: Data("Failed to save file".utf8)
            )
        }

        // Process the file and upload to the remote WordPress server.
        let result: Result<MediaUploadResult, Error>
        var processedURL: URL?
        do {
            let (media, processed) = try await processAndUpload(
                fileURL: fileURL,
                mimeType: mimeType,
                filename: filename,
                uploadDelegate: uploadDelegate,
                defaultUploader: defaultUploader
            )
            processedURL = processed
            result = .success(media)
        } catch {
            result = .failure(error)
        }

        // Clean up temp files after processing completes (success or failure).
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
                return HTTPResponse(
                    status: 500,
                    headers: corsHeaders + [("Content-Type", "text/plain")],
                    body: Data("Failed to encode response".utf8)
                )
            }
        case .failure(let error):
            Logger.uploadServer.error("Upload processing failed: \(error)")
            return HTTPResponse(
                status: 500,
                headers: corsHeaders + [("Content-Type", "text/plain")],
                body: Data(error.localizedDescription.utf8)
            )
        }
    }

    private static func processAndUpload(
        fileURL: URL,
        mimeType: String,
        filename: String,
        uploadDelegate: (any MediaUploadDelegate)?,
        defaultUploader: DefaultMediaUploader?
    ) async throws -> (MediaUploadResult, URL) {
        // Step 1: Process (resize, transcode, etc.)
        let processedURL: URL
        if let delegate = uploadDelegate {
            processedURL = try await delegate.processFile(at: fileURL, mimeType: mimeType)
        } else {
            processedURL = fileURL
        }

        // Step 2: Upload to remote WordPress
        if let delegate = uploadDelegate,
           let result = try await delegate.uploadFile(at: processedURL, mimeType: mimeType, filename: filename) {
            return (result, processedURL)
        } else if let defaultUploader {
            return (try await defaultUploader.upload(fileURL: processedURL, mimeType: mimeType, filename: filename), processedURL)
        } else {
            throw ServerError.noUploader
        }
    }

    // MARK: - Constants

    private static let corsHeaders: [(String, String)] = [
        ("Access-Control-Allow-Origin", "*"),
        ("Access-Control-Allow-Methods", "POST, OPTIONS"),
        ("Access-Control-Allow-Headers", "Relay-Authorization, Authorization, Content-Type"),
        ("Access-Control-Max-Age", "86400"),
    ]

    // MARK: - Errors

    enum ServerError: Error, LocalizedError {
        case noUploader

        var errorDescription: String? {
            switch self {
            case .noUploader: "No upload delegate or default uploader configured"
            }
        }
    }
}

// MARK: - Default Media Uploader

/// Uploads files to the WordPress REST API using site credentials from EditorConfiguration.
class DefaultMediaUploader: @unchecked Sendable {
    private let httpClient: EditorHTTPClientProtocol
    private let siteApiRoot: URL

    init(httpClient: EditorHTTPClientProtocol, siteApiRoot: URL) {
        self.httpClient = httpClient
        self.siteApiRoot = siteApiRoot
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

        let uploadURL = siteApiRoot.appending(path: "wp/v2/media")
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

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
