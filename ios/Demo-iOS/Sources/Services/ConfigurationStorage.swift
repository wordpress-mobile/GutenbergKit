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

        try self.signInToWpComFromLaunchArgumentsIfNeeded()
    }

    /// Stores the WordPress.com site named by the `-wpcom-token`, `-wpcom-site-id` and `-wpcom-site-host` launch
    /// arguments as an account, replacing any account already stored for that site. Lets a Simulator be signed in
    /// without the OAuth flow – see `bin/demo-app-login.sh`.
    ///
    /// Only called from `init`, so it runs at most once per process — deleting the site doesn't immediately add it
    /// back from the still-present launch arguments.
    private func signInToWpComFromLaunchArgumentsIfNeeded() throws {
        guard
            let token = Self.launchArgument("-wpcom-token"),
            let siteId = Self.launchArgument("-wpcom-site-id").flatMap(UInt64.init),
            let siteHost = Self.launchArgument("-wpcom-site-host")
        else {
            return
        }

        let siteApiRoot = Account.wpComSiteApiRoot(siteId: siteId)
        for account in try accountRepository.all() where account.isWpCom() && account.siteApiRoot == siteApiRoot {
            try accountRepository.remove(id: account.id())
        }

        _ = try accountRepository.store(
            account: .wpCom(id: 0, username: siteHost, token: token, siteApiRoot: siteApiRoot)
        )
    }

    /// The value that follows `name` in the launch arguments.
    ///
    /// Read from the raw process arguments rather than `UserDefaults`, which parses argument values as property
    /// lists and could mangle a token containing plist syntax.
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
