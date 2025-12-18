package org.wordpress.gutenberg.model.http

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/**
 * An HTTP response containing body data and headers.
 *
 * This class encapsulates the response from an HTTP request, storing both the
 * response body and headers. It's used throughout the editor for caching API
 * responses and building preload data.
 */
@Serializable
data class EditorURLResponse(
    /** The response body data as a string. */
    val data: String,
    /** The HTTP response headers. */
    val responseHeaders: EditorHTTPHeaders
) {
    fun toJsonElement(): JsonElement {
        val bodyElement = try {
            Json.parseToJsonElement(data)
        } catch (e: Exception) {
            kotlinx.serialization.json.JsonPrimitive(data)
        }

        return JsonObject(
            mapOf(
                "body" to bodyElement,
                "headers" to responseHeaders.toJsonElement()
            )
        )
    }

    companion object {
        /** An empty response with an empty JSON object body and no headers. */
        val empty = EditorURLResponse(data = "{}", responseHeaders = EditorHTTPHeaders.empty)
    }
}

/**
 * Creates a copy of the response with only preload-relevant headers.
 *
 * Filters headers to only include those expected by WordPress core's preload system.
 */
fun EditorURLResponse.asPreloadResponse(): EditorURLResponse {
    // These headers were chosen because they're the same as those present in WP Core
    val headers = this.responseHeaders.filtering("Accept", "Link")
    return EditorURLResponse(data = this.data, responseHeaders = headers)
}
