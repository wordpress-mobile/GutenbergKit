package org.wordpress.gutenberg.model

import android.annotation.SuppressLint
import android.net.Uri
import kotlinx.serialization.Serializable
import org.jsoup.Jsoup

/**
 * A processed editor asset manifest with parsed URLs ready for downloading.
 *
 * This class transforms a `RemoteEditorAssetManifest` by parsing the raw HTML
 * to extract individual script and stylesheet URLs. It preserves the original
 * HTML for later injection into the editor WebView.
 *
 * The manifest is used to:
 * 1. Determine which assets need to be downloaded and cached
 * 2. Provide the raw HTML for rendering in the editor (with URL rewriting)
 * 3. Specify which block types are allowed for this site
 */
@SuppressLint("UnsafeOptInUsageError")
@Serializable
data class LocalEditorAssetManifest(
    /** URLs of all external scripts that need to be cached locally. */
    val scripts: List<String>,
    /** URLs of all external stylesheets that need to be cached locally. */
    val styles: List<String>,
    /** The block type identifiers that can be used in the editor (e.g., "core/paragraph"). */
    val allowedBlockTypes: List<String>,
    /** The original HTML containing `<script>` tags from the server. */
    val rawScripts: String,
    /** The original HTML containing `<link>` stylesheet tags from the server. */
    val rawStyles: String,
    /** A SHA-256 checksum used to detect when assets need to be re-downloaded. */
    val checksum: String
) {
    /** All asset URLs (scripts and styles) that need to be cached. */
    val assetUrls: List<String>
        get() = scripts + styles

    companion object {
        /**
         * Creates a local manifest by parsing a remote manifest's HTML.
         *
         * This operation involves HTML parsing and is expensive. The results
         * should be cached.
         *
         * @param remoteManifest The raw manifest from the server.
         * @throws Exception An error if HTML parsing fails.
         */
        fun fromRemoteManifest(remoteManifest: RemoteEditorAssetManifest): LocalEditorAssetManifest {
            val html = """
                <html>
                    <head>
                    ${remoteManifest.scripts}
                    ${remoteManifest.styles}
                    </head>
                    <body></body>
                </html>
            """.trimIndent()

            val document = Jsoup.parse(html)

            val scripts = document.select("script[src]")
                .mapNotNull { it.attr("src") }
                .map { normalizeAssetLink(it) }

            val styles = document.select("""link[rel="stylesheet"][href]""")
                .mapNotNull { it.attr("href") }
                .map { normalizeAssetLink(it) }

            return LocalEditorAssetManifest(
                scripts = scripts,
                styles = styles,
                allowedBlockTypes = remoteManifest.allowedBlockTypes,
                rawScripts = remoteManifest.scripts,
                rawStyles = remoteManifest.styles,
                checksum = remoteManifest.checksum
            )
        }

        /**
         * Normalizes protocol-relative URLs (e.g., `//example.com/script.js`) to use HTTPS.
         *
         * @param link The URL string to normalize.
         * @return The normalized URL string with an explicit scheme.
         */
        private fun normalizeAssetLink(link: String): String {
            return if (link.startsWith("//")) {
                "https:$link"
            } else {
                link
            }
        }

        /** An empty manifest for sites that don't support the editor-assets endpoint. */
        val empty = LocalEditorAssetManifest(
            scripts = emptyList(),
            styles = emptyList(),
            allowedBlockTypes = emptyList(),
            rawScripts = "",
            rawStyles = "",
            checksum = "empty"
        )
    }

    /**
     * Renders the manifest's scripts and styles as HTML with rewritten URLs that reference
     * the application's custom URL scheme.
     *
     * @param urlScheme The scheme to use (e.g., "https" or a custom scheme).
     * @param shouldUsePlugins Whether to include plugin assets.
     * @param shouldUseThemeStyles Whether to include theme styles.
     * @return A RawManifest with rewritten URLs, or empty if both flags are false.
     */
    fun buildEditorRepresentation(
        urlScheme: String,
        shouldUsePlugins: Boolean,
        shouldUseThemeStyles: Boolean
    ): RemoteEditorAssetManifest.RawManifest {
        // If this site doesn't use plugins or theme styles, there's no work to do here.
        if (!shouldUsePlugins && !shouldUseThemeStyles) {
            return RemoteEditorAssetManifest.RawManifest.empty
        }

        val html = """
            <html>
                <head>${this.rawStyles}</head>
                <body>${this.rawScripts}</body>
            </html>
        """.trimIndent()

        val document = Jsoup.parse(html)

        for (script in document.select("script[src]")) {
            val src = script.attr("src")
            val rewrittenLink = resolveAssetLink(src, urlScheme)
            script.attr("src", rewrittenLink)
        }

        for (stylesheet in document.select("""link[rel="stylesheet"][href]""")) {
            val href = stylesheet.attr("href")
            val rewrittenLink = resolveAssetLink(href, urlScheme)
            stylesheet.attr("href", rewrittenLink)
        }

        val scriptsHtml = document.head()?.html() ?: ""
        val stylesHtml = document.body()?.html() ?: ""

        return RemoteEditorAssetManifest.RawManifest(
            scripts = scriptsHtml,
            styles = stylesHtml,
            allowedBlockTypes = this.allowedBlockTypes
        )
    }

    /**
     * Rewrites an asset URL to use the specified scheme.
     *
     * @param link The original asset URL string.
     * @param scheme The scheme to use.
     * @return The URL string with the new scheme, or the original if parsing fails.
     */
    private fun resolveAssetLink(link: String, scheme: String): String {
        return try {
            val uri = Uri.parse(link)
            if (uri.host == null || uri.path == null) {
                return link
            }
            uri.buildUpon().scheme(scheme).build().toString()
        } catch (e: Exception) {
            link
        }
    }
}
