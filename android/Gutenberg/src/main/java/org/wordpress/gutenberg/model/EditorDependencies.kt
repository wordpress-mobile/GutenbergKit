package org.wordpress.gutenberg.model

/**
 * A collection of data fetched from the WordPress REST API required to initialize the editor.
 *
 * This class bundles together all the pre-fetched dependencies needed before the editor
 * can be displayed. Fetching these dependencies ahead of time allows the editor to load
 * quickly without blocking on network requests.
 *
 * Dependencies include:
 * - Editor settings (theme styles, colors, typography, etc.)
 * - Cached plugin/theme assets (JavaScript and CSS files)
 * - Preloaded API responses (post types, taxonomies, etc.)
 */
data class EditorDependencies(
    /** Configuration and styling information for the editor. */
    val editorSettings: EditorSettings,
    /** Cached JavaScript and CSS assets for plugins and themes. */
    val assetBundle: EditorAssetBundle,
    /**
     * Pre-fetched API responses to avoid network requests during editor initialization.
     *
     * This is `null` if preloading is disabled or no preload data is available.
     */
    val preloadList: EditorPreloadList?
) {
    companion object {
        /** Empty dependencies for use when no pre-fetched data is available. */
        val empty = EditorDependencies(
            editorSettings = EditorSettings.undefined,
            assetBundle = EditorAssetBundle.empty,
            preloadList = null
        )
    }
}
