import Foundation

/// Manages editor files and media uploads in the Documents directory
@MainActor
final class EditorFileManager {
    static let shared = EditorFileManager()
    
    private let fileManager = FileManager.default
    
    /// Base directory for all GutenbergKit files
    let gutenbergDirectory: URL
    
    /// Directory for editor files (HTML, JS, CSS)
    let editorDirectory: URL
    
    /// Actor for managing media uploads
    let uploads: MediaUploadsFileManager
    
    private init() {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.gutenbergDirectory = documentsURL.appendingPathComponent("GutenbergKit")
        self.editorDirectory = gutenbergDirectory.appendingPathComponent("Editor")
        self.uploads = MediaUploadsFileManager(baseDirectory: gutenbergDirectory)
        
        // Create directories
        createDirectoriesIfNeeded()
    }
    
    /// Copies editor bundle files to Documents directory if needed
    func copyEditorFilesIfNeeded() throws {
        let bundleEditorURL = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Gutenberg")!
            .deletingLastPathComponent()
        
        // Check if we need to copy files (version check could be added here)
        let indexURL = editorDirectory.appendingPathComponent("index.html")
        if !fileManager.fileExists(atPath: indexURL.path) {
            try copyEditorFiles(from: bundleEditorURL)
        }
    }
    
    /// Returns the URL for the editor index.html in Documents
    var editorIndexURL: URL {
        editorDirectory.appendingPathComponent("index.html")
    }
    
    /// Returns the URL for the remote.html in Documents
    var remoteEditorURL: URL {
        editorDirectory.appendingPathComponent("remote.html")
    }
    
    /// Saves a media file to the uploads directory and returns its file:// URL
    func saveMediaFile(from sourceURL: URL, withExtension ext: String) async throws -> URL {
        try await uploads.saveMediaFile(from: sourceURL, withExtension: ext)
    }
    
    /// Saves media data to the uploads directory and returns its file:// URL
    func saveMediaData(_ data: Data, withExtension ext: String) async throws -> URL {
        try await uploads.saveMediaData(data, withExtension: ext)
    }
    
    /// Removes a specific upload file
    nonisolated func removeUploadFile(at url: URL) {
        Task {
            await uploads.removeUploadFile(at: url)
        }
    }
    
    /// Cleans up all upload files
    nonisolated func cleanupAllUploads() {
        Task {
            await uploads.cleanupAllUploads()
        }
    }
    
    // MARK: - Private Methods
    
    private func createDirectoriesIfNeeded() {
        do {
            try fileManager.createDirectory(at: editorDirectory, withIntermediateDirectories: true)
        } catch {
            print("Failed to create directories: \(error)")
        }
    }
    
    private func copyEditorFiles(from sourceURL: URL) throws {
        // Remove existing editor directory if it exists
        if fileManager.fileExists(atPath: editorDirectory.path) {
            try fileManager.removeItem(at: editorDirectory)
        }
        
        // Create fresh editor directory
        try fileManager.createDirectory(at: editorDirectory, withIntermediateDirectories: true)
        
        // Copy all files from bundle
        let enumerator = fileManager.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        
        guard let enumerator = enumerator else { return }
        
        for case let fileURL as URL in enumerator {
            let relativePath = fileURL.path.replacingOccurrences(of: sourceURL.path + "/", with: "")
            let destinationURL = editorDirectory.appendingPathComponent(relativePath)
            
            // Create intermediate directories
            let destinationDir = destinationURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)
            
            // Copy file
            try fileManager.copyItem(at: fileURL, to: destinationURL)
        }
    }
    
}
