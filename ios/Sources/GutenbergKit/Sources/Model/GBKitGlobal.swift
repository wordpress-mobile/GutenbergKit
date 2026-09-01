import Foundation

/// Configuration object passed to the editor's JavaScript as a global variable.
///
/// This struct is serialized to JSON and injected into the WebView as `window.GBKit`,
/// providing the JavaScript code with all the information it needs to initialize
/// the editor and communicate with the WordPress REST API.
public struct GBKitGlobal: Sendable, Codable {

    /// The post data passed to the editor.
    public struct Post: Sendable, Codable {
        /// The post ID, or -1 for new posts.
        let id: Int

        /// The post type (e.g., "post", "page").
        let type: String

        /// The REST API base path for this post type (e.g., "posts", "pages", "products").
        let restBase: String

        /// The REST API namespace for this post type (e.g., "wp/v2").
        let restNamespace: String

        /// The post status (e.g., "draft", "publish", "pending").
        let status: String

        /// The post title.
        let title: String

        /// The post content (Gutenberg block markup).
        let content: String
    }

    /// The site's base URL, or `nil` if offline mode is enabled.
    let siteURL: URL?

    /// The WordPress REST API root URL, or `nil` if offline mode is enabled.
    let siteApiRoot: URL?

    /// Namespace segments to insert into API request paths.
    ///
    /// Used primarily for WordPress.com sites where API requests need a site identifier.
    /// The first namespace is inserted after the first two path segments for eligible requests.
    ///
    /// For example, with `["sites/123"]`, a request to `/wp/v2/posts` becomes `/wp/v2/sites/123/posts`.
    ///
    /// All namespaces are used to detect whether a path already contains a namespace (to avoid
    /// double-insertion), but only the first one is used for insertion.
    let siteApiNamespace: [String]

    /// API paths that should not have the namespace inserted.
    ///
    /// Paths starting with any of these prefixes will bypass the namespace insertion middleware.
    let namespaceExcludedPaths: [String]

    /// The authorization header value for authenticated API requests.
    let authHeader: String

    /// Whether to apply theme styles to the editor.
    let themeStyles: Bool

    /// Whether to load plugin assets.
    let plugins: Bool

    /// Whether to use the native block inserter instead of the web-based one.
    let enableNativeBlockInserter: Bool

    /// Whether to hide the post title field in the editor.
    let hideTitle: Bool

    /// The locale identifier for translations (e.g., `fr`).
    let locale: String

    /// The post being edited.
    let post: Post

    /// The logging level for JavaScript console output.
    let logLevel: String

    /// Whether to log network requests in the JavaScript console.
    let enableNetworkLogging: Bool

    /// Port the local HTTP server is listening on for native media uploads.
    let nativeUploadPort: Int?

    /// Per-session auth token for requests to the local upload server.
    let nativeUploadToken: String?

    let editorSettings: JSON?

    let preloadData: JSON?

    /// Pre-fetched editor assets (scripts, styles, allowed block types) for plugin loading.
    let editorAssets: JSON?

    /// Connection details for the native loopback network proxy.
    ///
    /// When present, the editor sends every site REST API request through
    /// `http://127.0.0.1:<port>` with the given bearer token rather than
    /// directly. The host advertises it only when a direct request cannot work
    /// — under iOS Lockdown Mode, which breaks CORS for `file://` pages — so
    /// there is no direct attempt to fall back from.
    public struct NetworkProxy: Sendable, Codable {
        let port: Int
        let token: String

        /// The synthesized memberwise initializer is internal, which would
        /// leave the `networkProxy` parameter of this type's public initializer
        /// with no value a host could pass it.
        public init(port: Int, token: String) {
            self.port = port
            self.token = token
        }
    }

    let networkProxy: NetworkProxy?

    /// Creates a global configuration from an editor configuration and dependencies.
    ///
    /// - Parameters:
    ///   - configuration: The editor configuration.
    ///   - dependencies: The pre-fetched editor dependencies (unused but reserved for future use).
    ///   - nativeUploadPort: Port of the local upload server, or nil if not running.
    ///   - nativeUploadToken: Auth token for the local upload server, or nil if not running.
    ///   - networkProxy: Loopback proxy connection details, when the proxy is running.
    public init(
        configuration: EditorConfiguration,
        dependencies: EditorDependencies,
        nativeUploadPort: Int? = nil,
        nativeUploadToken: String? = nil,
        networkProxy: NetworkProxy? = nil
    ) throws {
        self.siteURL = configuration.isOfflineModeEnabled ? nil : configuration.siteURL
        self.siteApiRoot = configuration.isOfflineModeEnabled ? nil : configuration.siteApiRoot
        self.siteApiNamespace = configuration.siteApiNamespace
        self.namespaceExcludedPaths = configuration.namespaceExcludedPaths
        self.authHeader = configuration.authHeader
        self.themeStyles = configuration.shouldUseThemeStyles
        self.plugins = configuration.shouldUsePlugins
        self.enableNativeBlockInserter = configuration.isNativeInserterEnabled
        self.hideTitle = configuration.shouldHideTitle
        self.locale = configuration.locale
        self.post = Post(
            id: configuration.postID ?? -1,
            type: configuration.postType.postType,
            restBase: configuration.postType.restBase,
            restNamespace: configuration.postType.restNamespace,
            status: configuration.postStatus,
            title: configuration.escapedTitle,
            content: configuration.escapedContent
        )
        self.logLevel = configuration.logLevel.rawValue
        self.enableNetworkLogging = configuration.enableNetworkLogging
        self.nativeUploadPort = nativeUploadPort
        self.nativeUploadToken = nativeUploadToken
        self.editorSettings = dependencies.editorSettings.jsonValue
        self.preloadData = try dependencies.preloadList?.build()
        self.editorAssets = Self.buildEditorAssets(from: dependencies.assetBundle)
        self.networkProxy = networkProxy
    }

    private static func buildEditorAssets(from bundle: EditorAssetBundle) -> JSON? {
        guard let representation = try? bundle.getEditorRepresentation() as EditorAssetBundle.EditorRepresentation else {
            return nil
        }
        return .object([
            "scripts": .string(representation.scripts),
            "styles": .string(representation.styles),
            "allowed_block_types": .array(representation.allowedBlockTypes.map { .string($0) })
        ])
    }

    /// Serializes the configuration to a JSON string for injection into JavaScript.
    ///
    /// - Returns: A JSON string representation of this object.
    /// - Throws: An encoding error if serialization fails.
    public func toString() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}
