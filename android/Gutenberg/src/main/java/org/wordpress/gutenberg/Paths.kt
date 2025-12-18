package org.wordpress.gutenberg

import android.content.Context
import org.wordpress.gutenberg.model.EditorConfiguration
import java.io.File

/**
 * Utility object for constructing storage and cache directory paths.
 */
object Paths {
    /**
     * Returns the default storage root directory for GutenbergKit.
     *
     * This is typically in the app's files directory.
     *
     * @param context The Android context.
     * @return The default storage root directory.
     */
    fun defaultStorageRoot(context: Context): File {
        return File(context.filesDir, "GutenbergKit")
    }

    /**
     * Returns the storage root directory for a specific site configuration.
     *
     * @param context The Android context.
     * @param configuration The editor configuration.
     * @return The site-specific storage directory.
     */
    fun storageRoot(context: Context, configuration: EditorConfiguration): File {
        return File(defaultStorageRoot(context), configuration.siteId)
    }

    /**
     * Returns the storage root directory for a specific site configuration.
     *
     * @param baseDir The base directory to use instead of context.filesDir.
     * @param configuration The editor configuration.
     * @return The site-specific storage directory.
     */
    fun storageRoot(baseDir: File, configuration: EditorConfiguration): File {
        return File(File(baseDir, "GutenbergKit"), configuration.siteId)
    }

    /**
     * Returns the default cache root directory for GutenbergKit.
     *
     * This is typically in the app's cache directory.
     *
     * @param context The Android context.
     * @return The default cache root directory.
     */
    fun defaultCacheRoot(context: Context): File {
        return File(context.cacheDir, "GutenbergKit")
    }

    /**
     * Returns the cache root directory for a specific site configuration.
     *
     * @param context The Android context.
     * @param configuration The editor configuration.
     * @return The site-specific cache directory.
     */
    fun cacheRoot(context: Context, configuration: EditorConfiguration): File {
        return File(defaultCacheRoot(context), configuration.siteId)
    }

    /**
     * Returns the cache root directory for a specific site configuration.
     *
     * @param baseDir The base directory to use instead of context.cacheDir.
     * @param configuration The editor configuration.
     * @return The site-specific cache directory.
     */
    fun cacheRoot(baseDir: File, configuration: EditorConfiguration): File {
        return File(File(baseDir, "GutenbergKit"), configuration.siteId)
    }
}
