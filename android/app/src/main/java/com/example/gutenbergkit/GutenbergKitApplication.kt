package com.example.gutenbergkit

import android.app.Application
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import rs.wordpress.api.android.KeystorePasswordTransformer
import rs.wordpress.api.kotlin.NetworkAvailabilityProvider
import rs.wordpress.api.kotlin.WpApiClient
import rs.wordpress.api.kotlin.WpRequestExecutor
import uniffi.wp_api.ParsedUrl
import uniffi.wp_api.WpAuthentication
import uniffi.wp_api.WpAuthenticationProvider
import uniffi.wp_api.WpComBaseUrl
import uniffi.wp_api.WpComDotOrgApiUrlResolver
import uniffi.wp_api.WpOrgSiteApiUrlResolver
import uniffi.wp_api.wpAuthenticationFromUsernameAndPassword
import uniffi.wp_mobile.Account
import uniffi.wp_mobile.AccountRepository

class GutenbergKitApplication : Application() {
    lateinit var accountRepository: AccountRepository
        private set

    lateinit var networkAvailabilityProvider: NetworkAvailabilityProvider
        private set

    override fun onCreate() {
        super.onCreate()
        accountRepository = AccountRepository(
            rootPath = filesDir.resolve("accounts").absolutePath,
            passwordTransformer = KeystorePasswordTransformer("GutenbergKit")
        )
        networkAvailabilityProvider = NetworkAvailabilityProvider {
            val cm = getSystemService(ConnectivityManager::class.java)
            val capabilities = cm.getNetworkCapabilities(cm.activeNetwork)
            capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
        }
    }

    /**
     * Constructs a [WpApiClient] for the given [account]. Used by the demo app's posts
     * list and Save button to fetch/persist posts via the WordPress REST API.
     *
     * For WP.com accounts, uses [WpComDotOrgApiUrlResolver] so requests are routed
     * through `/wp/v2/sites/{blogId}/...` instead of the self-hosted layout. Otherwise,
     * the resolver double-prefixes paths and the WP.com REST API returns
     * `rest_no_route`.
     */
    fun createApiClient(account: Account): WpApiClient {
        val auth = when (account) {
            is Account.SelfHostedSite -> wpAuthenticationFromUsernameAndPassword(
                account.username,
                account.password
            )
            is Account.WpCom -> WpAuthentication.Bearer(token = account.token)
        }
        val authProvider = WpAuthenticationProvider.staticWithAuth(auth)
        val requestExecutor = WpRequestExecutor(
            interceptors = emptyList(),
            networkAvailabilityProvider = networkAvailabilityProvider
        )

        val apiUrlResolver = when (account) {
            is Account.WpCom -> {
                val siteId = extractWpComSiteId(account.siteApiRoot)
                    ?: error("Could not extract WP.com site id from ${account.siteApiRoot}")
                WpComDotOrgApiUrlResolver(siteId = siteId, baseUrl = WpComBaseUrl.Production)
            }
            is Account.SelfHostedSite -> WpOrgSiteApiUrlResolver(
                apiRootUrl = ParsedUrl.parse(account.siteApiRoot)
            )
        }

        return WpApiClient(
            apiUrlResolver = apiUrlResolver,
            authProvider = authProvider,
            requestExecutor = requestExecutor
        )
    }

    /**
     * Extracts the WP.com blog id from a namespace-specific API root URL such as
     * `https://public-api.wordpress.com/wp/v2/sites/229672404`. Returns null if the
     * URL is not a WP.com API root.
     */
    private fun extractWpComSiteId(siteApiRoot: String): String? {
        val regex = Regex("""public-api\.wordpress\.com/.+/sites/(\d+)""")
        return regex.find(siteApiRoot)?.groupValues?.get(1)
    }
}
