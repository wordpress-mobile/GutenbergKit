import Foundation

/// Configuration settings for initializing the Gutenberg block editor.
///
/// This struct contains all the parameters needed to configure the editor, including
/// site credentials, API endpoints, feature flags, and initial content. Use
/// `EditorConfigurationBuilder` to construct instances.
public struct EditorConfiguration: Sendable, Hashable, Equatable {
  /// Initial title for populating the editor
  public let title: String
  /// Initial content for populating the editor
  public let content: String
  /// ID of the post being edited
  public let postID: Int?
  /// Details about the post type being edited, including REST API configuration
  public let postType: PostTypeDetails
  /// Status of the post being edited (e.g., "draft", "publish", "pending")
  public let postStatus: String
  /// Toggles application of theme styles
  public let shouldUseThemeStyles: Bool
  /// Toggles loading plugin-provided editor assets
  public let shouldUsePlugins: Bool
  /// Toggles visibility of the title field
  public let shouldHideTitle: Bool
  /// Root URL for the site
  public let siteURL: URL
  /// Root URL for the site API
  public let siteApiRoot: URL
  /// Namespaces for the site API
  public let siteApiNamespace: [String]
  /// Paths excluded from API namespacing
  public let namespaceExcludedPaths: [String]
  /// Authorization header
  public let authHeader: String
  /// Raw block editor settings from the WordPress REST API
  public let editorSettings: String
  /// Locale used for translations
  public let locale: String
  /// Enables the native inserter UI in the editor
  public let isNativeInserterEnabled: Bool
  /// Endpoint for loading editor settings
  public let editorSettingsEndpoint: URL?
  /// Endpoint for loading editor assets, used when enabling `shouldUsePlugins`
  public let editorAssetsEndpoint: URL?
  /// Logs emitted at or above this level will be printed to the debug console
  public let logLevel: EditorLogLevel
  /// Enables logging of all network requests/responses to the native host
  public let enableNetworkLogging: Bool
  /// Don't make HTTP requests
  public let isOfflineModeEnabled: Bool
  /// A site ID derived from the URL that can be used in file system paths
  package let siteId: String

  /// Deliberately non-public – consumers should use `EditorConfigurationBuilder` to construct a configuration
  init(
    title: String,
    content: String,
    postID: Int?,
    postType: PostTypeDetails,
    postStatus: String,
    shouldUseThemeStyles: Bool,
    shouldUsePlugins: Bool,
    shouldHideTitle: Bool,
    siteURL: URL,
    siteApiRoot: URL,
    siteApiNamespace: [String],
    namespaceExcludedPaths: [String],
    authHeader: String,
    editorSettings: String,
    locale: String,
    isNativeInserterEnabled: Bool,
    editorSettingsEndpoint: URL?,
    editorAssetsEndpoint: URL?,
    logLevel: EditorLogLevel,
    enableNetworkLogging: Bool = false,
    isOfflineModeEnabled: Bool = false
  ) {
    self.title = title
    self.content = content
    self.postID = postID
    self.postType = postType
    self.postStatus = postStatus
    self.shouldUseThemeStyles = shouldUseThemeStyles
    self.shouldUsePlugins = shouldUsePlugins
    self.shouldHideTitle = shouldHideTitle
    self.siteURL = siteURL
    self.siteApiRoot = siteApiRoot
    self.siteApiNamespace = siteApiNamespace
    self.namespaceExcludedPaths = namespaceExcludedPaths
    self.authHeader = authHeader
    self.editorSettings = editorSettings
    self.locale = locale
    self.isNativeInserterEnabled = isNativeInserterEnabled
    self.editorSettingsEndpoint = editorSettingsEndpoint
    self.editorAssetsEndpoint = editorAssetsEndpoint
    self.logLevel = logLevel
    self.enableNetworkLogging = enableNetworkLogging
    self.isOfflineModeEnabled = isOfflineModeEnabled

    // Derived Properties
    self.siteId = self.siteURL.host(percentEncoded: false) ?? UUID().uuidString
  }

  /// Creates a builder initialized with this configuration's values.
  ///
  /// Use this to create a modified copy of an existing configuration.
  public func toBuilder() -> EditorConfigurationBuilder {
    return EditorConfigurationBuilder(
      title: title,
      content: content,
      postID: postID,
      postType: postType,
      postStatus: postStatus,
      shouldUseThemeStyles: shouldUseThemeStyles,
      shouldUsePlugins: shouldUsePlugins,
      shouldHideTitle: shouldHideTitle,
      siteURL: siteURL,
      siteApiRoot: siteApiRoot,
      siteApiNamespace: siteApiNamespace,
      namespaceExcludedPaths: namespaceExcludedPaths,
      authHeader: authHeader,
      editorSettings: editorSettings,
      locale: locale,
      isNativeInserterEnabled: isNativeInserterEnabled,
      editorSettingsEndpoint: editorSettingsEndpoint,
      editorAssetsEndpoint: editorAssetsEndpoint,
      logLevel: logLevel,
      enableNetworkLogging: enableNetworkLogging,
      isOfflineModeEnabled: isOfflineModeEnabled
    )
  }

  package var escapedTitle: String {
    title.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
  }

  package var escapedContent: String {
    content.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
  }
}

/// A builder for constructing `EditorConfiguration` instances.
///
/// This builder provides a fluent API for setting configuration options:
///
/// ```swift
/// let config = EditorConfigurationBuilder(postType: .post, siteURL: siteURL, siteApiRoot: apiRoot)
///     .setTitle("Hello World")
///     .setContent("<!-- wp:paragraph --><p>Content</p><!-- /wp:paragraph -->")
///     .setShouldUseThemeStyles(true)
///     .build()
/// ```
public struct EditorConfigurationBuilder {
  private var title: String
  private var content: String
  private var postID: Int?
  private var postType: PostTypeDetails
  private var postStatus: String
  private var shouldUseThemeStyles: Bool
  private var shouldUsePlugins: Bool
  private var shouldHideTitle: Bool
  private var siteURL: URL
  private var siteApiRoot: URL
  private var siteApiNamespace: [String]
  private var namespaceExcludedPaths: [String]
  private var authHeader: String
  private var editorSettings: String
  private var locale: String
  private var isNativeInserterEnabled: Bool
  private var editorSettingsEndpoint: URL?
  private var editorAssetsEndpoint: URL?
  private var logLevel: EditorLogLevel
  private var enableNetworkLogging: Bool
  private var isOfflineModeEnabled: Bool

  public init(
    title: String = "",
    content: String = "",
    postID: Int? = nil,
    postType: PostTypeDetails,
    postStatus: String = "draft",
    shouldUseThemeStyles: Bool = false,
    shouldUsePlugins: Bool = false,
    shouldHideTitle: Bool = false,
    siteURL: URL,
    siteApiRoot: URL,
    siteApiNamespace: [String] = [],
    namespaceExcludedPaths: [String] = [],
    authHeader: String = "",
    editorSettings: String = "undefined",
    locale: String = "en",
    isNativeInserterEnabled: Bool = false,
    editorSettingsEndpoint: URL? = nil,
    editorAssetsEndpoint: URL? = nil,
    logLevel: EditorLogLevel = .error,
    enableNetworkLogging: Bool = false,
    isOfflineModeEnabled: Bool = false
  ) {
    self.title = title
    self.content = content
    self.postID = postID
    self.postType = postType
    self.postStatus = postStatus
    self.shouldUseThemeStyles = shouldUseThemeStyles
    self.shouldUsePlugins = shouldUsePlugins
    self.shouldHideTitle = shouldHideTitle
    self.siteURL = siteURL
    self.siteApiRoot = siteApiRoot
    self.siteApiNamespace = siteApiNamespace
    self.namespaceExcludedPaths = namespaceExcludedPaths
    self.authHeader = authHeader
    self.editorSettings = editorSettings
    self.locale = locale
    self.isNativeInserterEnabled = isNativeInserterEnabled
    self.editorSettingsEndpoint = editorSettingsEndpoint
    self.editorAssetsEndpoint = editorAssetsEndpoint
    self.logLevel = logLevel
    self.enableNetworkLogging = enableNetworkLogging
    self.isOfflineModeEnabled = isOfflineModeEnabled
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

  public func setSiteUrl(_ siteUrl: URL) -> EditorConfigurationBuilder {
    var copy = self
    copy.siteURL = siteUrl
    return copy
  }

  public func setSiteApiRoot(_ siteApiRoot: URL) -> EditorConfigurationBuilder {
    var copy = self
    copy.siteApiRoot = siteApiRoot
    return copy
  }

  public func setPostType(_ type: PostTypeDetails) -> EditorConfigurationBuilder {
    var copy = self
    copy.postType = type
    return copy
  }

  public func setPostStatus(_ postStatus: String) -> EditorConfigurationBuilder {
    var copy = self
    copy.postStatus = postStatus
    return copy
  }

  public func setSiteApiNamespace(_ siteApiNamespace: [String]) -> EditorConfigurationBuilder {
    var copy = self
    copy.siteApiNamespace = siteApiNamespace
    return copy
  }

  public func setNamespaceExcludedPaths(_ namespaceExcludedPaths: [String])
    -> EditorConfigurationBuilder {
    var copy = self
    copy.namespaceExcludedPaths = namespaceExcludedPaths
    return copy
  }

  public func setAuthHeader(_ authHeader: String) -> EditorConfigurationBuilder {
    var copy = self
    copy.authHeader = authHeader
    return copy
  }

  public func setEditorSettings(_ editorSettings: String) -> EditorConfigurationBuilder {
    var copy = self
    copy.editorSettings = editorSettings
    return copy
  }

  public func setLocale(_ locale: String) -> EditorConfigurationBuilder {
    var copy = self
    copy.locale = locale
    return copy
  }

  public func setNativeInserterEnabled(_ isNativeInserterEnabled: Bool = true)
    -> EditorConfigurationBuilder {
    var copy = self
    copy.isNativeInserterEnabled = isNativeInserterEnabled
    return copy
  }

  public func setEditorSettingsEndpoint(_ editorSettingsEndpoint: URL?)
    -> EditorConfigurationBuilder {
    var copy = self
    copy.editorSettingsEndpoint = editorSettingsEndpoint
    return copy
  }

  public func setEditorAssetsEndpoint(_ editorAssetsEndpoint: URL?) -> EditorConfigurationBuilder {
    var copy = self
    copy.editorAssetsEndpoint = editorAssetsEndpoint
    return copy
  }

  public func setLogLevel(_ logLevel: EditorLogLevel) -> EditorConfigurationBuilder {
    var copy = self
    copy.logLevel = logLevel
    return copy
  }

  public func setEnableNetworkLogging(_ enableNetworkLogging: Bool) -> EditorConfigurationBuilder {
    var copy = self
    copy.enableNetworkLogging = enableNetworkLogging
    return copy
  }

  public func setIsOfflineModeEnabled(_ isOfflineModeEnabled: Bool) -> EditorConfigurationBuilder {
    var copy = self
    copy.isOfflineModeEnabled = isOfflineModeEnabled
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
  public func apply<T>(
    _ value: T?, _ closure: (EditorConfigurationBuilder, T) -> EditorConfigurationBuilder
  ) -> Self {
    guard let value else {
      return self
    }

    return closure(self, value)
  }

  /// Builds an `EditorConfiguration` from the current builder state.
  public func build() -> EditorConfiguration {
    EditorConfiguration(
      title: title,
      content: content,
      postID: postID,
      postType: postType,
      postStatus: postStatus,
      shouldUseThemeStyles: shouldUseThemeStyles,
      shouldUsePlugins: shouldUsePlugins,
      shouldHideTitle: shouldHideTitle,
      siteURL: siteURL,
      siteApiRoot: siteApiRoot,
      siteApiNamespace: siteApiNamespace,
      namespaceExcludedPaths: namespaceExcludedPaths,
      authHeader: authHeader,
      editorSettings: editorSettings,
      locale: locale,
      isNativeInserterEnabled: isNativeInserterEnabled,
      editorSettingsEndpoint: editorSettingsEndpoint,
      editorAssetsEndpoint: editorAssetsEndpoint,
      logLevel: logLevel,
      enableNetworkLogging: enableNetworkLogging,
      isOfflineModeEnabled: isOfflineModeEnabled
    )
  }
}
