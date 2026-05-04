package org.wordpress.gutenberg.model

import android.content.Context
import android.os.Parcelable
import kotlinx.parcelize.IgnoredOnParcel
import kotlinx.parcelize.Parcelize
import java.net.URI
import java.util.Locale
import java.util.UUID

@Parcelize
data class EditorConfiguration(
    val title: String,
    val content: String,
    val postId: UInt?,
    val postType: PostTypeDetails,
    val postStatus: String,
    val themeStyles: Boolean,
    val plugins: Boolean,
    val hideTitle: Boolean,
    val siteURL: String,
    val siteApiRoot: String,
    val siteApiNamespace: Array<String>,
    val namespaceExcludedPaths: Array<String>,
    val authHeader: String,
    val editorSettings: String?,
    val locale: String?,
    val cookies: Map<String, String>,
    val enableAssetCaching: Boolean = false,
    val cachedAssetHosts: Set<String> = emptySet(),
    val editorAssetsEndpoint: String? = null,
    val enableNetworkLogging: Boolean = false,
    var enableOfflineMode: Boolean = false,
    /**
     * When true, the web editor delegates block inserter UI to a native
     * bottom sheet owned by [org.wordpress.gutenberg.GutenbergView] instead of
     * showing the built-in Gutenberg inserter. Defaults to false so existing
     * consumers keep the web-based inserter until they opt in.
     */
    val enableNativeBlockInserter: Boolean = false
): Parcelable {

    /**
     * A site ID derived from the URL that can be used in file system paths.
     *
     * Returns the host portion of the siteURL, or a UUID if the URL has no host.
     */
    @IgnoredOnParcel
    val siteId: String by lazy {
        try {
            URI(siteURL).host ?: UUID.randomUUID().toString()
        } catch (e: Exception) {
            UUID.randomUUID().toString()
        }
    }
    companion object {
        @JvmStatic
        fun builder(siteURL: String, siteApiRoot: String, postType: PostTypeDetails = PostTypeDetails.post): Builder = Builder(siteURL, siteApiRoot, postType = postType)

        @JvmStatic
        fun bundled(): EditorConfiguration = Builder("https://example.com", "https://example.com/wp-json/", PostTypeDetails.post)
            .setEnableOfflineMode(true)
            .build()
    }

    class Builder(private var siteURL: String, private var siteApiRoot: String, private var postType: PostTypeDetails) {
        private var title: String = ""
        private var content: String = ""
        private var postId: UInt? = null
        private var postStatus: String = "draft"
        private var themeStyles: Boolean = false
        private var plugins: Boolean = false
        private var hideTitle: Boolean = false
        private var siteApiNamespace: Array<String> = arrayOf()
        private var namespaceExcludedPaths: Array<String> = arrayOf()
        private var authHeader: String = ""
        private var editorSettings: String? = null
        private var locale: String? = "en"
        private var cookies: Map<String, String> = mapOf()
        private var enableAssetCaching: Boolean = false
        private var cachedAssetHosts: Set<String> = emptySet()
        private var editorAssetsEndpoint: String? = null
        private var enableNetworkLogging: Boolean = false
        private var enableOfflineMode: Boolean = false
        private var enableNativeBlockInserter: Boolean = false

        fun setTitle(title: String) = apply { this.title = title }
        fun setContent(content: String) = apply { this.content = content }
        fun setPostId(postId: UInt?) = apply { this.postId = postId?.takeIf { it != 0u } }
        fun setPostType(postType: PostTypeDetails) = apply { this.postType = postType }
        fun setPostStatus(postStatus: String) = apply { this.postStatus = postStatus }
        fun setThemeStyles(themeStyles: Boolean) = apply { this.themeStyles = themeStyles }
        fun setPlugins(plugins: Boolean) = apply { this.plugins = plugins }
        fun setHideTitle(hideTitle: Boolean) = apply { this.hideTitle = hideTitle }
        fun setSiteURL(siteURL: String) = apply { this.siteURL = siteURL }
        fun setSiteApiRoot(siteApiRoot: String) = apply { this.siteApiRoot = siteApiRoot }
        fun setSiteApiNamespace(siteApiNamespace: Array<String>) = apply { this.siteApiNamespace = siteApiNamespace }
        fun setNamespaceExcludedPaths(namespaceExcludedPaths: Array<String>) = apply { this.namespaceExcludedPaths = namespaceExcludedPaths }
        fun setAuthHeader(authHeader: String) = apply { this.authHeader = authHeader }
        fun setEditorSettings(editorSettings: String?) = apply { this.editorSettings = editorSettings }
        fun setLocale(locale: String?) = apply { this.locale = locale }

        /**
         * Resolves [locale] against the bundled translations and stores the
         * resulting tag for serialization.
         *
         * Prefer this overload when the locale comes from a platform API
         * (e.g. [android.content.res.Configuration.getLocales] or the user's
         * per-app locale). It runs the resolution chain — full tag →
         * language-only tag → `en` — using the manifest shipped in this
         * library's assets, so a device configured for `pt_BR` correctly
         * lands on the `pt-br` bundle instead of silently falling through
         * to English.
         *
         * @param context Used to read the shipped translations manifest
         *                from this library's assets.
         * @param locale  The platform locale to resolve.
         */
        fun setLocale(context: Context, locale: Locale) = apply {
            this.locale = LocaleResolver.fromAssets(context).resolve(locale)
        }
        fun setCookies(cookies: Map<String, String>) = apply { this.cookies = cookies }
        fun setEnableAssetCaching(enableAssetCaching: Boolean) = apply { this.enableAssetCaching = enableAssetCaching }
        fun setCachedAssetHosts(cachedAssetHosts: Set<String>) = apply { this.cachedAssetHosts = cachedAssetHosts }
        fun setEditorAssetsEndpoint(editorAssetsEndpoint: String?) = apply { this.editorAssetsEndpoint = editorAssetsEndpoint }
        fun setEnableNetworkLogging(enableNetworkLogging: Boolean) = apply { this.enableNetworkLogging = enableNetworkLogging }
        fun setEnableOfflineMode(enableOfflineMode: Boolean) = apply { this.enableOfflineMode = enableOfflineMode }
        fun setEnableNativeBlockInserter(enabled: Boolean) = apply {
            this.enableNativeBlockInserter = enabled
        }

        fun build(): EditorConfiguration = EditorConfiguration(
            title = title,
            content = content,
            postId = postId?.takeIf { it != 0u },
            postType = postType,
            postStatus = postStatus,
            themeStyles = themeStyles,
            plugins = plugins,
            hideTitle = hideTitle,
            siteURL = siteURL,
            siteApiRoot = siteApiRoot,
            siteApiNamespace = siteApiNamespace,
            namespaceExcludedPaths = namespaceExcludedPaths,
            authHeader = authHeader,
            editorSettings = editorSettings,
            locale = locale,
            cookies = cookies,
            enableAssetCaching = enableAssetCaching,
            cachedAssetHosts = cachedAssetHosts,
            editorAssetsEndpoint = editorAssetsEndpoint,
            enableNetworkLogging = enableNetworkLogging,
            enableOfflineMode = enableOfflineMode,
            enableNativeBlockInserter = enableNativeBlockInserter
        )
    }

    /**
     * Creates a new Builder pre-populated with all values from this configuration.
     *
     * This allows modifying specific fields while preserving others.
     */
    fun toBuilder(): Builder = Builder(siteURL, siteApiRoot, postType)
        .setTitle(title)
        .setContent(content)
        .setPostId(postId)
        .setPostStatus(postStatus)
        .setThemeStyles(themeStyles)
        .setPlugins(plugins)
        .setHideTitle(hideTitle)
        .setSiteApiNamespace(siteApiNamespace)
        .setNamespaceExcludedPaths(namespaceExcludedPaths)
        .setAuthHeader(authHeader)
        .setEditorSettings(editorSettings)
        .setLocale(locale)
        .setCookies(cookies)
        .setEnableAssetCaching(enableAssetCaching)
        .setCachedAssetHosts(cachedAssetHosts)
        .setEditorAssetsEndpoint(editorAssetsEndpoint)
        .setEnableNetworkLogging(enableNetworkLogging)
        .setEnableOfflineMode(enableOfflineMode)
        .setEnableNativeBlockInserter(enableNativeBlockInserter)

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false

        other as EditorConfiguration

        if (title != other.title) return false
        if (content != other.content) return false
        if (postId != other.postId) return false
        if (postType != other.postType) return false
        if (postStatus != other.postStatus) return false
        if (themeStyles != other.themeStyles) return false
        if (plugins != other.plugins) return false
        if (hideTitle != other.hideTitle) return false
        if (siteURL != other.siteURL) return false
        if (siteApiRoot != other.siteApiRoot) return false
        if (!siteApiNamespace.contentEquals(other.siteApiNamespace)) return false
        if (!namespaceExcludedPaths.contentEquals(other.namespaceExcludedPaths)) return false
        if (authHeader != other.authHeader) return false
        if (editorSettings != other.editorSettings) return false
        if (locale != other.locale) return false
        if (cookies != other.cookies) return false
        if (enableAssetCaching != other.enableAssetCaching) return false
        if (cachedAssetHosts != other.cachedAssetHosts) return false
        if (editorAssetsEndpoint != other.editorAssetsEndpoint) return false
        if (enableNetworkLogging != other.enableNetworkLogging) return false
        if (enableOfflineMode != other.enableOfflineMode) return false
        if (enableNativeBlockInserter != other.enableNativeBlockInserter) return false
        if (siteId != other.siteId) return false

        return true
    }

    override fun hashCode(): Int {
        var result = title.hashCode()
        result = 31 * result + content.hashCode()
        result = 31 * result + (postId?.toInt() ?: 0)
        result = 31 * result + postType.hashCode()
        result = 31 * result + postStatus.hashCode()
        result = 31 * result + themeStyles.hashCode()
        result = 31 * result + plugins.hashCode()
        result = 31 * result + hideTitle.hashCode()
        result = 31 * result + siteURL.hashCode()
        result = 31 * result + siteApiRoot.hashCode()
        result = 31 * result + siteApiNamespace.contentHashCode()
        result = 31 * result + namespaceExcludedPaths.contentHashCode()
        result = 31 * result + authHeader.hashCode()
        result = 31 * result + (editorSettings?.hashCode() ?: 0)
        result = 31 * result + (locale?.hashCode() ?: 0)
        result = 31 * result + cookies.hashCode()
        result = 31 * result + enableAssetCaching.hashCode()
        result = 31 * result + cachedAssetHosts.hashCode()
        result = 31 * result + (editorAssetsEndpoint?.hashCode() ?: 0)
        result = 31 * result + enableNetworkLogging.hashCode()
        result = 31 * result + enableOfflineMode.hashCode()
        result = 31 * result + enableNativeBlockInserter.hashCode()
        result = 31 * result + siteId.hashCode()
        return result
    }
}
