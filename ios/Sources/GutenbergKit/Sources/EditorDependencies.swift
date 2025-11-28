import Foundation

/// Dependencies fetched from the WordPress REST API required for the editor
struct EditorDependencies: Sendable {
    /// Raw block editor settings from the WordPress REST API
    var editorSettings: String?

    /// Extracts CSS styles from the editor settings JSON string
    func extractThemeStyles() -> String? {
        guard let editorSettings = editorSettings,
              editorSettings != "undefined",
              let data = editorSettings.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let styles = json["styles"] as? [[String: Any]] else {
            return nil
        }

        // Concatenate all CSS from the styles array
        let cssArray = styles.compactMap { $0["css"] as? String }
        return cssArray.isEmpty ? nil : cssArray.joined(separator: "\n")
    }
}
