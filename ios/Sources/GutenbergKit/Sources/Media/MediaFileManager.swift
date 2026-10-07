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
            Self.removeStaleWebKitUploadCopies()
        }
    }

    /// Imports a photo picker item into the uploads directory.
    ///
    /// Asks Photos for the item as a file and copies it, which on APFS is a clone: a
    /// 1 GB video costs neither memory nor disk. The file keeps the name Photos gave
    /// it, so the attachment WordPress creates is named after it. An item Photos can
    /// only hand over as data is written from memory instead.
    ///
    /// - Returns: MediaInfo with a `gbk-media-file://` URL and detected media type
    func `import`(_ item: PhotosPickerItem) async throws -> MediaInfo {
        do {
            if let picked = try await item.loadTransferable(type: PickedFile.self) {
                defer { try? fileManager.removeItem(at: picked.url.deletingLastPathComponent()) }
                let imported = try adopt(picked.url, mimeType: picked.mimeType ?? item.supportedContentTypes.first?.preferredMIMEType)
                return imported.mediaInfo
            }
        } catch {
            Logger.media.error("Failed to load picker item \(item.supportedContentTypes) as a file, loading its data instead: \(error)")
        }

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

    /// Imports a file that is already on disk — a video the camera recorded — by
    /// copying it into the uploads directory under its own name.
    func importFile(at url: URL) throws -> MediaInfo {
        try adopt(url, mimeType: nil).mediaInfo
    }

    /// Copies `url` into its own directory under the uploads directory.
    private func adopt(_ url: URL, mimeType: String?) throws -> ImportedMedia {
        let directory = uploadsDirectory.appending(component: UUID().uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(component: MediaUploadSessionStore.sanitizeFilename(url.lastPathComponent))
        try fileManager.copyItem(at: url, to: destination)
        return ImportedMedia(
            fileURL: destination,
            mimeType: mimeType ?? Self.mimeType(forExtension: destination.pathExtension),
            mediaURL: try Self.mediaURL(forPath: "/Uploads/\(directory.lastPathComponent)/\(destination.lastPathComponent)")
        )
    }

    /// A `gbk-media-file:` URL for a path under the root, percent-encoded so a
    /// filename with spaces or non-ASCII characters survives.
    nonisolated static func mediaURL(forPath path: String) throws -> URL {
        var components = URLComponents()
        components.scheme = MediaFileSchemeHandler.scheme
        components.host = ""
        components.path = path
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }

    /// The `gbk-media-file:` URL that names `fileURL`, or `nil` when the file isn't
    /// under `root` — the inverse of ``fileURL(for:root:)``.
    nonisolated static func mediaURL(forFile fileURL: URL, root: URL = defaultRootURL) -> URL? {
        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        let filePath = fileURL.standardizedFileURL.path(percentEncoded: false)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else { return nil }
        return try? mediaURL(forPath: "/" + filePath.dropFirst(prefix.count))
    }

    nonisolated static func mimeType(forExtension pathExtension: String) -> String {
        UTType(filenameExtension: pathExtension)?.preferredMIMEType ?? "application/octet-stream"
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

extension MediaFileManager {
    /// How long WebKit's copy of an uploaded file is kept.
    static let webKitUploadCopyLifetime: TimeInterval = 2 * 24 * 60 * 60

    /// Deletes the copies WebKit made of files handed to a file input, once they are
    /// older than `age`.
    ///
    /// WebKit copies every file a file input receives — from the system picker or from
    /// ``NativeFileInput`` — into `tmp/WKFileUploadPanel-…`, and never deletes it. The
    /// copy is a clone, so it costs nothing while the original exists; once the
    /// original is gone it holds the file's storage on its own. An upload in flight
    /// reads from that copy, so only old ones are removed.
    nonisolated static func removeStaleWebKitUploadCopies(
        in directory: URL = FileManager.default.temporaryDirectory,
        olderThan age: TimeInterval = webKitUploadCopyLifetime
    ) {
        let cutoff = Date.now.addingTimeInterval(-age)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return }
        for entry in entries where entry.lastPathComponent.hasPrefix("WKFileUploadPanel-") {
            let created = (try? entry.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            if let created, created < cutoff {
                try? FileManager.default.removeItem(at: entry)
            }
        }
    }
}

/// A file imported into the uploads directory.
struct ImportedMedia: Sendable {
    let fileURL: URL
    let mimeType: String
    /// The file's `gbk-media-file:` URL.
    let mediaURL: URL

    var mediaInfo: MediaInfo {
        MediaInfo(url: mediaURL.absoluteString, type: mimeType)
    }
}

/// A picker item received as a file.
///
/// Photos deletes the file it hands over once the import closure returns, so the
/// closure copies it — a clone on APFS — into a staging directory first.
/// Representations are tried in order; `.data` catches everything else.
private struct PickedFile: Transferable {
    let url: URL
    let mimeType: String?

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { try stage($0, as: .movie) }
        FileRepresentation(importedContentType: .image) { try stage($0, as: .image) }
        FileRepresentation(importedContentType: .audio) { try stage($0, as: .audio) }
        FileRepresentation(importedContentType: .data) { try stage($0, as: nil) }
    }

    private static func stage(_ received: ReceivedTransferredFile, as type: UTType?) throws -> PickedFile {
        let directory = FileManager.default.temporaryDirectory
            .appending(component: "GutenbergKit-imports", directoryHint: .isDirectory)
            .appending(component: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(component: received.file.lastPathComponent)
        try FileManager.default.copyItem(at: received.file, to: destination)
        let fromExtension = UTType(filenameExtension: destination.pathExtension)
        return PickedFile(url: destination, mimeType: (fromExtension ?? type)?.preferredMIMEType)
    }
}
