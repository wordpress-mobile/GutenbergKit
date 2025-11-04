import Foundation
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

    init(rootURL: URL = URL.libraryDirectory.appendingPathComponent("GutenbergKit")) {
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
        guard let data = try await item.loadTransferable(type: Data.self) else {
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

    /// Gets URLResponse and data for a `gbk-media-file` URL
    func getData(for url: URL) async throws -> Data {
        // Convert `gbk-media-file://Uploads/filename.jpg` to actual file path
        let fileURL = rootURL.appendingPathComponent(url.path)
        return try Data(contentsOf: fileURL)
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
