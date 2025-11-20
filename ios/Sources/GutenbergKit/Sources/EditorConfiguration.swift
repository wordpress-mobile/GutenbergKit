import Foundation

public struct EditorConfiguration: Sendable {
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
    /// Locale used for translations
    public let locale: String
    /// Enables the native inserter UI in the editor
    public let isNativeInserterEnabled: Bool
    /// Logs emitted at or above this level will be printed to the debug console
    public let logLevel: LogLevel

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
        locale: String,
        isNativeInserterEnabled: Bool,
        logLevel: LogLevel
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
        self.locale = locale
        self.isNativeInserterEnabled = isNativeInserterEnabled
        self.logLevel = logLevel
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
            locale: locale,
            isNativeInserterEnabled: isNativeInserterEnabled
        )
    }

    var escapedTitle: String {
        title.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
    }

    var escapedContent: String {
        content.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
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
    private var locale: String
    private var isNativeInserterEnabled: Bool
    private var logLevel: LogLevel

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
        locale: String = "en",
        isNativeInserterEnabled: Bool = false,
        logLevel: LogLevel = .error
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
        self.locale = locale
        self.isNativeInserterEnabled = isNativeInserterEnabled
        self.logLevel = logLevel
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

    public func setLocale(_ locale: String) -> EditorConfigurationBuilder {
        var copy = self
        copy.locale = locale
        return copy
    }

    public func setNativeInserterEnabled(_ isNativeInserterEnabled: Bool = true) -> EditorConfigurationBuilder {
        var copy = self
        copy.isNativeInserterEnabled = isNativeInserterEnabled
        return copy
    }

    public func setLogLevel(_ logLevel: LogLevel) -> EditorConfigurationBuilder {
        var copy = self
        copy.logLevel = logLevel
        return copy
    }

    /// Simplify conditionally applying a configuration change
    ///
    /// Sample Code:
    /// ```swift
    ///  // Before
    ///  let configurationBuilder = EditorConfigurationBuilder()
    ///  if let postID = post.id {
    ///     configurationBuilder = configurationBuilder.setPostID(postID)
    ///  }
    ///
    ///  // After
    ///  let configurationBuilder = EditorConfigurationBuilder()
    ///     .apply(post.id, { $0.setPostID($1) } )
    /// ```
    public func apply<T>(_ value: T?, _ closure: (EditorConfigurationBuilder, T) -> EditorConfigurationBuilder) -> Self {
        guard let value else {
            return self
        }

        return closure(self, value)
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
            locale: locale,
            isNativeInserterEnabled: isNativeInserterEnabled,
            logLevel: logLevel
        )
    }
}

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

