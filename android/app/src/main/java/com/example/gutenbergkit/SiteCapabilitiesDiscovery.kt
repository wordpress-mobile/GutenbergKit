package com.example.gutenbergkit

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject

/**
 * Data class representing the capabilities discovered from a WordPress site.
 */
data class SiteCapabilities(
    val supportsPlugins: Boolean,
    val supportsThemeStyles: Boolean
)

/**
 * Discovers WordPress site capabilities by querying the API root endpoint.
 * This mirrors the iOS implementation's capability discovery logic.
 */
class SiteCapabilitiesDiscovery {

    companion object {
        private const val TAG = "SiteCapabilitiesDiscovery"

        // Routes to check for capability support
        private const val ROUTE_EDITOR_ASSETS = "/wpcom/v2/editor-assets"
        private const val ROUTE_EDITOR_SETTINGS = "/wp-block-editor/v1/settings"
    }

    /**
     * Discovers site capabilities by fetching the API root metadata.
     *
     * @param siteApiRoot The WordPress REST API root URL
     * @param authHeader The authentication header (e.g., "Basic xyz123")
     * @return SiteCapabilities indicating which features are supported
     */
    suspend fun discoverCapabilities(
        siteApiRoot: String,
        authHeader: String
    ): SiteCapabilities = withContext(Dispatchers.IO) {
        try {
            val client = OkHttpClient()
            val request = Request.Builder()
                .url(siteApiRoot)
                .addHeader("Authorization", authHeader)
                .build()

            val response = client.newCall(request).execute()

            if (!response.isSuccessful) {
                Log.w(TAG, "Failed to fetch API root: ${response.code}")
                return@withContext getDefaultCapabilities()
            }

            val responseBody = response.body?.string()
            if (responseBody == null) {
                Log.w(TAG, "Empty response body from API root")
                return@withContext getDefaultCapabilities()
            }

            val apiRoot = JSONObject(responseBody)
            val routes = apiRoot.optJSONObject("routes")

            if (routes == null) {
                Log.w(TAG, "No routes found in API root response")
                return@withContext getDefaultCapabilities()
            }

            val supportsPlugins = hasRoute(routes, ROUTE_EDITOR_ASSETS)
            val supportsThemeStyles = hasRoute(routes, ROUTE_EDITOR_SETTINGS)

            Log.d(TAG, "Discovered capabilities - Plugins: $supportsPlugins, Theme Styles: $supportsThemeStyles")

            SiteCapabilities(
                supportsPlugins = supportsPlugins,
                supportsThemeStyles = supportsThemeStyles
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error discovering site capabilities", e)
            getDefaultCapabilities()
        }
    }

    /**
     * Checks if a specific route exists in the routes object.
     */
    private fun hasRoute(routes: JSONObject, route: String): Boolean {
        return routes.has(route)
    }

    /**
     * Returns default capabilities when discovery fails.
     * Conservative defaults: no plugins, no theme styles.
     */
    private fun getDefaultCapabilities(): SiteCapabilities {
        return SiteCapabilities(
            supportsPlugins = false,
            supportsThemeStyles = false
        )
    }
}
