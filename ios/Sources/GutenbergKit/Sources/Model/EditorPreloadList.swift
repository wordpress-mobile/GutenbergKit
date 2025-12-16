import Foundation

/// Pre-fetched API responses that are injected into the editor to avoid network requests.
///
/// The Gutenberg editor makes several API requests during initialization to fetch post types,
/// theme data, and site settings. By pre-fetching these responses and injecting them as
/// "preload data," the editor can initialize without waiting for network requests.
///
/// The preload list is serialized to JSON and passed to the editor's JavaScript, which uses
/// these cached responses instead of making network calls.
public struct EditorPreloadList: Sendable, Equatable, Hashable {

    /// The ID of the post being edited, if editing an existing post.
    let postID: Int?

    /// The pre-fetched post data for the post being edited.
    let postData: EditorURLResponse?

    /// The post type identifier (e.g., "post", "page").
    let postType: String

    /// Pre-fetched data for the current post type's schema.
    let postTypeData: EditorURLResponse

    /// Pre-fetched data for all available post types.
    let postTypesData: EditorURLResponse

    /// Pre-fetched data for the active theme, if available.
    let activeThemeData: EditorURLResponse?

    /// Pre-fetched site settings schema (OPTIONS request), if available.
    let settingsOptionsData: EditorURLResponse?

    /// Creates a new preload list with the specified API responses.
    ///
    /// Response headers are filtered to only include headers relevant to preloading.
    ///
    /// - Parameters:
    ///   - postID: The ID of the post being edited, or `nil` for new posts.
    ///   - postData: The pre-fetched post data, or `nil` for new posts.
    ///   - postType: The post type identifier.
    ///   - postTypeData: Pre-fetched post type schema.
    ///   - postTypesData: Pre-fetched list of all post types.
    ///   - activeThemeData: Pre-fetched active theme data, or `nil` if not available.
    ///   - settingsOptionsData: Pre-fetched settings schema, or `nil` if not available.
    public init(
        postID: Int? = nil,
        postData: EditorURLResponse? = nil,
        postType: String,
        postTypeData: EditorURLResponse,
        postTypesData: EditorURLResponse,
        activeThemeData: EditorURLResponse?,
        settingsOptionsData: EditorURLResponse?
    ) {
        self.postID = postID
        self.postData = postData?.asPreloadResponse()
        self.postType = postType
        self.postTypeData = postTypeData.asPreloadResponse()
        self.postTypesData = postTypesData.asPreloadResponse()
        self.activeThemeData = activeThemeData?.asPreloadResponse()
        self.settingsOptionsData = settingsOptionsData?.asPreloadResponse()
    }

    func build() throws -> JSON {
        return try logExecutionTime("Build Editor Preload List") {
            var getRequests = [
                buildPostTypePath(type: self.postType): try self.postTypeData.toJSON(),
                Constants.API.postTypesPath: try self.postTypesData.toJSON()
            ]

            if let postID, let postData {
                getRequests[buildPostPath(id: postID)] = try postData.toJSON()
            }

            if let activeThemeData {
                getRequests[Constants.API.activeThemePath] = try activeThemeData.toJSON()
            }

            var optionsRequests: [String: JSON] = [:]

            if let settingsOptionsData {
                optionsRequests[Constants.API.siteSettingsPath] = try settingsOptionsData.toJSON()
            }

            var allRequests = getRequests
            allRequests["OPTIONS"] = .object(optionsRequests)
            return .object(allRequests)
        }
    }

    /// Builds the preload list as a JSON string for injection into the editor.
    ///
    /// The JSON structure maps API paths to their cached responses, organized by HTTP method.
    /// GET requests are at the top level, while OPTIONS requests are nested under an "OPTIONS" key.
    ///
    /// - Parameter formatted: If `true`, returns pretty-printed JSON. Defaults to `false`.
    /// Formatting JSON is very expensive, so this shouldn't be used in production.
    /// - Returns: A JSON string representing the preload data.
    /// - Throws: An error if JSON serialization fails when `formatted` is `true`.
    func build(formatted: Bool = false) throws -> String {
        return try logExecutionTime("Serialize Editor Preload List") {
            var jsonData = try JSONEncoder().encode(self.build())

            if formatted {
                let rawData = try JSONSerialization.jsonObject(with: jsonData)
                jsonData = try JSONSerialization.data(
                    withJSONObject: rawData, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            }

            return String(decoding: jsonData, as: UTF8.self)
        }
    }

    /// Builds the API path for fetching a specific post.
    private func buildPostPath(id: Int) -> String {
        "/wp/v2/posts/\(id)?context=edit"
    }

    /// Builds the API path for fetching a post type's schema.
    private func buildPostTypePath(type: String) -> String {
        "/wp/v2/types/\(type)?context=edit"
    }
}

extension EditorURLResponse {
    /// Creates a copy of the response with only preload-relevant headers.
    ///
    /// Filters headers to only include those expected by WordPress core's preload system.
    func asPreloadResponse() -> EditorURLResponse {
        // These headers were chosen because they're the same as those present in WP Core
        let headers = self.responseHeaders.filtering(keys: "Accept", "Link")
        return EditorURLResponse(data: self.data, responseHeaders: headers)
    }
}
