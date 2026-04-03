import CryptoKit
import Foundation

/// A caching repository for WordPress REST API resources needed by the editor.
///
/// `RESTAPIRepository` handles fetching and caching API responses such as editor settings,
/// post data, theme information, and site options. Cached responses are stored on disk
/// and returned on subsequent requests to improve loading performance.
public struct RESTAPIRepository: Sendable {

    let httpClient: EditorHTTPClientProtocol
    private let configuration: EditorConfiguration
    private let cache: EditorURLCache

    // Other Endpoints
    private let editorSettingsUrl: URL
    private let activeThemeUrl: URL
    private let siteSettingsUrl: URL
    private let postTypesUrl: URL

    public init(
        configuration: EditorConfiguration,
        httpClient: EditorHTTPClientProtocol,
        urlSession: URLSession = .shared,
        cache: EditorURLCache
    ) {
        self.httpClient = httpClient
        self.configuration = configuration
        self.cache = cache

        let apiRoot = configuration.siteApiRoot

        // Use custom endpoint if provided, otherwise build from apiRoot with namespace
        if let customEndpoint = configuration.editorSettingsEndpoint {
            self.editorSettingsUrl = customEndpoint
        } else {
            self.editorSettingsUrl = Self.buildNamespacedURL(
                apiRoot: apiRoot,
                path: Constants.API.editorSettingsPath,
                namespace: configuration.siteApiNamespace.first
            )
        }

        self.activeThemeUrl = Self.buildNamespacedURL(
            apiRoot: apiRoot,
            path: Constants.API.activeThemePath,
            namespace: configuration.siteApiNamespace.first
        )
        self.siteSettingsUrl = Self.buildNamespacedURL(
            apiRoot: apiRoot,
            path: Constants.API.siteSettingsPath,
            namespace: configuration.siteApiNamespace.first
        )
        self.postTypesUrl = Self.buildNamespacedURL(
            apiRoot: apiRoot,
            path: Constants.API.postTypesPath,
            namespace: configuration.siteApiNamespace.first
        )
    }

    /// Builds a URL by inserting the namespace after the version segment of the path.
    /// For example: `/wp/v2/posts` with namespace `sites/123/` becomes `/wp/v2/sites/123/posts`
    private static func buildNamespacedURL(apiRoot: URL, path: String, namespace: String?) -> URL {
        guard let rawNamespace = namespace else {
            return apiRoot.appending(rawPath: path)
        }

        let namespace = rawNamespace.hasSuffix("/") ? rawNamespace : rawNamespace + "/"

        // Parse the path to find where to insert the namespace
        // Path format is typically: /prefix/version/endpoint (e.g., /wp/v2/posts or /wp-block-editor/v1/settings)
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 2 else {
            return apiRoot.appending(rawPath: path)
        }

        // Insert namespace after the version segment (second component)
        // e.g., /wp-block-editor/v1/settings -> /wp-block-editor/v1/sites/123/settings
        let prefix = components[0]
        let version = components[1]
        let remainder = components.dropFirst(2).joined(separator: "/")

        let namespacedPath: String
        if remainder.isEmpty {
            namespacedPath = "/\(prefix)/\(version)/\(namespace)"
        } else {
            namespacedPath = "/\(prefix)/\(version)/\(namespace)\(remainder)"
        }

        return apiRoot.appending(rawPath: namespacedPath)
    }

    /// Clears all cached API responses.
    public func purge() throws {
        try self.cache.clear()
    }

    // MARK: Post
    @discardableResult
    public func fetchPost(id: Int) async throws -> EditorURLResponse {
        let request = URLRequest(method: .GET, url: self.buildPostUrl(id: id))
        let response = try await self.httpClient.perform(request)
        return EditorURLResponse(response)
    }

    public func readPost(id: Int) throws -> EditorURLResponse? {
        try self.cache.response(for: buildPostUrl(id: id), httpMethod: .GET)
    }

    private func buildPostUrl(id: Int) -> URL {
        let restNamespace = configuration.postType.restNamespace
        let restBase = configuration.postType.restBase
        return Self.buildNamespacedURL(
            apiRoot: configuration.siteApiRoot,
            path: "/\(restNamespace)/\(restBase)/\(id)",
            namespace: configuration.siteApiNamespace.first
        ).appending(queryItems: [
            URLQueryItem(name: "context", value: "edit")
        ])
    }

    // MARK: Editor Settings
    @discardableResult
    public func fetchEditorSettings() async throws -> EditorSettings {
        if !self.configuration.shouldUseThemeStyles {
            return .undefined
        }

        let request = URLRequest(method: .GET, url: editorSettingsUrl)
        let response = try await self.httpClient.perform(request)

        let editorSettings = try EditorSettings(data: response.0)

        let urlResponse = EditorURLResponse((try JSONEncoder().encode(editorSettings), response.1))
        try self.cache.store(urlResponse, for: editorSettingsUrl, httpMethod: .GET)
        return editorSettings
    }

    public func readEditorSettings() throws -> EditorSettings? {
        guard let editorURLResponse = try self.cache.response(for: editorSettingsUrl, httpMethod: .GET) else {
            return nil
        }

        return try JSONDecoder().decode(EditorSettings.self, from: editorURLResponse.data)
    }

    // MARK: GET Post Type
    @discardableResult
    func fetchPostType(for type: String) async throws -> EditorURLResponse {
        try await self.perform(method: .GET, url: self.buildPostTypeUrl(type: type))
    }

    func readPostType(for type: String) throws -> EditorURLResponse? {
        try self.cache.response(for: buildPostTypeUrl(type: type), httpMethod: .GET)
    }

    private func buildPostTypeUrl(type: String) -> URL {
        Self.buildNamespacedURL(
            apiRoot: configuration.siteApiRoot,
            path: "/wp/v2/types/\(type)",
            namespace: configuration.siteApiNamespace.first
        ).appending(queryItems: [
            URLQueryItem(name: "context", value: "edit")
        ])
    }

    // MARK: GET Active Theme
    @discardableResult
    func fetchActiveTheme() async throws -> EditorURLResponse {
        try await self.perform(method: .GET, url: self.activeThemeUrl)
    }

    func readActiveTheme() throws -> EditorURLResponse? {
        try self.cache.response(for: self.activeThemeUrl, httpMethod: .GET)
    }

    // MARK: OPTIONS Settings
    @discardableResult
    func fetchSettingsOptions() async throws -> EditorURLResponse {
        try await self.perform(method: .OPTIONS, url: self.siteSettingsUrl)
    }

    func readSettingsOptions() throws -> EditorURLResponse? {
        try self.cache.response(for: self.siteSettingsUrl, httpMethod: .OPTIONS)
    }

    // MARK: Post Types
    @discardableResult
    func fetchPostTypes() async throws -> EditorURLResponse {
        try await self.perform(method: .GET, url: self.postTypesUrl)
    }

    func readPostTypes() throws -> EditorURLResponse? {
        try self.cache.response(for: self.postTypesUrl, httpMethod: .GET)
    }

    private func perform(method: EditorHttpMethod, url: URL) async throws -> EditorURLResponse {
        let request = URLRequest(method: method, url: url)
        let response = try await self.httpClient.perform(request)
        let urlResponse = EditorURLResponse(response)
        try self.cache.store(urlResponse, for: url, httpMethod: method)
        return urlResponse
    }

}
