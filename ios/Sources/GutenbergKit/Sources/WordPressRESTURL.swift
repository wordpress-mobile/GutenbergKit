import Foundation

/// Single source of truth for building namespaced WordPress REST API URLs, so the
/// media endpoint and every ``RESTAPIRepository`` endpoint normalize the site API
/// root and namespace identically (no drift).
enum WordPressRESTURL {
    /// Builds a URL by inserting the site API namespace after the version segment
    /// of the path. For example, `/wp/v2/posts` with namespace `sites/123` becomes
    /// `/wp/v2/sites/123/posts`. A `nil` namespace appends the path unchanged.
    ///
    /// Trailing slashes on the root and namespace are normalized, so an unslashed
    /// `apiRoot` or `namespace` still joins cleanly.
    ///
    /// A query string on `path` (e.g. `/wp/v2/media?force=true`) is kept verbatim
    /// and joined by ``URL/appending(rawPath:)``, which merges it with `&` into a
    /// query-based root (plain permalinks, `?rest_route=/`).
    static func namespaced(apiRoot: URL, path: String, namespace: String?) -> URL {
        guard let rawNamespace = namespace else {
            return apiRoot.appending(rawPath: path)
        }

        let namespace = rawNamespace.hasSuffix("/") ? rawNamespace : rawNamespace + "/"

        // Only the route is namespaced: splitting the query on `/` too would drop
        // empty segments from its values.
        let queryStart = path.firstIndex(of: "?") ?? path.endIndex
        let route = path[..<queryStart]
        let query = path[queryStart...]

        // Path format is typically /prefix/version/endpoint
        // (e.g. /wp/v2/posts or /wp-block-editor/v1/settings).
        let components = route.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 2 else {
            return apiRoot.appending(rawPath: path)
        }

        // Insert the namespace after the version segment (second component).
        let prefix = components[0]
        let version = components[1]
        let remainder = components.dropFirst(2).joined(separator: "/")

        let namespacedPath = remainder.isEmpty
            ? "/\(prefix)/\(version)/\(namespace)"
            : "/\(prefix)/\(version)/\(namespace)\(remainder)"

        return apiRoot.appending(rawPath: namespacedPath + query)
    }
}
