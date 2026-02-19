package com.example.gutenbergkit

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import rs.wordpress.api.kotlin.ApiDiscoveryResult
import rs.wordpress.api.kotlin.WpLoginClient
import java.net.HttpURLConnection
import java.net.URL

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
     * Discovers site capabilities via API discovery.
     *
     * @param siteApiRoot The WordPress REST API root URL (e.g., "https://example.com/wp-json")
     * @return SiteCapabilities indicating which features are supported
     */
    suspend fun discoverCapabilities(
        siteApiRoot: String,
    ): SiteCapabilities = withContext(Dispatchers.IO) {
        try {
            // Extract the site URL from the API root URL
            // e.g., "https://example.com/wp-json" -> "https://example.com"
            val siteUrl = siteApiRoot.removeSuffix("/").substringBeforeLast("/wp-json")

            // Use WpLoginClient to perform API discovery, which includes API details
            when (val apiDiscoveryResult = WpLoginClient().apiDiscovery(siteUrl)) {
                is ApiDiscoveryResult.Success -> {
                    val success = apiDiscoveryResult.success
                    val apiDetails = success.apiDetails

                    // Check if the site has the required routes using hasRoute() method
                    val supportsPlugins = apiDetails.hasRoute(ROUTE_EDITOR_ASSETS)
                    val supportsThemeStyles = apiDetails.hasRoute(ROUTE_EDITOR_SETTINGS)

                    Log.d(TAG, "Discovered capabilities - Plugins: $supportsPlugins, Theme Styles: $supportsThemeStyles")

                    SiteCapabilities(
                        supportsPlugins = supportsPlugins,
                        supportsThemeStyles = supportsThemeStyles
                    )
                }
                else -> {
                    Log.w(TAG, "API discovery via WpLoginClient failed: $apiDiscoveryResult, trying direct HTTP fetch")
                    discoverCapabilitiesViaHttp(siteApiRoot)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "API discovery via WpLoginClient threw, trying direct HTTP fetch", e)
            try {
                discoverCapabilitiesViaHttp(siteApiRoot)
            } catch (httpError: Exception) {
                Log.e(TAG, "Direct HTTP discovery also failed", httpError)
                getDefaultCapabilities()
            }
        }
    }

    /**
     * Discovers capabilities by directly fetching the REST API root and inspecting
     * the `routes` object. This works over plain HTTP, unlike WpLoginClient which
     * may require HTTPS.
     */
    private fun discoverCapabilitiesViaHttp(siteApiRoot: String): SiteCapabilities {
        val url = URL(siteApiRoot.trimEnd('/') + "/")
        val connection = url.openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "GET"
            connection.connectTimeout = 10_000
            connection.readTimeout = 10_000
            connection.setRequestProperty("Accept", "application/json")

            val responseCode = connection.responseCode
            if (responseCode != HttpURLConnection.HTTP_OK) {
                Log.w(TAG, "HTTP discovery got status $responseCode")
                return getDefaultCapabilities()
            }

            val body = connection.inputStream.bufferedReader().use { it.readText() }
            val json = JSONObject(body)
            val routes = json.optJSONObject("routes") ?: return getDefaultCapabilities()

            val supportsPlugins = routes.has(ROUTE_EDITOR_ASSETS)
            val supportsThemeStyles = routes.has(ROUTE_EDITOR_SETTINGS)

            Log.d(TAG, "HTTP discovery - Plugins: $supportsPlugins, Theme Styles: $supportsThemeStyles")

            return SiteCapabilities(
                supportsPlugins = supportsPlugins,
                supportsThemeStyles = supportsThemeStyles
            )
        } finally {
            connection.disconnect()
        }
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
