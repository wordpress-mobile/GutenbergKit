package org.wordpress.gutenberg

import java.net.URLEncoder

/**
 * Encodes a string for safe injection into the editor's JavaScript.
 *
 * This performs URL encoding and replaces `+` with `%20` to ensure spaces
 * are properly encoded for JavaScript string literals.
 *
 * @return The encoded string safe for editor injection.
 */
fun String.encodeForEditor(): String {
    return URLEncoder.encode(this, "UTF-8").replace("+", "%20")
}

/**
 * Appends a REST API endpoint path to this API root.
 *
 * Handles slash normalization between the root and the path, ensuring exactly one slash
 * separates them.
 *
 * When the root is a query-based REST root — as used by sites with plain permalinks,
 * e.g. `https://example.com/?rest_route=/` — the path is appended to the query value rather
 * than the URL path, and any query string on [path] is merged with `&`:
 *
 * ```
 * https://example.com/?rest_route=/ + /wp/v2/media -> https://example.com/?rest_route=/wp/v2/media
 * ```
 *
 * This mirrors the behavior of `@wordpress/api-fetch`'s root URL middleware, which the web
 * layer uses, for the canonical `?rest_route=/` root, so native and web requests resolve to the
 * same endpoints. For a root supplied without a trailing slash the two intentionally diverge:
 * this keeps the leading slash on the route value, which WordPress's `rest_route` matching
 * expects, whereas the middleware strips it.
 *
 * @param path The endpoint path to append. May or may not start with a slash.
 * @return The full endpoint URL.
 */
fun String.appendingRestPath(path: String): String {
    // A query-based root already carries the REST route in its query string, so the path is
    // concatenated onto that value and its own query separator becomes `&`.
    if (contains("?")) {
        val merged = path.replaceFirst("?", "&")

        // The route value must keep exactly one leading slash regardless of whether the root
        // was supplied as `?rest_route=/` or `?rest_route=`.
        return if (endsWith("/")) {
            this + merged.removePrefix("/")
        } else {
            this + if (merged.startsWith("/")) merged else "/$merged"
        }
    }

    return trimEnd('/') + if (path.startsWith("/")) path else "/$path"
}
