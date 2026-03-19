package com.example.gutenbergkit

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import rs.wordpress.api.kotlin.ApiDiscoveryResult
import rs.wordpress.api.kotlin.WpLoginClient

/**
 * Data class representing the capabilities discovered from a WordPress site.
 */
data class SiteCapabilities(
    val supportsPlugins: Boolean,
    val supportsThemeStyles: Boolean
)

/**
 * Discovers WordPress site capabilities by querying the site via autodiscovery.
 */
class SiteCapabilitiesDiscovery {

    companion object {
        private const val TAG = "SiteCapabilitiesDiscovery"

        // Routes to check for capability support
        private const val ROUTE_EDITOR_ASSETS = "/wpcom/v2/editor-assets"
        private const val ROUTE_EDITOR_SETTINGS = "/wp-block-editor/v1/settings"
    }

    /**
     * Discovers site capabilities via API autodiscovery.
     *
     * @param siteUrl The WordPress site URL (e.g., "example.com" or "example.wordpress.com")
     * @return SiteCapabilities indicating which features are supported
     */
    suspend fun discoverCapabilities(
        siteUrl: String,
    ): SiteCapabilities = withContext(Dispatchers.IO) {
        try {
            when (val apiDiscoveryResult = WpLoginClient(emptyList()).apiDiscovery(siteUrl)) {
                is ApiDiscoveryResult.Success -> {
                    val apiDetails = apiDiscoveryResult.success.apiDetails
                    val siteSlug = siteUrl
                        .removePrefix("https://").removePrefix("http://")
                        .trimEnd('/')

                    // Check both the standard route and the WP.com rewritten
                    // form that includes /sites/{slug}/ after the namespace prefix.
                    val supportsPlugins = apiDetails.hasRoute(ROUTE_EDITOR_ASSETS)
                        || apiDetails.hasRoute(wpComRoute(ROUTE_EDITOR_ASSETS, siteSlug))
                    val supportsThemeStyles = apiDetails.hasRoute(ROUTE_EDITOR_SETTINGS)
                        || apiDetails.hasRoute(wpComRoute(ROUTE_EDITOR_SETTINGS, siteSlug))

                    Log.d(TAG, "Discovered capabilities - Plugins: $supportsPlugins, Theme Styles: $supportsThemeStyles")

                    SiteCapabilities(
                        supportsPlugins = supportsPlugins,
                        supportsThemeStyles = supportsThemeStyles
                    )
                }
                else -> {
                    Log.w(TAG, "API discovery failed: $apiDiscoveryResult")
                    getDefaultCapabilities()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "API discovery threw", e)
            getDefaultCapabilities()
        }
    }

    /**
     * Rewrites a route for WP.com by inserting /sites/{slug}/ after the
     * namespace/version prefix.
     *
     * e.g., "/wpcom/v2/editor-assets" with slug "example.wordpress.com"
     *     -> "/wpcom/v2/sites/example.wordpress.com/editor-assets"
     */
    private fun wpComRoute(route: String, siteSlug: String): String {
        val parts = route.removePrefix("/").split("/", limit = 3)
        if (parts.size < 3) return route
        return "/${parts[0]}/${parts[1]}/sites/$siteSlug/${parts[2]}"
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
