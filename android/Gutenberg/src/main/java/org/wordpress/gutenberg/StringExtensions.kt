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
