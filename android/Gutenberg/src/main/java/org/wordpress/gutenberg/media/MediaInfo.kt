package org.wordpress.gutenberg.media

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Mirrors `MediaInfo` on iOS — the shape the JS editor's
 * `window.blockInserter.insertMedia(...)` receiver expects per item.
 *
 * `id` is reserved for media-library round-trips that resolve a known
 * attachment; native-inserter handoffs leave it null and the JS side
 * falls back to URL-fetch-and-transform.
 */
@Serializable
internal data class MediaInfo(
    val id: Int? = null,
    val url: String,
    val type: String? = null,
    val title: String? = null,
    val caption: String? = null,
    val alt: String? = null,
    val metadata: Map<String, String> = emptyMap(),
)

/**
 * - `explicitNulls = false`: a null `id` / `type` / etc. encodes as a missing key, matching iOS Codable.
 * - `encodeDefaults = true`: keep `metadata` in the output even when it's `emptyMap()`, matching iOS
 *   (where non-optional `metadata: [String: String]` always encodes) and the JS receiver's expectation.
 */
internal val MediaInfoJson: Json = Json {
    explicitNulls = false
    encodeDefaults = true
}
