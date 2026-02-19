import Foundation
import GutenbergKit

/// Represents a configuration item for the editor
enum ConfigurationItem: Codable, Identifiable, Equatable, Hashable {
    case bundledEditor
    case localWordPress
    case editorConfiguration(ConfiguredEditor)

    var id: String {
        switch self {
        case .bundledEditor:
            return "bundled"
        case .localWordPress:
            return "local-wordpress"
        case .editorConfiguration(let config):
            return config.id
        }
    }

    var displayName: String {
        switch self {
        case .bundledEditor:
            return "Bundled Editor"
        case .localWordPress:
            return "Local WordPress"
        case .editorConfiguration(let config):
            return config.name
        }
    }
}

struct RunnableEditor: Equatable, Hashable {
    let configuration: EditorConfiguration
    let dependencies: EditorDependencies?
}

/// Credentials loaded from the wp-env setup script output
struct LocalWordPressCredentials: Codable {
    let siteUrl: String
    let siteApiRoot: String
    let username: String
    let appPassword: String
    let authHeader: String

    /// Loads credentials from the file path specified in the `WP_ENV_CREDENTIALS_PATH` environment variable.
    static func load() -> LocalWordPressCredentials? {
        guard let path = ProcessInfo.processInfo.environment["WP_ENV_CREDENTIALS_PATH"] else {
            return nil
        }

        guard let data = FileManager.default.contents(atPath: path) else {
            return nil
        }

        return try? JSONDecoder().decode(LocalWordPressCredentials.self, from: data)
    }
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
