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
