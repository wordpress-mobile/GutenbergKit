import Foundation

public struct EditorConfiguration {
    /// Initial title for populating the editor
    public let title: String
    /// Initial content for populating the editor
    public let content: String

    /// ID of the post being edited
    public let postID: Int?
    /// Type of the post being edited
    public let postType: String?
    /// Toggles application of theme styles
    public let shouldUseThemeStyles: Bool
    /// Toggles loading plugin-provided editor assets
    public let shouldUsePlugins: Bool
    /// Toggles visibility of the title field
    public let shouldHideTitle: Bool
    /// Root URL for the site
    public let siteURL: String
    /// Root URL for the site API
    public let siteApiRoot: String
    /// Namespaces for the site API
    public let siteApiNamespace: [String]
    /// Paths excluded from API namespacing
    public let namespaceExcludedPaths: [String]
    /// Authorization header
    public let authHeader: String
    /// Global variables to be made available to the editor
    public let webViewGlobals: [WebViewGlobal]
    /// Raw block editor settings from the WordPress REST API
    public let editorSettings: EditorSettings
    /// Locale used for translations
    public let locale: String
    /// Endpoint for loading editor assets, used when enabling `shouldUsePlugins`
    public var editorAssetsEndpoint: URL?

    // Cookies
    public let cookies: [HTTPCookie]

    /// Deliberately non-public – consumers should use `EditorConfigurationBuilder` to construct a configuration
    init(
        title: String,
        content: String,
        postID: Int?,
        postType: String?,
        shouldUseThemeStyles: Bool,
        shouldUsePlugins: Bool,
        shouldHideTitle: Bool,
        siteURL: String,
        siteApiRoot: String,
        siteApiNamespace: [String],
        namespaceExcludedPaths: [String],
        authHeader: String,
        webViewGlobals: [WebViewGlobal],
        editorSettings: EditorSettings,
        locale: String,
        editorAssetsEndpoint: URL? = nil,
        cookies: [HTTPCookie] = []
    ) {
        self.title = title
        self.content = content
        self.postID = postID
        self.postType = postType
        self.shouldUseThemeStyles = shouldUseThemeStyles
        self.shouldUsePlugins = shouldUsePlugins
        self.shouldHideTitle = shouldHideTitle
        self.siteURL = siteURL
        self.siteApiRoot = siteApiRoot
        self.siteApiNamespace = siteApiNamespace
        self.namespaceExcludedPaths = namespaceExcludedPaths
        self.authHeader = authHeader
        self.webViewGlobals = webViewGlobals
        self.editorSettings = editorSettings
        self.locale = locale
        self.editorAssetsEndpoint = editorAssetsEndpoint
        self.cookies = cookies
    }

    public func toBuilder() -> EditorConfigurationBuilder {
        return EditorConfigurationBuilder(
            title: title,
            content: content,
            postID: postID,
            postType: postType,
            shouldUseThemeStyles: shouldUseThemeStyles,
            shouldUsePlugins: shouldUsePlugins,
            shouldHideTitle: shouldHideTitle,
            siteURL: siteURL,
            siteApiRoot: siteApiRoot,
            siteApiNamespace: siteApiNamespace,
            namespaceExcludedPaths: namespaceExcludedPaths,
            authHeader: authHeader,
            webViewGlobals: webViewGlobals,
            editorSettings: editorSettings,
            locale: locale,
            editorAssetsEndpoint: editorAssetsEndpoint
        )
    }

    var escapedTitle: String {
        title.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
    }

    var escapedContent: String {
        content.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
    }

    var editorSettingsJSON: String {
        // `editorSettings` values are always `encodable` so this should never fail
        let jsonData = try! JSONSerialization.data(withJSONObject: editorSettings, options: [])
        return String(data: jsonData, encoding: .utf8) ?? "undefined"
    }

    public static let `default` = EditorConfigurationBuilder().build()
}

public struct EditorConfigurationBuilder {
    private var title: String
    private var content: String
    private var postID: Int?
    private var postType: String?
    private var shouldUseThemeStyles: Bool
    private var shouldUsePlugins: Bool
    private var shouldHideTitle: Bool
    private var siteURL: String
    private var siteApiRoot: String
    private var siteApiNamespace: [String]
    private var namespaceExcludedPaths: [String]
    private var authHeader: String
    private var webViewGlobals: [WebViewGlobal]
    private var editorSettings: EditorSettings
    private var locale: String
    private var editorAssetsEndpoint: URL?

    public init(
        title: String = "",
        content: String = "",
        postID: Int? = nil,
        postType: String? = nil,
        shouldUseThemeStyles: Bool = false,
        shouldUsePlugins: Bool = false,
        shouldHideTitle: Bool = false,
        siteURL: String = "",
        siteApiRoot: String = "",
        siteApiNamespace: [String] = [],
        namespaceExcludedPaths: [String] = [],
        authHeader: String = "",
        webViewGlobals: [WebViewGlobal] = [],
        editorSettings: EditorSettings = [:],
        locale: String = "en",
        editorAssetsEndpoint: URL? = nil
    ){
        self.title = title
        self.content = content
        self.postID = postID
        self.postType = postType
        self.shouldUseThemeStyles = shouldUseThemeStyles
        self.shouldUsePlugins = shouldUsePlugins
        self.shouldHideTitle = shouldHideTitle
        self.siteURL = siteURL
        self.siteApiRoot = siteApiRoot
        self.siteApiNamespace = siteApiNamespace
        self.namespaceExcludedPaths = namespaceExcludedPaths
        self.authHeader = authHeader
        self.webViewGlobals = webViewGlobals
        self.editorSettings = editorSettings
        self.locale = locale
        self.editorAssetsEndpoint = editorAssetsEndpoint
    }

    public func setTitle(_ title: String) -> EditorConfigurationBuilder {
        var copy = self
        copy.title = title
        return copy
    }

    public func setContent(_ content: String) -> EditorConfigurationBuilder {
        var copy = self
        copy.content = content
        return copy
    }

    public func setPostID(_ postID: Int?) -> EditorConfigurationBuilder {
        var copy = self
        copy.postID = postID
        return copy
    }

    public func setPostType(_ postType: String?) -> EditorConfigurationBuilder {
        var copy = self
        copy.postType = postType
        return copy
    }

    public func setShouldUseThemeStyles(_ shouldUseThemeStyles: Bool) -> EditorConfigurationBuilder {
        var copy = self
        copy.shouldUseThemeStyles = shouldUseThemeStyles
        return copy
    }

    public func setShouldUsePlugins(_ shouldUsePlugins: Bool) -> EditorConfigurationBuilder {
        var copy = self
        copy.shouldUsePlugins = shouldUsePlugins
        return copy
    }

    public func setShouldHideTitle(_ shouldHideTitle: Bool) -> EditorConfigurationBuilder {
        var copy = self
        copy.shouldHideTitle = shouldHideTitle
        return copy
    }

    public func setSiteUrl(_ siteUrl: String) -> EditorConfigurationBuilder {
        var copy = self
        copy.siteURL = siteUrl
        return copy
    }

    public func setSiteApiRoot(_ siteApiRoot: String) -> EditorConfigurationBuilder {
        var copy = self
        copy.siteApiRoot = siteApiRoot
        return copy
    }

    public func setSiteApiNamespace(_ siteApiNamespace: [String]) -> EditorConfigurationBuilder {
        var copy = self
        copy.siteApiNamespace = siteApiNamespace
        return copy
    }

    public func setNamespaceExcludedPaths(_ namespaceExcludedPaths: [String]) -> EditorConfigurationBuilder {
        var copy = self
        copy.namespaceExcludedPaths = namespaceExcludedPaths
        return copy
    }

    public func setAuthHeader(_ authHeader: String) -> EditorConfigurationBuilder {
        var copy = self
        copy.authHeader = authHeader
        return copy
    }

    public func setWebViewGlobals(_ webViewGlobals: [WebViewGlobal]) -> EditorConfigurationBuilder {
        var copy = self
        copy.webViewGlobals = webViewGlobals
        return copy
    }

    public func setEditorSettings(_ editorSettings: EditorSettings) -> EditorConfigurationBuilder {
        var copy = self
        copy.editorSettings = editorSettings
        return copy
    }

    public func setLocale(_ locale: String) -> EditorConfigurationBuilder {
        var copy = self
        copy.locale = locale
        return copy
    }

    public func setEditorAssetsEndpoint(_ editorAssetsEndpoint: URL?) -> EditorConfigurationBuilder {
        var copy = self
        copy.editorAssetsEndpoint = editorAssetsEndpoint
        return copy
    }

    public func build() -> EditorConfiguration {
        EditorConfiguration(
            title: title,
            content: content,
            postID: postID,
            postType: postType,
            shouldUseThemeStyles: shouldUseThemeStyles,
            shouldUsePlugins: shouldUsePlugins,
            shouldHideTitle: shouldHideTitle,
            siteURL: siteURL,
            siteApiRoot: siteApiRoot,
            siteApiNamespace: siteApiNamespace,
            namespaceExcludedPaths: namespaceExcludedPaths,
            authHeader: authHeader,
            webViewGlobals: webViewGlobals,
            editorSettings: editorSettings,
            locale: locale,
            editorAssetsEndpoint: editorAssetsEndpoint
        )
    }
}

public struct WebViewGlobal: Equatable {
    let name: String
    let value: WebViewGlobalValue

    public init(name: String, value: WebViewGlobalValue) throws {
        // Validate name is a valid JavaScript identifier
        guard Self.isValidJavaScriptIdentifier(name) else {
            throw WebViewGlobalError.invalidIdentifier(name)
        }
        self.name = name
        self.value = value
    }

    private static func isValidJavaScriptIdentifier(_ name: String) -> Bool {
        // Add validation logic for JavaScript identifiers
        return name.range(of: "^[a-zA-Z_$][a-zA-Z0-9_$]*$", options: .regularExpression) != nil
    }
}

public enum WebViewGlobalError: Error {
    case invalidIdentifier(String)
}

public enum WebViewGlobalValue: Equatable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case object([String: WebViewGlobalValue])
    case array([WebViewGlobalValue])
    case null

    func toJavaScript() -> String {
        switch self {
        case .string(let str):
            return "\"\(str.escaped)\""
        case .number(let num):
            return "\(num)"
        case .boolean(let bool):
            return "\(bool)"
        case .object(let dict):
            let sortedKeys = dict.keys.sorted()
            var pairs: [String] = []
            for key in sortedKeys {
                let value = dict[key]!
                pairs.append("\"\(key.escaped)\": \(value.toJavaScript())")
            }
            return "{\(pairs.joined(separator: ","))}"
        case .array(let array):
            return "[\(array.map { $0.toJavaScript() }.joined(separator: ","))]"
        case .null:
            return "null"
        }
    }
}

public typealias EditorSettings = [String: Encodable]

// String escaping extension
private extension String {
    var escaped: String {
        return self.replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\u{8}", with: "\\b")
            .replacingOccurrences(of: "\u{12}", with: "\\f")
    }
}
