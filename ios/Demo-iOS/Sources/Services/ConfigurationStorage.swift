import Foundation

/// Manages persistence of editor configurations
class ConfigurationStorage: ObservableObject {
    private let userDefaults: UserDefaults
    private let configurationsKey = "saved_configurations"

    @Published
    var editorConfigurations: [ConfigurationItem] = []

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// Load saved configurations from storage
    ///
    /// Includes the bundled editor
    @discardableResult
    func loadConfigurations() -> [ConfigurationItem] {
        guard let data = userDefaults.data(forKey: configurationsKey) else {
            return []
        }

        do {
            let configs = try JSONDecoder().decode([ConfiguredEditor].self, from: data)
            self.editorConfigurations = configs.map { .editorConfiguration($0) }
            return self.editorConfigurations
        } catch {
            NSLog("Failed to decode configurations: \(error)")
            return []
        }
    }

    /// Save configurations to storage
    func saveConfigurations(_ configurations: [ConfigurationItem]) {
        let configs = configurations.compactMap { item -> ConfiguredEditor? in
            if case .editorConfiguration(let config) = item {
                return config
            }
            return nil
        }

        do {
            let data = try JSONEncoder().encode(configs)
            userDefaults.set(data, forKey: configurationsKey)
        } catch {
            NSLog("Failed to encode configurations: \(error)")
        }
    }

    /// Add a configuration to storage
    func addConfiguration(_ configuration: ConfigurationItem) {
        self.editorConfigurations.append(configuration)
        self.saveConfigurations(self.editorConfigurations)
        self.loadConfigurations()
    }

    /// Delete configuration from storage
    func deleteConfiguration(_ configuration: ConfigurationItem) {
        guard let ix = self.editorConfigurations.firstIndex(where: { $0.id == configuration.id }) else {
            return
        }
        self.editorConfigurations.remove(at: ix)

        self.saveConfigurations(self.editorConfigurations)
        self.loadConfigurations()
    }
}
