import Foundation

/// Manages persistence of remote editor configurations
class ConfigurationStorage {
    private let userDefaults: UserDefaults
    private let configurationsKey = "saved_configurations"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// Load saved configurations from storage
    func loadConfigurations() -> [ConfigurationItem] {
        guard let data = userDefaults.data(forKey: configurationsKey) else {
            return []
        }

        do {
            let remoteConfigs = try JSONDecoder().decode([RemoteEditorConfiguration].self, from: data)
            return remoteConfigs.map { .remoteEditor($0) }
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
}
