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
     */
    fun namespaced(siteApiRoot: String, siteApiNamespace: String?, path: String): String {
        val root = siteApiRoot.trimEnd('/')
        val namespace = siteApiNamespace?.let { it.trimEnd('/') + "/" }
            ?: return "$root$path"

        val parts = path.removePrefix("/").split("/", limit = 3)
        if (parts.size < 3) {
            return "$root$path"
        }

        return "$root/${parts[0]}/${parts[1]}/$namespace${parts[2]}"
    }
}
