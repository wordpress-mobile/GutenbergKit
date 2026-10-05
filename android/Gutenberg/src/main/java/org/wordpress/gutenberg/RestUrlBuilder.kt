package org.wordpress.gutenberg

/**
 * Single source of truth for building namespaced WordPress REST API URLs, so the
 * media endpoint and every [RESTAPIRepository] endpoint normalize the site API
 * root and namespace identically (no drift).
 */
internal object RestUrlBuilder {
    /**
     * Builds a URL from [siteApiRoot] and [path], inserting [siteApiNamespace]
     * after the version segment if one is configured. A `null` namespace appends
     * the path unchanged.
     *
     * Trailing slashes on the root and namespace are normalized, so an unslashed
     * root or namespace still joins cleanly. For example, with namespace `sites/123`
     * and path `/wp/v2/types`, the result is `$root/wp/v2/sites/123/types`.
     *
     * The root and path are joined by [appendingRestPath], so a query-based root — as
     * used by sites with plain permalinks, e.g. `https://example.com/?rest_route=/` —
     * receives the path in its route value, with the path's own query string merged
     * with `&`.
     */
    fun namespaced(siteApiRoot: String, siteApiNamespace: String?, path: String): String =
        siteApiRoot.appendingRestPath(namespacedPath(siteApiNamespace, path))

    /**
     * Inserts [siteApiNamespace] after the version segment of [path], returning [path]
     * unchanged when no namespace is configured.
     */
    private fun namespacedPath(siteApiNamespace: String?, path: String): String {
        val namespace = siteApiNamespace?.let { it.trimEnd('/') + "/" }
            ?: return path

        val parts = path.removePrefix("/").split("/", limit = 3)
        if (parts.size < 2) {
            return path
        }

        val remainder = parts.getOrNull(2).orEmpty()
        return "/${parts[0]}/${parts[1]}/$namespace$remainder"
    }
}
