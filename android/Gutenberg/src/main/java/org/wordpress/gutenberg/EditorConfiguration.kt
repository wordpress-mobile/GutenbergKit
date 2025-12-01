package org.wordpress.gutenberg

import android.os.Parcelable
import kotlinx.parcelize.Parcelize

@Parcelize
open class EditorConfiguration constructor(
    val title: String,
    val content: String,
    val postId: Int?,
    val postType: String?,
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
    val enableNetworkLogging: Boolean = false
): Parcelable {
    companion object {
        @JvmStatic
        fun builder(): Builder = Builder()
    }

    class Builder {
        private var title: String = ""
        private var content: String = ""
        private var postId: Int? = null
        private var postType: String? = null
        private var themeStyles: Boolean = false
        private var plugins: Boolean = false
        private var hideTitle: Boolean = false
        private var siteURL: String = ""
        private var siteApiRoot: String = ""
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

        fun setTitle(title: String) = apply { this.title = title }
        fun setContent(content: String) = apply { this.content = content }
        fun setPostId(postId: Int?) = apply { this.postId = postId }
        fun setPostType(postType: String?) = apply { this.postType = postType }
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
        fun setCookies(cookies: Map<String, String>) = apply { this.cookies = cookies }
        fun setEnableAssetCaching(enableAssetCaching: Boolean) = apply { this.enableAssetCaching = enableAssetCaching }
        fun setCachedAssetHosts(cachedAssetHosts: Set<String>) = apply { this.cachedAssetHosts = cachedAssetHosts }
        fun setEditorAssetsEndpoint(editorAssetsEndpoint: String?) = apply { this.editorAssetsEndpoint = editorAssetsEndpoint }
        fun setEnableNetworkLogging(enableNetworkLogging: Boolean) = apply { this.enableNetworkLogging = enableNetworkLogging }

        fun build(): EditorConfiguration = EditorConfiguration(
            title = title,
            content = content,
            postId = postId,
            postType = postType,
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
            enableNetworkLogging = enableNetworkLogging
        )
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false

        other as EditorConfiguration

        if (title != other.title) return false
        if (content != other.content) return false
        if (postId != other.postId) return false
        if (postType != other.postType) return false
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

        return true
    }

    override fun hashCode(): Int {
        var result = title.hashCode()
        result = 31 * result + content.hashCode()
        result = 31 * result + (postId ?: 0)
        result = 31 * result + (postType?.hashCode() ?: 0)
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
        return result
    }
}
