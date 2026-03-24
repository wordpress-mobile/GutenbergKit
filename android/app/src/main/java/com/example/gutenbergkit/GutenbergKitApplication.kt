package com.example.gutenbergkit

import android.app.Application
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import rs.wordpress.api.android.KeystorePasswordTransformer
import rs.wordpress.api.kotlin.NetworkAvailabilityProvider
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
}
