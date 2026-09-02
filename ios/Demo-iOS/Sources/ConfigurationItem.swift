import Foundation
import GutenbergKit
import WordPressAPI

/// Represents a configuration item for the editor
enum ConfigurationItem: Identifiable, Equatable, Hashable {
    case bundledEditor
    case localWordPress
    case account(Account)

    var id: String {
        switch self {
        case .bundledEditor:
            return "bundled"
        case .localWordPress:
            return "local-wordpress"
        case .account(let account):
            return "\(account.id())"
        }
    }

    var displayName: String {
        switch self {
        case .bundledEditor:
            return "Standalone Editor"
        case .localWordPress:
            return "Local WordPress"
        case .account(let account):
            return account.displayName
        }
    }
}

struct RunnableEditor: Equatable, Hashable {
    let configuration: EditorConfiguration
    let dependencies: EditorDependencies?
    let apiClient: WordPressAPI?
    var enableNativeMediaUpload: Bool = true

    init(configuration: EditorConfiguration, dependencies: EditorDependencies?, apiClient: WordPressAPI? = nil, enableNativeMediaUpload: Bool = true) {
        self.configuration = configuration
        self.dependencies = dependencies
        self.apiClient = apiClient
        self.enableNativeMediaUpload = enableNativeMediaUpload
    }

    // `apiClient` is intentionally excluded from `==` and `hash(into:)`:
    // `WordPressAPI` is not `Hashable`/`Equatable` (it owns native Rust state),
    // and two editors with the same configuration but different client
    // instances should be treated as equal for navigation/identity purposes.
    static func == (lhs: RunnableEditor, rhs: RunnableEditor) -> Bool {
        lhs.configuration == rhs.configuration && lhs.dependencies == rhs.dependencies && lhs.enableNativeMediaUpload == rhs.enableNativeMediaUpload
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(configuration)
        hasher.combine(dependencies)
        hasher.combine(enableNativeMediaUpload)
    }
}

/// Credentials loaded from the wp-env setup script output
struct LocalWordPressCredentials: Codable {
    let siteUrl: String
    let siteApiRoot: String
    let username: String
    let appPassword: String
    let authHeader: String

    /// Loads credentials from the file path specified in the `WP_ENV_CREDENTIALS_PATH` environment variable.
    ///
    /// Returns `nil` when the variable is unset or the file cannot be read, so
    /// a misconfigured environment surfaces as the "not configured" message
    /// rather than as a confusing failure against some other site.
    static func load() -> LocalWordPressCredentials? {
        guard let path = ProcessInfo.processInfo.environment["WP_ENV_CREDENTIALS_PATH"],
              let data = FileManager.default.contents(atPath: path),
              let credentials = try? JSONDecoder().decode(LocalWordPressCredentials.self, from: data) else {
            return nil
        }
        return credentials
    }
}

// MARK: - Account Helpers

extension Account {

    var displayName: String {
        switch self {
        case .selfHostedSite(_, let domain, _, _, _):
            return URL(string: domain)?.host ?? domain
        case .wpCom(_, let username, _, _):
            return username.isEmpty ? "WordPress.com" : username
        }
    }

    var authHeader: String {
        switch self {
        case .selfHostedSite(_, _, let username, let password, _):
            let authString = "\(username):\(password)"
            let authData = authString.data(using: .utf8)!
            return "Basic \(authData.base64EncodedString())"
        case .wpCom(_, _, let token, _):
            return "Bearer \(token)"
        }
    }

    var siteApiRoot: String {
        switch self {
        case .selfHostedSite(_, _, _, _, let siteApiRoot):
            return siteApiRoot
        case .wpCom(_, _, _, let siteApiRoot):
            return siteApiRoot
        }
    }

    var siteUrl: String {
        switch self {
        case .selfHostedSite(_, let domain, _, _, _):
            return domain
        case .wpCom(_, _, _, let siteApiRoot):
            return siteApiRoot
        }
    }
}
