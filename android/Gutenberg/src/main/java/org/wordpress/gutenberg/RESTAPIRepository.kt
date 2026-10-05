package org.wordpress.gutenberg

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.wordpress.gutenberg.model.EditorConfiguration
import org.wordpress.gutenberg.model.EditorSettings
import org.wordpress.gutenberg.model.http.EditorHTTPHeaders
import org.wordpress.gutenberg.model.http.EditorHttpMethod
import org.wordpress.gutenberg.model.http.EditorURLResponse
import org.wordpress.gutenberg.stores.EditorURLCache

/**
 * A caching repository for WordPress REST API resources needed by the editor.
 *
 * `RESTAPIRepository` handles fetching and caching API responses such as editor settings,
 * post data, theme information, and site options. Cached responses are stored on disk
 * and returned on subsequent requests to improve loading performance.
 */
class RESTAPIRepository(
    private val configuration: EditorConfiguration,
    val httpClient: EditorHTTPClientProtocol,
    private val cache: EditorURLCache
) {
    private val json = Json { ignoreUnknownKeys = true }

    private val editorSettingsUrl = buildNamespacedUrl(EDITOR_SETTINGS_PATH)
    private val activeThemeUrl = buildNamespacedUrl(ACTIVE_THEME_PATH)
    private val siteSettingsUrl = buildNamespacedUrl(SITE_SETTINGS_PATH)
    private val postTypesUrl = buildNamespacedUrl(POST_TYPES_PATH)

    /**
     * Cleanup any expired cache entries.
     *
     */
    fun cleanup() {
        cache.clean()
    }

    /**
     * Clears all cached API responses.
     */
    fun purge() {
        cache.purge()
    }

    // MARK: Post

    /**
     * Fetches post data for the given post ID.
     *
     * @param id The post ID to fetch.
     * @return The response containing the post data.
     */
    suspend fun fetchPost(id: Int): EditorURLResponse {
        val url = buildPostUrl(id)
        val response = httpClient.perform(EditorHttpMethod.GET, url)
        return EditorURLResponse(
            data = response.stringData,
            responseHeaders = response.headers
        )
    }

    /**
     * Reads cached post data for the given post ID.
     *
     * @param id The post ID to look up.
     * @return The cached response, or `null` if not cached.
     */
    fun readPost(id: Int): EditorURLResponse? {
        return cache.getResponse(buildPostUrl(id), EditorHttpMethod.GET)
    }

    private fun buildPostUrl(id: Int): String {
        val restNamespace = configuration.postType.restNamespace
        val restBase = configuration.postType.restBase
        return buildNamespacedUrl("/$restNamespace/$restBase/$id?context=edit")
    }

    // MARK: Editor Settings

    /**
     * Fetches editor settings from the WordPress REST API.
     *
     * Returns [EditorSettings.undefined] if plugins and theme styles are both disabled
     * in the configuration.
     *
     * @return The parsed editor settings.
     */
    suspend fun fetchEditorSettings(): EditorSettings {
        if (!configuration.themeStyles) {
            return EditorSettings.undefined
        }

        val response = httpClient.perform(EditorHttpMethod.GET, editorSettingsUrl)
        val editorSettings = EditorSettings.fromData(response.stringData)

        // Store the parsed settings in cache
        val urlResponse = EditorURLResponse(
            data = json.encodeToString(editorSettings),
            responseHeaders = response.headers
        )
        cache.store(urlResponse, editorSettingsUrl, EditorHttpMethod.GET)

        return editorSettings
    }

    /**
     * Reads cached editor settings.
     *
     * @return The cached settings, or `null` if not cached.
     */
    fun readEditorSettings(): EditorSettings? {
        val response = cache.getResponse(editorSettingsUrl, EditorHttpMethod.GET) ?: return null

        return runCatching {
            json.decodeFromString<EditorSettings>(response.data)
        }.getOrNull()
    }

    // MARK: GET Post Type

    /**
     * Fetches the schema for a specific post type.
     *
     * @param type The post type slug (e.g., "post", "page").
     * @return The response containing the post type schema.
     */
    internal suspend fun fetchPostType(type: String): EditorURLResponse {
        return perform(EditorHttpMethod.GET, buildPostTypeUrl(type))
    }

    /**
     * Reads cached post type schema.
     *
     * @param type The post type slug to look up.
     * @return The cached response, or `null` if not cached.
     */
    internal fun readPostType(type: String): EditorURLResponse? {
        return cache.getResponse(buildPostTypeUrl(type), EditorHttpMethod.GET)
    }

    private fun buildPostTypeUrl(type: String): String {
        return buildNamespacedUrl("/wp/v2/types/$type?context=edit")
    }

    // MARK: GET Active Theme

    /**
     * Fetches the active theme information.
     *
     * @return The response containing the active theme data.
     */
    internal suspend fun fetchActiveTheme(): EditorURLResponse {
        return perform(EditorHttpMethod.GET, activeThemeUrl)
    }

    /**
     * Reads cached active theme information.
     *
     * @return The cached response, or `null` if not cached.
     */
    internal fun readActiveTheme(): EditorURLResponse? {
        return cache.getResponse(activeThemeUrl, EditorHttpMethod.GET)
    }

    // MARK: OPTIONS Settings

    /**
     * Fetches site settings options (OPTIONS request).
     *
     * @return The response containing the settings schema.
     */
    internal suspend fun fetchSettingsOptions(): EditorURLResponse {
        return perform(EditorHttpMethod.OPTIONS, siteSettingsUrl)
    }

    /**
     * Reads cached settings options.
     *
     * @return The cached response, or `null` if not cached.
     */
    internal fun readSettingsOptions(): EditorURLResponse? {
        return cache.getResponse(siteSettingsUrl, EditorHttpMethod.OPTIONS)
    }

    // MARK: Post Types

    /**
     * Fetches all available post types.
     *
     * @return The response containing the post types data.
     */
    internal suspend fun fetchPostTypes(): EditorURLResponse {
        return perform(EditorHttpMethod.GET, postTypesUrl)
    }

    /**
     * Reads cached post types.
     *
     * @return The cached response, or `null` if not cached.
     */
    internal fun readPostTypes(): EditorURLResponse? {
        return cache.getResponse(postTypesUrl, EditorHttpMethod.GET)
    }

    private suspend fun perform(method: EditorHttpMethod, url: String): EditorURLResponse {
        val response = httpClient.perform(method, url)
        val urlResponse = EditorURLResponse(
            data = response.stringData,
            responseHeaders = response.headers
        )
        cache.store(urlResponse, url, method)
        return urlResponse
    }

    /** Builds a namespaced REST URL via the shared [RestUrlBuilder]. */
    private fun buildNamespacedUrl(path: String): String =
        RestUrlBuilder.namespaced(
            configuration.siteApiRoot,
            configuration.siteApiNamespace.firstOrNull(),
            path
        )

    companion object {
        private const val EDITOR_SETTINGS_PATH = "/wp-block-editor/v1/settings"
        private const val ACTIVE_THEME_PATH = "/wp/v2/themes?context=edit&status=active"
        private const val SITE_SETTINGS_PATH = "/wp/v2/settings"
        private const val POST_TYPES_PATH = "/wp/v2/types?context=view"
    }
}
