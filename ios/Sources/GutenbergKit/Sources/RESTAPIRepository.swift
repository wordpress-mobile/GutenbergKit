import CryptoKit
import Foundation

/// A caching repository for WordPress REST API resources needed by the editor.
///
/// `RESTAPIRepository` handles fetching and caching API responses such as editor settings,
/// post data, theme information, and site options. Cached responses are stored on disk
/// and returned on subsequent requests to improve loading performance.
public struct RESTAPIRepository: Sendable {

    package let httpClient: EditorHTTPClientProtocol
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

        self.editorSettingsUrl = apiRoot.appending(rawPath: Constants.API.editorSettingsPath)
        self.activeThemeUrl = apiRoot.appending(rawPath: Constants.API.activeThemePath)
        self.siteSettingsUrl = apiRoot.appending(rawPath: Constants.API.siteSettingsPath)
        self.postTypesUrl = apiRoot.appending(rawPath: Constants.API.postTypesPath)
    }

    /// Clears all cached API responses.
    public func purge() throws {
        try self.cache.clear()
    }

    // MARK: Post
    @discardableResult
    public func fetchPost(id: Int) async throws -> EditorURLResponse {
        let response = try await self.httpClient.GET(url: buildPostUrl(id: id))
        return EditorURLResponse(response)
    }

    public func readPost(id: Int) throws -> EditorURLResponse? {
        try self.cache.response(for: buildPostUrl(id: id), httpMethod: .GET)
    }

    private func buildPostUrl(id: Int) -> URL {
        configuration.siteApiRoot
            .appending(path: "wp/v2/posts")
            .appendingPathComponent(String(id))
            .appending(queryItems: [
                URLQueryItem(name: "context", value: "edit")
            ])
    }

    // MARK: Editor Settings
    @discardableResult
    public func fetchEditorSettings() async throws -> EditorSettings {
        if !self.configuration.shouldUsePlugins && !self.configuration.shouldUseThemeStyles {
            return .undefined
        }

        let response = try await self.httpClient.GET(url: editorSettingsUrl)
        let editorSettings = EditorSettings(data: response.0)

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
    package func fetchPostType(for type: String) async throws -> EditorURLResponse {
        try await GET(url: buildPostTypeUrl(type: type))
    }

    package func readPostType(for type: String) throws -> EditorURLResponse? {
        try self.cache.response(for: buildPostTypeUrl(type: type), httpMethod: .GET)
    }

    private func buildPostTypeUrl(type: String) -> URL {
        configuration.siteApiRoot.appending(path: "wp/v2/types/")
            .appending(path: type)
            .appending(queryItems: [
                URLQueryItem(name: "context", value: "edit")
            ])
    }

    // MARK: GET Active Theme
    @discardableResult
    package func fetchActiveTheme() async throws -> EditorURLResponse {
        try await GET(url: self.activeThemeUrl)
    }

    package func readActiveTheme() throws -> EditorURLResponse? {
        try self.cache.response(for: self.activeThemeUrl, httpMethod: .GET)
    }

    // MARK: OPTIONS Settings
    @discardableResult
    package func fetchSettingsOptions() async throws -> EditorURLResponse {
        try await OPTIONS(url: self.siteSettingsUrl)
    }

    package func readSettingsOptions() throws -> EditorURLResponse? {
        try self.cache.response(for: self.siteSettingsUrl, httpMethod: .OPTIONS)
    }

    // MARK: Post Types
    @discardableResult
    package func fetchPostTypes() async throws -> EditorURLResponse {
        try await self.GET(url: self.postTypesUrl)
    }

    package func readPostTypes() throws -> EditorURLResponse? {
        try self.cache.response(for: self.postTypesUrl, httpMethod: .GET)
    }

    private func GET(url: URL) async throws -> EditorURLResponse {
        let response = try await self.httpClient.GET(url: url)
        let urlResponse = EditorURLResponse(response)
        try self.cache.store(urlResponse, for: url, httpMethod: .GET)
        return urlResponse
    }

    private func OPTIONS(url: URL) async throws -> EditorURLResponse {
        let response = try await self.httpClient.OPTIONS(url: url)
        let urlResponse = EditorURLResponse(response)
        try self.cache.store(urlResponse, for: url, httpMethod: .OPTIONS)
        return urlResponse
    }
}
