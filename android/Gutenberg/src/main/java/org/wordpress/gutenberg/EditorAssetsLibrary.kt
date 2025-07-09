package org.wordpress.gutenberg

import android.content.Context
import android.util.Log
import kotlinx.coroutines.*
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
        private const val CACHE_EXPIRY_DAYS = 7
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
                ?: "${configuration.siteApiRoot}wpcom/v2/editor-assets"

            val connection = URL(endpoint).openConnection() as HttpURLConnection
            connection.requestMethod = "GET"

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
        }

    /**
     * Returns the manifest for use by the editor JavaScript
     */
    suspend fun manifestContentForEditor(headers: Map<String, String> = emptyMap()): String =
        withContext(Dispatchers.IO) {
            // Simply return the original manifest - no URL modification needed for Android
            loadManifestContent(headers)
        }


    /**
     * Caches a single asset from the given URL
     */
    suspend fun cacheAsset(httpURL: String): File = withContext(Dispatchers.IO) {
        if (!shouldCacheUrl(httpURL)) {
            throw IllegalArgumentException("Unsupported URL for caching: $httpURL")
        }

        val localFile = getLocalCacheFile(httpURL)

        // Check if already cached and not expired
        if (localFile.exists()) {
            val age = System.currentTimeMillis() - localFile.lastModified()
            val maxAge = CACHE_EXPIRY_DAYS * 24 * 60 * 60 * 1000L
            if (age < maxAge) {
                return@withContext localFile
            }
        }

        // Fetch and cache
        val connection = URL(httpURL).openConnection() as HttpURLConnection
        connection.requestMethod = "GET"
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
    }

    /**
     * Gets cached asset data if available
     */
    fun getCachedAsset(url: String): ByteArray? {
        val localFile = getLocalCacheFile(url)
        if (!localFile.exists()) {
            return null
        }

        // Check expiry
        val age = System.currentTimeMillis() - localFile.lastModified()
        val maxAge = CACHE_EXPIRY_DAYS * 24 * 60 * 60 * 1000L
        if (age > maxAge) {
            localFile.delete()
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
