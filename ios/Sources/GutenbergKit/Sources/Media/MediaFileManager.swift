import Foundation
import OSLog
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Manages media files for the editor, handling imports, storage, and cleanup.
///
/// Files are stored in the Library/GutenbergKit/Uploads directory and served via
/// a custom `gbk-media-file://` URL scheme. Old files are automatically cleaned up.
actor MediaFileManager {
    /// Shared instance for app-wide media management
    static let shared = MediaFileManager()

    private let fileManager = FileManager.default
    private let rootURL: URL
    private let uploadsDirectory: URL

    /// Where imported media lives: `gbk-media-file:///Uploads/<name>` names
    /// `<root>/Uploads/<name>`.
    static let defaultRootURL = URL.libraryDirectory.appendingPathComponent("GutenbergKit")

    init(rootURL: URL = MediaFileManager.defaultRootURL) {
        self.rootURL = rootURL
        self.uploadsDirectory = self.rootURL.appendingPathComponent("Uploads")
        Task {
            await cleanupOldFiles()
        }
    }

    /// Imports a photo picker item and saves it to the uploads directory.
    ///
    /// - Returns: MediaInfo with a `gbk-media-file://` URL and detected media type
    func `import`(_ item: PhotosPickerItem) async throws -> MediaInfo {
        let data: Data?
        do {
            data = try await item.loadTransferable(type: Data.self)
        } catch {
            Logger.media.error("Failed to load picker item \(item.supportedContentTypes): \(error)")
            throw error
        }
        guard let data else {
            Logger.media.error("Picker returned no data for item \(item.supportedContentTypes)")
            throw URLError(.unknown)
        }
        let contentType = item.supportedContentTypes.first
        let fileExtension = contentType?.preferredFilenameExtension ?? "jpeg"

        let fileURL = try await writeData(data, withExtension: fileExtension)
        return MediaInfo(url: fileURL.absoluteString, type: contentType?.preferredMIMEType)
    }

    /// Saves media data to the uploads directory and returns a URL with a
    /// custom scheme.
    func writeData(_ data: Data, withExtension ext: String) async throws -> URL {
        let fileName = "\(UUID().uuidString).\(ext)"
        let destinationURL = uploadsDirectory.appendingPathComponent(fileName)

        try fileManager.createDirectory(at: uploadsDirectory, withIntermediateDirectories: true)
        try data.write(to: destinationURL)

        return URL(string: "\(MediaFileSchemeHandler.scheme):///Uploads/\(fileName)")!
    }

    /// The file a `gbk-media-file` URL names, or `nil` when the URL's path would
    /// resolve outside `root` — a `..` segment, for instance, which the page controls.
    nonisolated static func fileURL(for url: URL, root: URL = defaultRootURL) -> URL? {
        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        let candidate = root.appending(path: url.path(percentEncoded: false)).standardizedFileURL
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard candidate.path(percentEncoded: false).hasPrefix(prefix) else {
            return nil
        }
        return candidate
    }

    /// Cleans up files older than 2 days
    private func cleanupOldFiles() {
        let sevenDaysAgo = Date().addingTimeInterval(-2 * 24 * 60 * 60)

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: uploadsDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )

            for fileURL in contents {
                if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                   let creationDate = attributes[.creationDate] as? Date,
                   creationDate < sevenDaysAgo {
                    try? fileManager.removeItem(at: fileURL)
                }
            }
        } catch {
#if DEBUG
            print("Failed to clean up old files: \(error)")
#endif
        }
    }
}
