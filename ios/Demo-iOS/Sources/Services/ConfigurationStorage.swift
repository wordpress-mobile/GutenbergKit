import Foundation

/// Manages persistence of remote editor configurations
class ConfigurationStorage: ObservableObject {
    private let userDefaults: UserDefaults
    private let configurationsKey = "saved_configurations"

    @Published
    var remoteEditors: [ConfigurationItem] = []

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
            let remoteConfigs = try JSONDecoder().decode([RemoteEditorConfiguration].self, from: data)
            self.remoteEditors = remoteConfigs.map { .remoteEditor($0) }
            return self.remoteEditors
        } catch {
            NSLog("Failed to decode configurations: \(error)")
            return []
        }
    }

    /// Save configurations to storage
    func saveConfigurations(_ configurations: [ConfigurationItem]) {
        let remoteConfigs = configurations.compactMap { item -> RemoteEditorConfiguration? in
            if case .remoteEditor(let config) = item {
                return config
            }
            return nil
        }

        do {
            let data = try JSONEncoder().encode(remoteConfigs)
            userDefaults.set(data, forKey: configurationsKey)
        } catch {
            NSLog("Failed to encode configurations: \(error)")
        }
    }

    /// Add a configuration to storage
    func addConfiguration(_ configuration: ConfigurationItem) {
        self.remoteEditors.append(configuration)
        self.saveConfigurations(self.remoteEditors)
        self.loadConfigurations()
    }

    /// Delete configuration from storage
    func deleteConfiguration(_ configuration: ConfigurationItem) {
        guard let ix = self.remoteEditors.firstIndex(where: { $0.id == configuration.id }) else {
            return
        }
        self.remoteEditors.remove(at: ix)

        self.saveConfigurations(self.remoteEditors)
        self.loadConfigurations()
    }
}
