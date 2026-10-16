import Foundation
import OSLog

/// A file that native code holds and is about to upload.
struct MediaUploadFile: Sendable, Equatable {
    /// Where the file is on disk. The service never moves or deletes it.
    let url: URL
    let mimeType: String
    let filename: String
}

/// Delivers native media uploads and deletes to WordPress.
///
/// A protocol so the transport that carries files to native code can be tested
/// without a network behind it.
protocol MediaUploading: Sendable {
    /// Uploads `file` and returns WordPress's response verbatim, non-2xx included.
    ///
    /// Throws only when there is no response to relay — the processor or uploader
    /// threw, the request failed at the transport layer, or the task was cancelled.
    func upload(_ file: MediaUploadFile, fields: [MediaUploadField], query: String) async throws -> MediaUploadResponse

    /// Deletes an attachment and returns WordPress's response verbatim.
    func delete(attachmentId: String, query: String) async throws -> MediaUploadResponse
}

/// Runs the host's ``MediaProcessor``, then delivers the result through the host's
/// ``MediaUploader`` or GutenbergKit's own ``InternalMediaClient``.
///
/// Independent of how the file reached native code: the editor's page hands files over
/// through ``MediaUploadSchemeHandler``, and the block inserter imports them directly.
/// Both end here.
///
/// Holds the processor and uploader **strongly**, so a processor that admitted a file
/// processes it and an uploader that was handed one delivers it, even if the editor
/// drops its references mid-upload. The editor owns the service through the scheme
/// handler, which it releases in ``EditorViewController/stopMediaHandling()``.
struct MediaUploadService: MediaUploading {
    let processor: (any MediaProcessor)?
    let uploader: (any MediaUploader)?
    let internalClient: InternalMediaClient?

    func upload(_ file: MediaUploadFile, fields: [MediaUploadField], query: String) async throws -> MediaUploadResponse {
        // Ask the processor — from metadata alone — whether it will touch a file like
        // this. A declined file skips `processFile`: handing it one anyway would break
        // the contract the gate documents. With an uploader set the file is still
        // delivered, just unprocessed.
        let processorWantsFile = processor?.handlesFile(ofType: file.mimeType, named: file.filename) ?? false

        let processed: ProcessedProxyFile
        if let processor, processorWantsFile {
            processed = try await processor.processFile(at: file.url, mimeType: file.mimeType, filename: file.filename)
        } else {
            processed = .original
        }

        // `.processed` uses the processor's values verbatim, so a format change is
        // reported to WordPress.
        let delivered: MediaUploadFile
        switch processed {
        case .original:
            delivered = file
        case let .processed(url, mimeType, filename):
            delivered = MediaUploadFile(url: url, mimeType: mimeType, filename: filename)
        }

        // A file the processor produced is ours to clean up — uploaded on success,
        // abandoned on failure. Here rather than in the caller so the throw paths are
        // covered too.
        defer {
            if delivered.url != file.url {
                try? FileManager.default.removeItem(at: delivered.url)
            }
        }

        // The editor was torn down, or the page gave up on this upload, while we
        // processed. Don't start an upload whose response nobody will read — it would
        // create an attachment neither GutenbergKit nor the host knows to clean up.
        // Checked here rather than left to the HTTP client so it holds for a
        // host-injected `URLSessionProtocol` that ignores cancellation.
        try Task.checkCancellation()

        // An uploader owns delivery on the host's stack and returns the finished
        // attachment (or throws); GutenbergKit relays it as a success and runs no
        // recovery behind it.
        if let uploader {
            let upload = MediaUpload(
                fileURL: delivered.url,
                mimeType: delivered.mimeType,
                filename: delivered.filename,
                fields: fields,
                query: query
            )
            let attachment = try await uploader.upload(upload)
            return MediaUploadResponse(statusCode: 201, body: attachment)
        }

        guard let internalClient else {
            throw UploadError.noUploader
        }
        return try await internalClient.upload(
            fileURL: delivered.url,
            mimeType: delivered.mimeType,
            filename: delivered.filename,
            fields: fields,
            query: query
        )
    }

    func delete(attachmentId: String, query: String) async throws -> MediaUploadResponse {
        guard let internalClient else {
            throw UploadError.noUploader
        }
        return try await internalClient.deleteMedia(attachmentId: attachmentId, query: query)
    }
}
