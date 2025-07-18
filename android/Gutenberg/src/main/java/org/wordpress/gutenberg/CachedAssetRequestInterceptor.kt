package org.wordpress.gutenberg

import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.util.Log
import java.io.ByteArrayInputStream

class CachedAssetRequestInterceptor(
    private val library: EditorAssetsLibrary,
    private val allowedHosts: Set<String> = emptySet()
) : GutenbergRequestInterceptor {
    companion object {
        private const val TAG = "CachedAssetInterceptor"
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
        val mimeType = getMimeType(url)
        return WebResourceResponse(
            mimeType,
            "UTF-8",
            ByteArrayInputStream(data)
        )
    }

    private fun getMimeType(url: String): String {
        // Check specific patterns first, then fallback to general ones
        return when {
            // CSS files with ?inline query parameter are transformed by Vite into JavaScript modules
            // that export CSS as strings. See use-editor-styles.js where these are imported and used
            // as JavaScript string variables for programmatic style injection.
            url.contains(".css?inline") -> "application/javascript"
            url.contains(".js") -> "application/javascript"
            url.contains(".css") -> "text/css"
            url.contains(".map") -> "application/json"
            else -> "application/octet-stream"
        }
    }
}
