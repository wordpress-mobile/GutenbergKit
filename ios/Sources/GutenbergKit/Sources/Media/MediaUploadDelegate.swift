import Foundation

/// A raw response from the WordPress REST API media endpoint.
///
/// GutenbergKit relays this to the editor verbatim — it does not interpret the
/// body. The editor therefore receives the exact attachment object (on success)
/// or WordPress REST error object (on failure) it would get from a direct
/// upload, so every consumer — image sub-sizes, attachment links, error notices —
/// behaves identically to a non-native upload.
struct MediaUploadResponse: Sendable {
    /// The HTTP status code WordPress (or the host's upload service) returned.
    let statusCode: Int

    /// The raw response body — a WordPress REST attachment on success, or a
    /// WordPress REST error object (`{ "code", "message", "data" }`) on failure.
    let body: Data

    /// The response headers to relay to the editor.
    ///
    /// `x-wp-upload-attachment-id` is the one that carries behavior: WordPress
    /// sets it on a failed upload whose attachment row was created before
    /// metadata generation fataled, and the editor's api-fetch middleware reads
    /// it to retry `post-process` and clean up the orphan. Dropping it turns a
    /// recoverable upload into a permanent failure.
    let headers: [String: String]

    init(statusCode: Int, body: Data, headers: [String: String] = [:]) {
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

/// Transforms media before GutenbergKit delivers it.
///
/// A delegate only changes *bytes* — GutenbergKit still uploads the result to the
/// configured site and owns the whole lifecycle (retries, cleanup). Because it never
/// performs the upload itself, it cannot deliver media to the wrong place. Set
/// ``EditorViewController/mediaUploadDelegate`` to resize images, transcode video,
/// strip EXIF, etc.
///
/// This is the safe, common extension point: most hosts want only this. To perform
/// the upload yourself, conform to ``MediaUploader`` instead.
public protocol MediaUploadDelegate: AnyObject, Sendable {
    /// Whether this delegate might transform a file with the given metadata.
    ///
    /// A cheap, metadata-only gate the server consults *before* materializing the
    /// upload to a temp file. Return `false` to decline a file by type — e.g. an
    /// image-only delegate returning `false` for a video — so the server forwards
    /// the original upload to WordPress without first copying a file the delegate
    /// won't touch.
    ///
    /// Only consulted when no ``MediaUploader`` is set: an uploader takes over
    /// delivery for every file, so there is no passthrough to decline to.
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
}

/// Default implementations.
extension MediaUploadDelegate {
    public func handlesFile(ofType mimeType: String, named filename: String) -> Bool {
        true
    }

    public func processFile(at url: URL, mimeType: String, filename: String) async throws -> ProcessedProxyFile {
        .original
    }
}

/// One of the editor's non-file form fields, as sent with a media upload.
///
/// A named type rather than a `(name, value)` tuple: tuples are not nominal, so a
/// tuple-typed property would permanently block `Equatable`/`Hashable`/`Codable`
/// synthesis on ``MediaUpload`` — including inside GutenbergKit, and not fixable
/// later without a source break for every host.
public struct MediaUploadField: Sendable, Hashable, Codable {
    /// The field name, e.g. `post`. Not unique — a `field[]` array repeats it.
    public let name: String

    /// The field's value, decoded as UTF-8.
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// Everything a ``MediaUploader`` needs to reproduce a native upload: the file to
/// send, its metadata, the editor's non-file form fields, and the request's query.
public struct MediaUpload: Sendable {
    /// The file to upload — already processed, if a ``MediaUploadDelegate`` ran.
    public let fileURL: URL

    /// The file's MIME type.
    public let mimeType: String

    /// The file's name.
    public let filename: String

    /// The editor's non-file form fields, in order, each decoded as UTF-8 — most
    /// importantly `post`, the parent post's ID, without which the attachment is
    /// created unattached. A list, not a dictionary, so repeated field names (e.g. a
    /// `field[]` array) survive verbatim. Send each as a form part on your
    /// `POST /wp/v2/media`, in the given order.
    public let fields: [MediaUploadField]

    /// The request's query string (leading `?`, e.g. `?_embed=wp:featuredmedia`), or
    /// empty. Carry it on your request so the editor gets the response it expects.
    public let query: String

    public init(fileURL: URL, mimeType: String, filename: String, fields: [MediaUploadField], query: String) {
        self.fileURL = fileURL
        self.mimeType = mimeType
        self.filename = filename
        self.fields = fields
        self.query = query
    }
}

/// Takes over *performing* a media upload — on the host's own stack: its own
/// networking (say, to log every request), a background session, an offline queue,
/// a resumable transport, its own retry policy.
///
/// This is a choice of *who executes the requests*, not where they go: an uploader
/// and GutenbergKit's internal media client both target the same configured site.
/// Setting ``EditorViewController/mediaUploader`` makes the host own that upload
/// end-to-end — the request, its own retries, and its recovery and cleanup — with
/// GutenbergKit out of the network entirely. Because the host does the retries
/// itself, there's no raw response left for the editor to retry behind it. The
/// attachment you return lives on that same configured site, where the editor reads
/// and updates it by ID.
public protocol MediaUploader: AnyObject, Sendable {
    /// Upload a (possibly processed) file and return the finished WordPress
    /// attachment JSON the editor inserts — the same object a direct
    /// `POST /wp/v2/media` returns. Return only once the upload is genuinely done,
    /// or `throw` on terminal failure: a returned value is taken as a completed
    /// attachment, and there is no GutenbergKit recovery behind you.
    ///
    /// The ``MediaUpload`` carries the file plus the editor's form fields (e.g.
    /// `post`) and query — send them all so the created attachment matches a native
    /// upload rather than landing as an unattached orphan.
    ///
    /// That recovery is yours to run. When `POST /wp/v2/media` fatals in server-side
    /// post-processing it returns a 5xx carrying the attachment's ID in
    /// `x-wp-upload-attachment-id` — the attachment exists but is unfinished. Don't
    /// re-upload; drive `POST /wp/v2/media/<id>/post-process` to completion, the way
    /// core recovers its own uploads (up to 5 attempts), then return the finished
    /// attachment.
    ///
    /// Owning the upload means owning cleanup on the server too: if post-process
    /// can't be recovered, force-delete the orphan
    /// (`DELETE /wp/v2/media/<id>?force=true`) before you `throw`, or it stays on the
    /// site — neither GutenbergKit nor the editor cleans up behind you.
    func upload(_ upload: MediaUpload) async throws -> Data
}
