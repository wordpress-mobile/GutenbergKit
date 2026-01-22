package org.wordpress.gutenberg.model

import android.annotation.SuppressLint
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import org.wordpress.gutenberg.model.http.EditorURLResponse
import org.wordpress.gutenberg.model.http.asPreloadResponse

/**
 * Pre-fetched API responses that are injected into the editor to avoid network requests.
 *
 * The Gutenberg editor makes several API requests during initialization to fetch post types,
 * theme data, and site settings. By pre-fetching these responses and injecting them as
 * "preload data," the editor can initialize without waiting for network requests.
 *
 * The preload list is serialized to JSON and passed to the editor's JavaScript, which uses
 * these cached responses instead of making network calls.
 */
@SuppressLint("UnsafeOptInUsageError")
@Serializable
@ConsistentCopyVisibility
data class EditorPreloadList private constructor(
    /** The ID of the post being edited, if editing an existing post. */
    val postID: Int?,
    /** The pre-fetched post data for the post being edited. */
    val postData: EditorURLResponse?,
    /** The post type identifier (e.g., "post", "page"). */
    val postType: String,
    /** Pre-fetched data for the current post type's schema. */
    val postTypeData: EditorURLResponse,
    /** Pre-fetched data for all available post types. */
    val postTypesData: EditorURLResponse,
    /** Pre-fetched data for the active theme, if available. */
    val activeThemeData: EditorURLResponse?,
    /** Pre-fetched site settings schema (OPTIONS request), if available. */
    val settingsOptionsData: EditorURLResponse?
) {
    /**
     * Creates a new preload list with the specified API responses.
     *
     * Response headers are filtered to only include headers relevant to preloading.
     */
    constructor(
        postID: Int? = null,
        postData: EditorURLResponse? = null,
        postType: String,
        postTypeData: EditorURLResponse,
        postTypesData: EditorURLResponse,
        activeThemeData: EditorURLResponse?,
        settingsOptionsData: EditorURLResponse?,
        @Suppress("UNUSED_PARAMETER") filterHeaders: Boolean = true
    ) : this(
        postID = postID,
        postData = postData?.asPreloadResponse(),
        postType = postType,
        postTypeData = postTypeData.asPreloadResponse(),
        postTypesData = postTypesData.asPreloadResponse(),
        activeThemeData = activeThemeData?.asPreloadResponse(),
        settingsOptionsData = settingsOptionsData?.asPreloadResponse()
    )

    companion object {
        private const val POST_TYPES_PATH = "/wp/v2/types?context=view"
        private const val ACTIVE_THEME_PATH = "/wp/v2/themes?context=edit&status=active"
        private const val SITE_SETTINGS_PATH = "/wp/v2/settings"
    }

    fun build(): JsonElement {
        val entries = mutableMapOf<String, JsonElement>()

        entries[buildPostTypePath(postType)] = postTypeData.toJsonElement()
        entries[POST_TYPES_PATH] = postTypesData.toJsonElement()

        if (postID != null && postData != null) {
            entries[buildPostPath(postID)] = postData.toJsonElement()
        }

        if (activeThemeData != null) {
            entries[ACTIVE_THEME_PATH] = activeThemeData.toJsonElement()
        }

        val optionsRequests = buildJsonObject {
            if (settingsOptionsData != null) {
                put(SITE_SETTINGS_PATH, settingsOptionsData.toJsonElement())
            }
        }
        entries["OPTIONS"] = optionsRequests

        // Sort keys alphabetically to match Swift output
        return JsonObject(entries.toSortedMap())
    }

    /**
     * Builds the preload list as a JSON string for injection into the editor.
     *
     * The JSON structure maps API paths to their cached responses, organized by HTTP method.
     * GET requests are at the top level, while OPTIONS requests are nested under an "OPTIONS" key.
     *
     * @param formatted If `true`, returns pretty-printed JSON. Defaults to `false`.
     *   Formatting JSON is very expensive, so this shouldn't be used in production.
     * @return A JSON string representing the preload data.
     */
    fun build(formatted: Boolean = false): String {
        val jsonElement = build()
        return if (formatted) {
            @Suppress("JSON_FORMAT_REDUNDANT") // This is only used in debug builds
            Json { prettyPrint = true }.encodeToString(jsonElement)
        } else {
            Json.encodeToString(jsonElement)
        }
    }

    /** Builds the API path for fetching a specific post. */
    private fun buildPostPath(id: Int): String = "/wp/v2/posts/$id?context=edit"

    /** Builds the API path for fetching a post type's schema. */
    private fun buildPostTypePath(type: String): String = "/wp/v2/types/$type?context=edit"
}
