package org.wordpress.gutenberg

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
    val authHeader: String
) {
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
            authHeader = authHeader
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
        return result
    }
}
