package com.example.gutenbergkit

import android.content.Context
import android.content.Intent
import android.util.Base64
import androidx.core.net.toUri
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import rs.wordpress.api.kotlin.ApiDiscoveryResult
import rs.wordpress.api.kotlin.WpLoginClient

class AuthenticationManager(private val context: Context) {
    interface AuthenticationCallback {
        fun onAuthenticationSuccess(siteUrl: String, siteApiRoot: String, authToken: String)
        fun onAuthenticationFailure(errorMessage: String)
    }

    private var currentApiRootUrl: String? = null

    companion object {
        private const val APP_NAME_AUTH = "GutenbergKitAndroidDemoApp"
    }

    fun startAuthentication(siteUrl: String, callback: AuthenticationCallback) {
        CoroutineScope(Dispatchers.IO).launch {
            when (val apiDiscoveryResult = WpLoginClient().apiDiscovery(siteUrl)) {
                is ApiDiscoveryResult.Success -> {
                    val success = apiDiscoveryResult.success
                    val apiRootUrl = success.apiRootUrl.url()
                    val applicationPasswordAuthenticationUrl =
                        success.applicationPasswordsAuthenticationUrl.url()
                    withContext(Dispatchers.Main) {
                        launchAuthenticationFlow(
                            apiRootUrl,
                            applicationPasswordAuthenticationUrl
                        )
                    }
                }

                else -> {
                    withContext(Dispatchers.Main) {
                        callback.onAuthenticationFailure("Failed to find api root: $apiDiscoveryResult")
                    }
                }
            }
        }
    }

    private fun launchAuthenticationFlow(
        apiRootUrl: String,
        applicationPasswordAuthenticationUrl: String
    ) {
        // Store the API root URL for use when processing authentication result
        currentApiRootUrl = apiRootUrl

        val uriBuilder = applicationPasswordAuthenticationUrl.toUri().buildUpon()

        uriBuilder
            .appendQueryParameter("app_name", APP_NAME_AUTH)
            .appendQueryParameter("app_id", "00000000-0000-4000-9000-000000000000")
            // Url scheme is defined in AndroidManifest file
            .appendQueryParameter("success_url", "gutenbergkit://authorized")

        uriBuilder.build().let { uri ->
            val intent = Intent(Intent.ACTION_VIEW, uri)
            context.startActivity(intent)
        }
    }

    fun processAuthenticationResult(intent: Intent, callback: AuthenticationCallback) {
        intent.data?.let { data ->
            try {
                val siteUrl = data.getQueryParameter("site_url")
                    ?: throw IllegalStateException("site_url is missing from authentication")
                val username = data.getQueryParameter("user_login")
                    ?: throw IllegalStateException("username is missing from authentication")
                val password = data.getQueryParameter("password")
                    ?: throw IllegalStateException("password is missing from authentication")

                val siteApiRoot = currentApiRootUrl
                    ?: throw IllegalStateException("API root URL is not available")
                currentApiRootUrl = null

                val authToken = "Basic " + Base64.encodeToString(
                    "$username:$password".toByteArray(),
                    Base64.NO_WRAP
                )

                callback.onAuthenticationSuccess(siteUrl, siteApiRoot, authToken)
            } catch (e: Exception) {
                callback.onAuthenticationFailure("Authentication error: ${e.message}")
            }
        }
    }
}
