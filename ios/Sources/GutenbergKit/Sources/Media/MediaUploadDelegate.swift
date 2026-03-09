import Foundation

/// Result of a successful media upload to the remote WordPress server.
///
/// This structure matches the format expected by Gutenberg's `onFileChange` callback.
public struct MediaUploadResult: Codable, Sendable {
  public let id: Int
  public let url: String
  public let alt: String
  public let caption: String
  public let title: String
  public let mime: String
  public let type: String
  public let width: Int?
  public let height: Int?

  public init(id: Int, url: String, alt: String = "", caption: String = "", title: String, mime: String, type: String, width: Int? = nil, height: Int? = nil) {
    self.id = id
    self.url = url
    self.alt = alt
    self.caption = caption
    self.title = title
    self.mime = mime
    self.type = type
    self.width = width
    self.height = height
  }
}

/// Protocol for customizing media upload behavior.
///
/// The native host app can provide an implementation to resize images,
/// transcode video, or use its own upload service. Default implementations
/// pass files through unchanged and upload via the WordPress REST API.
public protocol MediaUploadDelegate: AnyObject, Sendable {
  /// Process a file before upload (e.g., resize image, transcode video).
  /// Return the URL of the processed file, or the original URL for passthrough.
  func processFile(at url: URL, mimeType: String) async throws -> URL

  /// Upload a processed file to the remote WordPress site.
  /// Return the Gutenberg-compatible media result, or `nil` to use the default uploader.
  func uploadFile(at url: URL, mimeType: String, filename: String) async throws -> MediaUploadResult?
}

/// Default implementations.
extension MediaUploadDelegate {
  public func processFile(at url: URL, mimeType: String) async throws -> URL {
    url
  }

  public func uploadFile(at url: URL, mimeType: String, filename: String) async throws -> MediaUploadResult? {
    nil
  }
}
