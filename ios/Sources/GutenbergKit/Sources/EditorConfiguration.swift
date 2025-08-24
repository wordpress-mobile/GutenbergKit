import Foundation

public struct EditorConfiguration {
    /// The initial title to initialize the editor with.
    public var title = ""
    /// The initial content to initialize the editor with.
    public var content = ""

    public var postID: Int?
    public var postType: String?
    public var themeStyles = false
    public var plugins = false
    public var hideTitle = false
    public var siteURL = ""
    public var siteApiRoot = ""
    public var siteApiNamespace: [String] = []
    public var namespaceExcludedPaths: [String] = []
    public var authHeader = ""
    /// Raw block editor settings from the WordPress REST API
    public var editorSettings: [String: Any]?
    /// The locale to use for translations
    public var locale = "en"
    public var editorAssetsEndpoint: URL?

    public init(title: String = "", content: String = "") {
        self.title = title
        self.content = content
    }

    public mutating func updateEditorSettings(_ settings: [String: Any]?) {
        self.editorSettings = settings
    }

    public static let `default` = EditorConfiguration()
}
