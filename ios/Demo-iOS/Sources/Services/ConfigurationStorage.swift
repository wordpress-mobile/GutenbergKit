import Foundation
import WordPressAPI

/// Manages persistence of editor configurations using encrypted account storage
class ConfigurationStorage: ObservableObject {

    let accountRepository: AccountRepository

    @Published
    var editorConfigurations: [ConfigurationItem] = []

    init() throws {
        let rootPath = URL.applicationSupportDirectory.path(percentEncoded: false)
        let transformer = try SecureEnclavePasswordTransformer(applicationName: "gutenbergkit-demo")
        self.accountRepository = try AccountRepository(rootPath: rootPath, passwordTransformer: transformer)

        try self.signInFromLaunchArgumentsIfNeeded()
    }

    /// Stores the sites in the `-accounts` launch argument as accounts, replacing any account already stored for
    /// the same site. Lets a Simulator be signed in without a login flow – see `bin/demo-app-login.sh`.
    ///
    /// Only called from `init`, so it runs at most once per process — deleting a site doesn't immediately add it
    /// back from the still-present launch argument.
    private func signInFromLaunchArgumentsIfNeeded() throws {
        guard
            let json = Self.launchArgument("-accounts"),
            let entries = try? JSONDecoder().decode([LaunchAccount].self, from: Data(json.utf8))
        else {
            return
        }

        for account in entries.compactMap(\.account) {
            for existing in try accountRepository.all() where existing.siteApiRoot == account.siteApiRoot {
                try accountRepository.remove(id: existing.id())
            }

            _ = try accountRepository.store(account: account)
        }
    }

    /// One entry of the `-accounts` launch argument, which is a JSON array: a self-hosted site with its
    /// credentials and REST API root, or a WordPress.com site with a bearer token.
    private struct LaunchAccount: Decodable {
        var siteUrl: String?
        var username: String?
        var password: String?
        var siteApiRoot: String?

        var wpcomToken: String?
        var wpcomSiteId: UInt64?
        var wpcomSiteHost: String?

        var account: Account? {
            if let wpcomToken, let wpcomSiteId, let wpcomSiteHost {
                return .wpCom(
                    id: 0,
                    username: wpcomSiteHost,
                    token: wpcomToken,
                    siteApiRoot: Account.wpComSiteApiRoot(siteId: wpcomSiteId)
                )
            }

            if let siteUrl, let username, let password, let siteApiRoot {
                return .selfHostedSite(
                    id: 0,
                    domain: siteUrl,
                    username: username,
                    password: password,
                    siteApiRoot: siteApiRoot
                )
            }

            return nil
        }
    }

    /// The value that follows `name` in the launch arguments.
    ///
    /// Read from the raw process arguments rather than `UserDefaults`, which parses argument values as property
    /// lists and would not hand back the JSON as it was written.
    private static func launchArgument(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard
            let index = arguments.firstIndex(of: name),
            arguments.indices.contains(index + 1)
        else {
            return nil
        }

        let value = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Load saved configurations from storage
    @discardableResult
    func loadConfigurations() throws -> [ConfigurationItem] {
        let accounts = try accountRepository.all()
        self.editorConfigurations = accounts.map { .account($0) }
        return self.editorConfigurations
    }

    /// Add an account to storage
    func addAccount(_ account: Account) throws {
        _ = try accountRepository.store(account: account)
        try loadConfigurations()
    }

    /// Delete an account from storage
    func deleteAccount(id: UInt64) throws {
        try accountRepository.remove(id: id)
        try loadConfigurations()
    }

    /// Delete configuration from storage
    func deleteConfiguration(_ configuration: ConfigurationItem) throws {
        guard case .account(let account) = configuration else { return }
        try deleteAccount(id: account.id())
    }
}
