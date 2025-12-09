import Foundation

/// Editor configuration and styling data fetched from the WordPress REST API.
///
/// This struct wraps the raw JSON response from the block editor settings endpoint,
/// which contains theme colors, typography, spacing, and other customization options.
/// The raw JSON is injected directly into the editor's JavaScript.
///
/// Theme styles are extracted separately for use in styling the editor UI.
public struct EditorSettings: Sendable, Codable, Equatable, Hashable {
    let jsonValue: JSON?

    /// CSS styles extracted from the theme's global styles.
    ///
    /// Contains the concatenated CSS from all theme style entries.
    /// Used to apply theme styling to the editor interface.
    public let themeStyles: String

    var stringValue: String

    /// Creates editor settings from raw API response data.
    ///
    /// Parses the JSON to extract theme styles while preserving the raw string
    /// for JavaScript injection. This operation involves JSON parsing and should
    /// be cached.
    ///
    /// - Parameter data: The raw JSON data from the block editor settings endpoint.
    init(data: Data) {
        let json = try? JSON(data)
        self.jsonValue = json

        let encodedJSON = try? JSONEncoder().encode(json)
        self.stringValue = String(decoding: encodedJSON ?? Data(), as: UTF8.self)

        if let settings = try? JSONDecoder().decode(InternalEditorSettings.self, from: data) {
            self.themeStyles = settings.styles.compactMap { $0.css }.joined(separator: "\n")
        } else {
            self.themeStyles = ""
        }
    }

    private init(
        jsonValue: JSON?,
        themeStyles: String
    ) {
        let encodedJSON = try? JSONEncoder().encode(jsonValue)
        self.stringValue = String(decoding: encodedJSON ?? Data(), as: UTF8.self)
        self.jsonValue = jsonValue
        self.themeStyles = themeStyles
    }

    /// A placeholder value for when editor settings are not available.
    static let undefined = EditorSettings(jsonValue: nil, themeStyles: "undefined")
}

/// Internal structure for decoding the editor settings response.
///
/// Only decodes the fields needed to extract theme styles.
struct InternalEditorSettings: Decodable {
    /// A CSS style entry from the theme.
    struct CSSStyle: Decodable {
        /// The CSS content, if present.
        let css: String?
        
        /// Whether this style is from the global styles system.
        let isGlobalStyles: Bool
    }

    /// All style entries from the theme.
    let styles: [CSSStyle]
}
