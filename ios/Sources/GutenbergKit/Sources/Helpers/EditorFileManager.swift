import Foundation
import UniformTypeIdentifiers

/// Manages editor files and media uploads in the Documents directory
actor EditorFileManager {
    static let shared = EditorFileManager()
    
    private let fileManager = FileManager.default
    
    /// Base directory for all GutenbergKit files
    let rootURL: URL
    
    /// Uploads directory URL
    private let uploadsDirectory: URL

    init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            self.rootURL = URL.libraryDirectory.appendingPathComponent("GutenbergKit")
        }
        self.uploadsDirectory = self.rootURL.appendingPathComponent("Uploads")
        
        // Create directories synchronously during init
        try? fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: self.uploadsDirectory, withIntermediateDirectories: true)

        // Schedule cleanup of old files
        Task {
            await cleanupOldFiles()
        }
    }

    /// Saves media data to the uploads directory and returns its custom scheme URL
    func saveMediaData(_ data: Data, withExtension ext: String) async throws -> URL {
        let fileName = "\(UUID().uuidString).\(ext)"
        let destinationURL = uploadsDirectory.appendingPathComponent(fileName)
        
        try data.write(to: destinationURL)

        // Return custom scheme URL: gbk-file:///Uploads/filename.ext
        return URL(string: "\(EditorFileSchemeHandler.scheme):///Uploads/\(fileName)")!
    }
    
    /// Gets URLResponse and data for a gbk-file URL
    func getResponse(for url: URL) async throws -> (URLResponse, Data) {
        // Convert `gbk-file:///Uploads/filename.jpg` to actual file path
        let path = url.path
        let fileURL = rootURL.appendingPathComponent(path)

        let data = try Data(contentsOf: fileURL)

        let headers = [
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
            "Access-Control-Allow-Headers": "*",
            "Cache-Control": "no-cache"
        ]
        
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            throw URLError(.unknown)
        }

        return (response, data)
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
            print("Failed to clean up old files: \(error)")
        }
    }
}
