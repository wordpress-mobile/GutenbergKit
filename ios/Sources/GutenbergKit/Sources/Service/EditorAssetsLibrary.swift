import Foundation

/// Wrapper around EditorService to provide manifest content for the editor
actor EditorAssetsLibrary {
    let service: EditorService
    let configuration: EditorConfiguration

    init(service: EditorService, configuration: EditorConfiguration) {
        self.service = service
        self.configuration = configuration
    }

    /// Returns the editor assets manifest content as Data, ready to be sent to the web view
    func manifestContentForEditor() async throws -> Data {
        let jsonString = try await service.getProcessedManifest()
        guard let data = jsonString.data(using: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return data
    }
}
