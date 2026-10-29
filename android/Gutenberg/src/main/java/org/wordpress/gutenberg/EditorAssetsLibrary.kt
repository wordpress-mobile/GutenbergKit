package org.wordpress.gutenberg

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.wordpress.gutenberg.model.EditorConfiguration
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

class EditorAssetsLibrary(
    private val context: Context,
    private val configuration: EditorConfiguration
) {
    private val cacheDir: File = getCacheDirectory()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    companion object {
        private const val TAG = "EditorAssetsLibrary"
        private const val CACHE_CLEANUP_INTERVAL_DAYS = 7
        private val CACHEABLE_EXTENSIONS = setOf(".js", ".css", ".js.map")
    }

    init {
        if (!cacheDir.exists()) {
            cacheDir.mkdirs()
        }
    }

    /**
     * Loads the manifest content from the editor assets endpoint
     */
    suspend fun loadManifestContent(headers: Map<String, String> = emptyMap()): String =
        withContext(Dispatchers.IO) {
            val endpoint = configuration.editorAssetsEndpoint
                ?: configuration.siteApiRoot.appendingRestPath("/wpcom/v2/editor-assets")

            val connection = URL(endpoint).openConnection() as HttpURLConnection
            try {
                connection.requestMethod = "GET"

                val defaultUserAgent = System.getProperty("http.agent") ?: ""
                connection.setRequestProperty("User-Agent", "$defaultUserAgent GutenbergKit/${GutenbergKitVersion.VERSION}")

                // Set headers from configuration
                if (configuration.authHeader.isNotEmpty()) {
                    connection.setRequestProperty("Authorization", configuration.authHeader)
                }

                // Set headers from request
                headers.forEach { (key, value) ->
                    connection.setRequestProperty(key, value)
                }

                connection.connectTimeout = 30000
                connection.readTimeout = 30000

                if (connection.responseCode in 200..299) {
                    connection.inputStream.use { it.bufferedReader().readText() }
                } else {
                    throw Exception("Failed to fetch manifest: ${connection.responseCode}")
                }
            } finally {
                connection.disconnect()
            }
        }

    /**
     * Returns the manifest for use by the editor JavaScript
     */
    suspend fun manifestContentForEditor(headers: Map<String, String> = emptyMap()): String =
        withContext(Dispatchers.IO) {
            val manifestJson = loadManifestContent(headers)

            // Trigger periodic cache cleanup in background
            // Assets are versioned, so old versions become unused naturally over time
            scope.launch {
                cleanupOldCache()
            }

            manifestJson
        }

    /**
     * Caches a single asset from the given URL
     */
    suspend fun cacheAsset(httpURL: String): File = withContext(Dispatchers.IO) {
        if (!shouldCacheUrl(httpURL)) {
            throw IllegalArgumentException("Unsupported URL for caching: $httpURL")
        }

        val localFile = getLocalCacheFile(httpURL)

        // If already cached, return existing file (versioned URLs change when updated)
        if (localFile.exists()) {
            return@withContext localFile
        }

        // Fetch and cache
        val connection = URL(httpURL).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "GET"

            val defaultUserAgent = System.getProperty("http.agent") ?: ""
            connection.setRequestProperty("User-Agent", "$defaultUserAgent GutenbergKit/${GutenbergKitVersion.VERSION}")

            connection.connectTimeout = 30000
            connection.readTimeout = 30000

            if (connection.responseCode in 200..299) {
                localFile.parentFile?.mkdirs()
                connection.inputStream.use { input ->
                    localFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }
                Log.d(TAG, "Cached asset: $httpURL (${localFile.length()} bytes)")
                localFile
            } else {
                throw Exception("Failed to fetch asset: $httpURL (${connection.responseCode})")
            }
        } finally {
            connection.disconnect()
        }
    }

    /**
     * Gets cached asset data if available
     */
    fun getCachedAsset(url: String): ByteArray? {
        val localFile = getLocalCacheFile(url)
        if (!localFile.exists()) {
            return null
        }

        return try {
            localFile.readBytes()
        } catch (e: Exception) {
            Log.e(TAG, "Error reading cached asset: $url", e)
            null
        }
    }

    fun clearCache() {
        cacheDir.deleteRecursively()
        cacheDir.mkdirs()
    }

    /**
     * Cache an asset in the background without blocking
     */
    fun cacheAssetInBackground(url: String) {
        if (!shouldCacheUrl(url)) return

        scope.launch {
            try {
                cacheAsset(url)
                Log.d(TAG, "Background cached: $url")
            } catch (e: Exception) {
                Log.w(TAG, "Failed to background cache: $url", e)
            }
        }
    }

    /**
     * Cleans up old cached files to prevent unlimited storage growth.
     * Since assets are versioned (URLs change when updated), old versions
     * become unused naturally. We can safely remove files older than the
     * cleanup interval without affecting functionality.
     */
    private fun cleanupOldCache() {
        try {
            val cutoffTime = System.currentTimeMillis() - (CACHE_CLEANUP_INTERVAL_DAYS * 24 * 60 * 60 * 1000L)
            var deletedCount = 0
            var deletedSize = 0L

            cacheDir.listFiles()?.forEach { file ->
                if (file.isFile && file.lastModified() < cutoffTime) {
                    val size = file.length()
                    if (file.delete()) {
                        deletedCount++
                        deletedSize += size
                    }
                }
            }

            if (deletedCount > 0) {
                Log.d(TAG, "Cache cleanup: deleted $deletedCount files (${deletedSize / 1024}KB)")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Cache cleanup failed", e)
        }
    }

    fun shutdown() {
        scope.cancel()
    }

    private fun shouldCacheUrl(url: String): Boolean {
        return url.startsWith("http") && CACHEABLE_EXTENSIONS.any { url.contains(it) }
    }

    private fun getCacheDirectory(): File {
        // Match iOS's directory structure
        var siteName = "shared"

        if (configuration.siteURL.isNotEmpty()) {
            try {
                val url = URL(configuration.siteURL)
                val host = url.host.replace(":", "-")
                val path = url.path.replace("/", "-").trim('-')
                siteName = if (path.isEmpty()) host else "$host-$path"

                // Remove illegal characters
                siteName = siteName.replace(Regex("[/:\\\\?%*|\"<>]"), "-")
            } catch (e: Exception) {
                Log.w(TAG, "Failed to parse site URL for cache directory", e)
            }
        }

        return File(context.filesDir, "editor-caches/$siteName")
    }

    private fun getLocalCacheFile(url: String): File {
        // Generate unique filename similar to iOS
        val path = URL(url).path.trimStart('/')
        val nameWithoutExt = path.substringBeforeLast('.')
        val extension = path.substringAfterLast('.', "")

        val hash = MessageDigest.getInstance("SHA-256")
            .digest(url.toByteArray())
            .fold("") { str, it -> str + "%02x".format(it) }

        val filename = if (extension.isEmpty()) {
            "$nameWithoutExt$hash"
        } else {
            "$nameWithoutExt$hash.$extension"
        }

        return File(cacheDir, filename)
    }
}
