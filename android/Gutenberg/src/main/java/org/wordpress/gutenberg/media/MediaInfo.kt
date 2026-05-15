package org.wordpress.gutenberg.media

import org.json.JSONArray
import org.json.JSONObject

/**
 * Mirrors `MediaInfo` on iOS — the shape the JS editor's
 * `window.blockInserter.insertMedia(...)` receiver expects per item.
 *
 * `id` is reserved for media-library round-trips that resolve a known
 * attachment; native-inserter handoffs leave it null and the JS side
 * falls back to URL-fetch-and-transform.
 */
internal data class MediaInfo(
    val id: Int? = null,
    val url: String,
    val type: String?,
    val title: String? = null,
    val caption: String? = null,
    val alt: String? = null,
    val metadata: Map<String, String> = emptyMap(),
) {
    fun toJson(): JSONObject = JSONObject().apply {
        if (id != null) put("id", id)
        put("url", url)
        if (type != null) put("type", type)
        if (title != null) put("title", title)
        if (caption != null) put("caption", caption)
        if (alt != null) put("alt", alt)
        put("metadata", JSONObject(metadata as Map<*, *>))
    }
}

internal fun List<MediaInfo>.toJsonArray(): JSONArray =
    JSONArray().also { array -> forEach { array.put(it.toJson()) } }
