import Foundation
import OSLog

// MARK: - Errors

/// Errors from the native media upload pipeline.
enum UploadError: Error, LocalizedError {
    case noUploader
    case streamReadFailed

    var errorDescription: String? {
        switch self {
        case .noUploader: "No media uploader or internal media client configured"
        case .streamReadFailed: "Failed to read upload stream"
        }
    }
}

// MARK: - Internal Media Client

/// GutenbergKit's own client for the configured site, built from the site credentials
/// in `EditorConfiguration`.
///
/// Not an implementation of any host-facing protocol — it is the thing that actually
/// performs GutenbergKit's media requests. It delivers uploads the host did not take
/// over, and relays the editor's media deletes: every attachment lives on the
/// configured site, so that is where its deletion goes.
class InternalMediaClient: @unchecked Sendable {
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
    private func mediaEndpointURL(query: String, attachmentId: String? = nil) -> URL {
        let path = attachmentId.map { "/wp/v2/media/\($0)" } ?? "/wp/v2/media"
        let base = WordPressRESTURL.namespaced(apiRoot: siteApiRoot, path: path, namespace: siteApiNamespace)
        guard !query.isEmpty else { return base }
        // `query` is the raw request query in wire form (leading "?"). Set it via
        // `percentEncodedQuery` so a value that isn't URL-safe can't make
        // `URL(string:)` return nil and silently drop the query.
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.percentEncodedQuery = String(query.dropFirst())
        return components?.url ?? base
    }

    /// Uploads a file to `POST /wp/v2/media` as `multipart/form-data`, streaming it
    /// from disk, and relays WordPress's response verbatim — non-2xx included.
    ///
    /// - Parameters:
    ///   - fields: The editor's other form fields (e.g. `post`), sent ahead of the file
    ///     in the order given.
    ///   - query: The editor's request query in wire form (leading `?`), or empty.
    func upload(fileURL: URL, mimeType: String, filename: String, fields: [MediaUploadField], query: String) async throws -> MediaUploadResponse {
        let boundary = UUID().uuidString
        let extraFields = fields.map { (name: $0.name, value: Data($0.value.utf8)) }

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

    /// Deletes an attachment, relaying WordPress's response verbatim.
    ///
    /// Carries the editor's query through unchanged — core's cleanup sends
    /// `?force=true`, without which WordPress trashes rather than deletes.
    func deleteMedia(attachmentId: String, query: String) async throws -> MediaUploadResponse {
        var request = URLRequest(url: mediaEndpointURL(query: query, attachmentId: attachmentId))
        request.httpMethod = "DELETE"

        // Authorization is applied centrally by the HTTP client, as for uploads.
        let (data, response) = try await httpClient.performRaw(request)
        return MediaUploadResponse(
            statusCode: response.statusCode,
            body: data,
            headers: Self.relayableHeaders(from: response)
        )
    }

    /// Sends the assembled upload request to WordPress and relays the response.
    ///
    /// The request body is a **one-shot** stream (a bound-pair pipe for the
    /// multipart body), so it can't be replayed. That
    /// only matters if URLSession has to resend the body — i.e. a `307`/`308`
    /// redirect that preserves the `POST`. `301`/`302`/`303` downgrade to a
    /// bodyless GET, and a Bearer-token `401` doesn't trigger a resend, so those
    /// never replay the stream. WordPress core never redirects `POST /wp/v2/media`;
    /// if a proxy or misconfiguration did, the resend would read the now-exhausted
    /// stream and send an empty body, which WordPress rejects — a clean failure,
    /// not a truncated attachment (the stream is consumed, never rewound). We
    /// intentionally don't implement `needNewBodyStream`, or buffer the body to a
    /// replayable file, for that rare case.
    private func performUpload(_ request: URLRequest) async throws -> MediaUploadResponse {
        // The body is fed by a background writer thread via a bound stream pair
        // (`multipartBodyStream`). If
        // the request is cancelled or fails, URLSession may abandon the stream
        // without draining it, leaving that writer blocked forever on a full buffer
        // — leaking the thread and its open file handle. Closing the input stream on
        // every exit breaks the pair so the writer's write() fails and it unwinds.
        defer { request.httpBodyStream?.close() }

        // Relay WordPress's response verbatim — including non-2xx statuses — so
        // the editor sees WordPress's real status and error body, exactly as a
        // direct upload would. `performRaw` does not throw on non-2xx.
        let (data, response) = try await httpClient.performRaw(request)
        return MediaUploadResponse(
            statusCode: response.statusCode,
            body: data,
            headers: Self.relayableHeaders(from: response)
        )
    }

    /// The upstream headers worth relaying to the editor.
    ///
    /// Deliberately an allowlist rather than a filtered passthrough: the body is
    /// re-sent with a recomputed length, so relaying upstream entity or
    /// transport headers wholesale would risk contradicting what the server
    /// actually sends.
    private static let relayableHeaderNames = ["x-wp-upload-attachment-id"]

    /// Picks the headers to relay out of an upstream response.
    private static func relayableHeaders(from response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for name in relayableHeaderNames {
            if let value = response.value(forHTTPHeaderField: name) {
                headers[name] = value
            }
        }
        return headers
    }

    // MARK: - Streaming Multipart Body

    /// Builds a multipart/form-data body as an `InputStream` that streams the
    /// file from disk without loading it into memory.
    ///
    /// Uses a bound stream pair with a background writer thread.
    ///
    /// - Returns: A tuple of the input stream and the total content length.
    static func multipartBodyStream(
        fileURL: URL,
        boundary: String,
        filename: String,
        mimeType: String,
        extraFields: [(name: String, value: Data)]
    ) throws -> (InputStream, Int) {
        // The non-file parts (post, additionalData) go into the preamble ahead of the streamed
        // file; they're small, and `contentLength` counts them via `preamble.count`. Their
        // values are appended as raw bytes rather than through `String(data:encoding:)`, which
        // returns nil on bad UTF-8 — and the `?? ""` you'd reach for behind it would quietly
        // drop a whole field.
        var preamble = Data()
        for field in extraFields {
            preamble.append(Data("--\(boundary)\r\n".utf8))
            preamble.append(Data("Content-Disposition: form-data; name=\"\(escapeQuotedParameter(field.name))\"\r\n\r\n".utf8))
            preamble.append(field.value)
            preamble.append(Data("\r\n".utf8))
        }
        preamble.append(Data("--\(boundary)\r\n".utf8))
        preamble.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(escapeQuotedParameter(filename))\"\r\n".utf8))
        // `mimeType` is a client-supplied Content-Type value; strip CR/LF so a
        // crafted value can't inject additional headers. (Quotes are legal in
        // Content-Type parameters, so they're left intact.)
        let safeMimeType = mimeType.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        preamble.append(Data("Content-Type: \(safeMimeType)\r\n\r\n".utf8))
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

        Thread.detachNewThread { [preamble] in
            defer {
                output.close()
                try? fileHandle.close()
            }
            _ = Self.writeMultipartBody(
                fileHandle: fileHandle, fileSize: fileSize,
                preamble: preamble, epilogue: epilogue, to: output
            )
        }

        return (inputStream, contentLength)
    }

    /// Writes the multipart body — preamble, then the file's bytes, then the
    /// closing boundary — to `output`, returning `true` only if all of it was
    /// written.
    ///
    /// Returns `false` **without** writing the closing boundary if the file can't
    /// be fully read: a mid-stream read error, or the file ending short of the
    /// `fileSize` the caller measured (it shrank since). The request's
    /// Content-Length reflects that measured size, so a short body can't be
    /// dressed up as a complete multipart — it fails the upload rather than
    /// silently corrupting it, and the real cause is logged instead of swallowed.
    /// (`false` is also returned on a write failure — e.g. the consumer closing
    /// the stream — matching the preamble/chunk write checks.)
    static func writeMultipartBody(
        fileHandle: FileHandle,
        fileSize: Int,
        preamble: Data,
        epilogue: Data,
        to output: OutputStream
    ) -> Bool {
        guard writeAll(preamble, to: output) else { return false }

        var remaining = fileSize
        while remaining > 0 {
            let chunkSize = min(65_536, remaining)
            let chunk: Data
            do {
                chunk = try fileHandle.read(upToCount: chunkSize) ?? Data()
            } catch {
                Logger.mediaUpload.error("Reading the upload file failed mid-stream: \(error)")
                return false
            }
            guard !chunk.isEmpty else {
                // The file ended before `fileSize` bytes — it shrank since we
                // measured it. Abort rather than emit a truncated multipart.
                Logger.mediaUpload.error("Upload file ended \(remaining) bytes short of its measured size")
                return false
            }
            guard writeAll(chunk, to: output) else { return false }
            remaining -= chunk.count
        }

        return writeAll(epilogue, to: output)
    }

    /// Escapes a client-supplied value for a quoted `Content-Disposition`
    /// parameter (`name`/`filename`). Percent-encodes CR, LF, and `"` so a crafted
    /// filename or field name can't break the header line or inject an extra
    /// multipart part — matching WHATWG's `multipart/form-data` field serialization.
    private static func escapeQuotedParameter(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\n", with: "%0A")
            .replacingOccurrences(of: "\"", with: "%22")
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
