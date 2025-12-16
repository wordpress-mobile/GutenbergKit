import Foundation
import GutenbergKit

/// Represents a configuration item for the editor
enum ConfigurationItem: Codable, Identifiable, Equatable, Hashable {
    case bundledEditor
    case editorConfiguration(ConfiguredEditor)

    var id: String {
        switch self {
        case .bundledEditor:
            return "bundled"
        case .editorConfiguration(let config):
            return config.id
        }
    }

    var displayName: String {
        switch self {
        case .bundledEditor:
            return "Bundled Editor"
        case .editorConfiguration(let config):
            return config.name
        }
    }
}

struct RunnableEditor: Equatable, Hashable {
    let configuration: EditorConfiguration
    let dependencies: EditorDependencies?
}

/// Configuration for an editor with site integration
struct ConfiguredEditor: Codable, Identifiable, Equatable, Hashable {
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
