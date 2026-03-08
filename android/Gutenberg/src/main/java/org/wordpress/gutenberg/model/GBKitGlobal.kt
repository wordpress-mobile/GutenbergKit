package org.wordpress.gutenberg.model

import android.annotation.SuppressLint
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import org.wordpress.gutenberg.encodeForEditor

/**
 * Configuration object passed to the editor's JavaScript as a global variable.
 *
 * This class is serialized to JSON and injected into the WebView as `window.GBKit`,
 * providing the JavaScript code with all the information it needs to initialize
 * the editor and communicate with the WordPress REST API.
 */
@SuppressLint("UnsafeOptInUsageError")
@Serializable
data class GBKitGlobal(
    /** The site's base URL, or `null` if offline mode is enabled. */
    val siteURL: String?,
    /** The WordPress REST API root URL, or `null` if offline mode is enabled. */
    val siteApiRoot: String?,
    /**
     * Namespace segments to insert into API request paths.
     *
     * Used primarily for WordPress.com sites where API requests need a site identifier.
     * The first namespace is inserted after the first two path segments for eligible requests.
     *
     * For example, with `["sites/123"]`, a request to `/wp/v2/posts` becomes `/wp/v2/sites/123/posts`.
     *
     * All namespaces are used to detect whether a path already contains a namespace (to avoid
     * double-insertion), but only the first one is used for insertion.
     */
    val siteApiNamespace: List<String>,
    /**
     * API paths that should not have the namespace inserted.
     *
     * Paths starting with any of these prefixes will bypass the namespace insertion middleware.
     */
    val namespaceExcludedPaths: List<String>,
    /** The authorization header value for authenticated API requests. */
    val authHeader: String,
    /** Whether to apply theme styles to the editor. */
    val themeStyles: Boolean,
    /** Whether to load plugin assets. */
    val plugins: Boolean,
    /** Whether to use the native block inserter instead of the web-based one. */
    val enableNativeBlockInserter: Boolean = false,
    /** Whether to hide the post title field in the editor. */
    val hideTitle: Boolean,
    /** The locale identifier for translations (e.g., `fr`). */
    val locale: String,
    /** The post being edited. */
    val post: Post,
    /** The logging level for JavaScript console output. */
    val logLevel: String = "debug",
    /** Whether to log network requests in the JavaScript console. */
    val enableNetworkLogging: Boolean,
    /** Port the local HTTP server is listening on for native media uploads. */
    val nativeUploadPort: Int? = null,
    /** Per-session auth token for requests to the local upload server. */
    val nativeUploadToken: String? = null,
    /** The raw editor settings JSON from the WordPress REST API. */
    val editorSettings: JsonElement?,
    /** Pre-fetched API responses JSON for faster editor initialization. */
    val preloadData: JsonElement? = null
) {
    /**
     * The post data passed to the editor.
     */
    @Serializable
    data class Post(
        /** The post ID, or -1 for new posts. */
        val id: Int,
        /** The post type (e.g., `post`, `page`). */
        val type: String,
        /** The post status (e.g., `draft`, `publish`, `pending`). */
        val status: String,
        /** The post title (URL-encoded). */
        val title: String,
        /** The post content (URL-encoded Gutenberg block markup). */
        val content: String
    )

    companion object {
        private val json = Json { encodeDefaults = true }

        /**
         * Creates a global configuration from an editor configuration and dependencies.
         *
         * @param configuration The editor configuration.
         * @param dependencies The pre-fetched editor dependencies.
         * @param nativeUploadPort Port of the local upload server, or null if not running.
         * @param nativeUploadToken Auth token for the local upload server, or null if not running.
         */
        fun fromConfiguration(
            configuration: EditorConfiguration,
            dependencies: EditorDependencies?,
            nativeUploadPort: Int? = null,
            nativeUploadToken: String? = null
        ): GBKitGlobal {
            return GBKitGlobal(
                siteURL = configuration.siteURL.ifEmpty { null },
                siteApiRoot = configuration.siteApiRoot.ifEmpty { null },
                siteApiNamespace = configuration.siteApiNamespace.toList(),
                namespaceExcludedPaths = configuration.namespaceExcludedPaths.toList(),
                authHeader = configuration.authHeader,
                themeStyles = configuration.themeStyles,
                plugins = configuration.plugins,
                hideTitle = configuration.hideTitle,
                locale = configuration.locale ?: "en",
                post = Post(
                    id = configuration.postId ?: -1,
                    type = configuration.postType,
                    status = configuration.postStatus ?: "draft",
                    title = configuration.title.encodeForEditor(),
                    content = configuration.content.encodeForEditor()
                ),
                enableNetworkLogging = configuration.enableNetworkLogging,
                nativeUploadPort = nativeUploadPort,
                nativeUploadToken = nativeUploadToken,
                editorSettings = dependencies?.editorSettings?.jsonValue,
                preloadData = dependencies?.preloadList?.build()
            )
        }
    }

    /**
     * Serializes the configuration to a JSON string for injection into JavaScript.
     *
     * @return A JSON string representation of this object.
     */
    fun toJsonString(): String {
        return json.encodeToString(this)
    }
}
