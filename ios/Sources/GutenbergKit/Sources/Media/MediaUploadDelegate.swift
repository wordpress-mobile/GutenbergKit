import Foundation

/// A raw response from the WordPress REST API media endpoint.
///
/// GutenbergKit relays this to the editor verbatim — it does not interpret the
/// body. The editor therefore receives the exact attachment object (on success)
/// or WordPress REST error object (on failure) it would get from a direct
/// upload, so every consumer — image sub-sizes, attachment links, error notices —
/// behaves identically to a non-native upload.
public struct MediaUploadResponse: Sendable {
    /// The HTTP status code WordPress (or the host's upload service) returned.
    public let statusCode: Int

    /// The raw response body — a WordPress REST attachment on success, or a
    /// WordPress REST error object (`{ "code", "message", "data" }`) on failure.
    public let body: Data

    /// The response headers to relay to the editor.
    ///
    /// `x-wp-upload-attachment-id` is the one that carries behavior: WordPress
    /// sets it on a failed upload whose attachment row was created before
    /// metadata generation fataled, and the editor's api-fetch middleware reads
    /// it to retry `post-process` and clean up the orphan. Dropping it turns a
    /// recoverable upload into a permanent failure.
    public let headers: [String: String]

    public init(statusCode: Int, body: Data, headers: [String: String] = [:]) {
        self.statusCode = statusCode
        self.body = body
        self.headers = headers
    }
}

/// The result of a delegate's ``MediaUploadDelegate/processFile(at:mimeType:filename:)``.
public enum ProcessedProxyFile: Sendable {
    /// The delegate did not modify the file; the original upload is forwarded
    /// to WordPress unchanged.
    case original

    /// The delegate produced a file to upload, along with its MIME type and
    /// filename. Both are used verbatim, so a format change (e.g. transcoding
    /// MOV to MP4, or an in-place EXIF strip) must report the resulting type and
    /// filename for WordPress to store the file correctly.
    case processed(URL, mimeType: String, filename: String)
}

/// Protocol for customizing media upload behavior.
///
/// The native host app can provide an implementation to resize images,
/// transcode video, or use its own upload service. Default implementations
/// pass files through unchanged and upload via the WordPress REST API.
public protocol MediaUploadDelegate: AnyObject, Sendable {
    /// Whether this delegate might handle a file with the given metadata — either
    /// processing it (``processFile(at:mimeType:filename:)``) or uploading it
    /// itself (``uploadFile(at:mimeType:filename:)``).
    ///
    /// A cheap, metadata-only gate the server consults *before* materializing the
    /// upload to a temp file. Return `false` to decline a file by type — e.g. an
    /// image-only delegate returning `false` for a video — so the server forwards
    /// the original upload to WordPress without first copying a file the delegate
    /// won't touch. Because it gates the temp-file copy needed by *both*
    /// `processFile` and `uploadFile`, return `true` for any file the delegate
    /// will either process or upload itself.
    ///
    /// Defaults to `true`: every file is materialized and the full pipeline runs.
    /// A `true` here is not a commitment — `processFile` may still return
    /// `.original` after inspecting the file's contents.
    func handlesFile(ofType mimeType: String, named filename: String) -> Bool

    /// Process a file before upload (e.g., resize image, transcode video).
    ///
    /// Return ``ProcessedProxyFile/original`` to upload the file unchanged, or
    /// ``ProcessedProxyFile/processed(_:mimeType:filename:)`` with the processed
    /// file and its metadata. When the format changes, report the new mimeType
    /// and filename so WordPress stores it with the correct extension and type.
    func processFile(at url: URL, mimeType: String, filename: String) async throws -> ProcessedProxyFile

    /// Upload a processed file to the remote WordPress site.
    ///
    /// Return the raw WordPress response (status code + body), which GutenbergKit
    /// relays to the editor unchanged, or `nil` to use the default uploader. A
    /// host that uploads to WordPress should return the exact response it
    /// received so the editor sees a complete attachment object.
    func uploadFile(at url: URL, mimeType: String, filename: String) async throws -> MediaUploadResponse?
}

/// Default implementations.
extension MediaUploadDelegate {
    public func handlesFile(ofType mimeType: String, named filename: String) -> Bool {
        true
    }

    public func processFile(at url: URL, mimeType: String, filename: String) async throws -> ProcessedProxyFile {
        .original
    }

    public func uploadFile(at url: URL, mimeType: String, filename: String) async throws -> MediaUploadResponse? {
        nil
    }
}
