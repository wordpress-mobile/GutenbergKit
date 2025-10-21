import Foundation

/// Represents a configuration item for the editor
enum ConfigurationItem: Codable, Identifiable {
    case bundledEditor
    case remoteEditor(RemoteEditorConfiguration)

    var id: String {
        switch self {
        case .bundledEditor:
            return "bundled"
        case .remoteEditor(let config):
            return config.id
        }
    }

    var displayName: String {
        switch self {
        case .bundledEditor:
            return "Bundled Editor"
        case .remoteEditor(let config):
            return config.name
        }
    }
}

/// Configuration for a remote editor
struct RemoteEditorConfiguration: Codable, Identifiable {
    let id: String
    let name: String
    let siteUrl: String
    let siteApiRoot: String
    let authHeader: String

    init(name: String, siteUrl: String, siteApiRoot: String, authHeader: String) {
        self.id = UUID().uuidString
        self.name = name
        self.siteUrl = siteUrl
        self.siteApiRoot = siteApiRoot
        self.authHeader = authHeader
    }
}
