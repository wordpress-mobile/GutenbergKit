package com.example.gutenbergkit

import android.app.Application
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import java.net.URI
import rs.wordpress.api.android.KeystorePasswordTransformer
import rs.wordpress.api.kotlin.NetworkAvailabilityProvider
import rs.wordpress.api.kotlin.WpApiClient
import uniffi.wp_api.WpAuthentication
import uniffi.wp_api.WpAuthenticationProvider
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
     */
    fun createApiClient(account: Account): WpApiClient {
        val auth = when (account) {
            is Account.SelfHostedSite -> wpAuthenticationFromUsernameAndPassword(
                account.username,
                account.password
            )
            is Account.WpCom -> WpAuthentication.Bearer(token = account.token)
        }
        val apiRootUrl = when (account) {
            is Account.SelfHostedSite -> account.siteApiRoot
            is Account.WpCom -> account.siteApiRoot
        }
        return WpApiClient(
            wpOrgSiteApiRootUrl = URI(apiRootUrl).toURL(),
            authProvider = WpAuthenticationProvider.staticWithAuth(auth),
            interceptors = emptyList(),
            networkAvailabilityProvider = networkAvailabilityProvider
        )
    }
}
