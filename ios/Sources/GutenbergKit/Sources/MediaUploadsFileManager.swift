import Foundation

/// Actor responsible for managing media uploads in an isolated context
actor MediaUploadsFileManager {
    private let fileManager = FileManager.default
    private let uploadsDirectory: URL
    
    init(baseDirectory: URL) {
        self.uploadsDirectory = baseDirectory.appendingPathComponent("Uploads")
        
        // Create uploads directory if needed
        try? fileManager.createDirectory(at: uploadsDirectory, withIntermediateDirectories: true)
        
        // Schedule cleanup of old files
        Task {
            await cleanupOldFiles()
        }
    }
    
    /// Saves a media file to the uploads directory and returns its file:// URL
    func saveMediaFile(from sourceURL: URL, withExtension ext: String) async throws -> URL {
        let fileName = "\(UUID().uuidString).\(ext)"
        let destinationURL = uploadsDirectory.appendingPathComponent(fileName)
        
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        
        return destinationURL
    }
    
    /// Saves media data to the uploads directory and returns its file:// URL
    func saveMediaData(_ data: Data, withExtension ext: String) async throws -> URL {
        let fileName = "\(UUID().uuidString).\(ext)"
        let destinationURL = uploadsDirectory.appendingPathComponent(fileName)
        
        try data.write(to: destinationURL)
        
        return destinationURL
    }
    
    /// Removes a specific upload file
    func removeUploadFile(at url: URL) {
        guard url.path.hasPrefix(uploadsDirectory.path) else { return }
        try? fileManager.removeItem(at: url)
    }
    
    /// Cleans up all upload files
    func cleanupAllUploads() {
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: uploadsDirectory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            
            for fileURL in contents {
                try? fileManager.removeItem(at: fileURL)
            }
        } catch {
            print("Failed to cleanup uploads: \(error)")
        }
    }
    
    /// Cleans up files older than 7 days
    private func cleanupOldFiles() {
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        
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
            print("Failed to clean up old files: \(error)")
        }
    }
}
