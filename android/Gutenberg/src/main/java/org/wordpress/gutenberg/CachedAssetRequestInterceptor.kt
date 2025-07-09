package org.wordpress.gutenberg

import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.util.Log
import kotlinx.coroutines.runBlocking
import java.io.ByteArrayInputStream

class CachedAssetRequestInterceptor(
    private val library: EditorAssetsLibrary,
    private val allowedHosts: Set<String> = emptySet()
) : GutenbergRequestInterceptor {

    companion object {
        private const val TAG = "CachedAssetInterceptor"
        private val MIME_TYPES = mapOf(
            ".js" to "application/javascript",
            ".css" to "text/css",
            ".map" to "application/json"
        )
        private val CACHEABLE_EXTENSIONS = setOf(".js", ".css", ".js.map")
    }

    override fun canIntercept(request: WebResourceRequest): Boolean {
        val url = request.url ?: return false
        val urlString = url.toString()

        // Always intercept manifest requests to let us handle caching logic
        if (urlString.contains("/wpcom/v2/") && urlString.contains("/editor-assets")) {
            return true
        }

        // Only intercept if host is in allowed list (if specified)
        if (allowedHosts.isNotEmpty() && url.host !in allowedHosts) {
            return false
        }

        // Only intercept cacheable asset types
        return CACHEABLE_EXTENSIONS.any { urlString.contains(it) }
    }

    override fun handleRequest(request: WebResourceRequest): WebResourceResponse? {
        val url = request.url?.toString() ?: return null

        try {
            // Handle manifest endpoint requests
            if (url.contains("/wpcom/v2/") && url.contains("/editor-assets")) {
                Log.d(TAG, "Manifest request detected: $url - letting WebView handle normally")
                // Let WebView make the request normally, we'll cache assets as they're requested
                return null
            }

            // Handle asset caching - only serve if already cached
            val cachedData = library.getCachedAsset(url)
            if (cachedData != null) {
                Log.d(TAG, "Serving cached asset: $url")
                return createResponse(url, cachedData)
            }

            // Not cached - let WebView fetch normally and cache in background
            Log.d(TAG, "Asset not cached, will cache in background: $url")
            // Start background caching for next time
            library.cacheAssetInBackground(url)
            
            return null // Let WebView handle the request normally
        } catch (e: Exception) {
            Log.e(TAG, "Error handling request: $url", e)
            return null
        }
    }

    fun shutdown() {
        library.shutdown()
    }

    private fun createResponse(url: String, data: ByteArray): WebResourceResponse {
        val mimeType =
            MIME_TYPES.entries.find { url.contains(it.key) }?.value ?: "application/octet-stream"
        return WebResourceResponse(
            mimeType,
            "UTF-8",
            ByteArrayInputStream(data)
        )
    }
}
