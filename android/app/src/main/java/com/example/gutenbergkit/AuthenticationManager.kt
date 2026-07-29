package com.example.gutenbergkit

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.net.toUri
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import rs.wordpress.api.kotlin.ApiDiscoveryResult
import rs.wordpress.api.kotlin.WpComApiClient
import rs.wordpress.api.kotlin.NetworkAvailabilityProvider
import rs.wordpress.api.kotlin.WpLoginClient
import rs.wordpress.api.kotlin.WpRequestResult
import rs.wordpress.api.kotlin.toURL
import uniffi.wp_api.AutoDiscoveryAttemptSuccess
import uniffi.wp_api.DiscoveredAuthenticationMechanism
import uniffi.wp_api.OAuth2Configuration
import uniffi.wp_api.TokenRequestParameters
import uniffi.wp_api.WpAuthenticationProvider
import uniffi.wp_api.WpComOauthScope
import uniffi.wp_api.WpComSiteIdentifier
import uniffi.wp_api.applicationPasswordsUrl
import uniffi.wp_api.wordpressComOauth2Configuration
import uniffi.wp_mobile.Account
import uniffi.wp_mobile.wordpressComSiteApiRoot

class AuthenticationManager(
    private val context: Context,
    private val app: GutenbergKitApplication,
    private val networkAvailabilityProvider: NetworkAvailabilityProvider,
    private val scope: CoroutineScope
) {
    interface AuthenticationCallback {
        fun onAuthenticationSuccess(account: Account)
        fun onAuthenticationFailure(errorMessage: String)
    }

    private var currentDiscoverySuccess: AutoDiscoveryAttemptSuccess? = null
    private var currentOAuthConfig: OAuth2Configuration? = null
    private var currentOAuthState: String? = null
    private var currentCallback: AuthenticationCallback? = null

    companion object {
        private const val APP_NAME = "GutenbergKitAndroidDemoApp"
        private const val APP_ID = "00000000-0000-4000-9000-000000000000"
        private const val SELF_HOSTED_REDIRECT_URI = "gutenbergkit://authorized"
        private const val WPCOM_REDIRECT_URI = "gutenbergkit://wpcom-authorized"
    }

    fun startAuthentication(siteUrl: String, callback: AuthenticationCallback) {
        currentCallback = callback

        scope.launch(Dispatchers.IO) {
            try {
                when (val apiDiscoveryResult = WpLoginClient(
                        interceptors = emptyList(),
                        networkAvailabilityProvider = networkAvailabilityProvider
                    ).apiDiscovery(siteUrl)) {
                    is ApiDiscoveryResult.Success -> {
                        val success = apiDiscoveryResult.success
                        currentDiscoverySuccess = success

                        withContext(Dispatchers.Main) {
                            when (success.authentication) {
                                is DiscoveredAuthenticationMechanism.ApplicationPasswords -> {
                                    launchApplicationPasswordsFlow(success)
                                }
                                is DiscoveredAuthenticationMechanism.OAuth2 -> {
                                    launchOAuthFlow(success)
                                }
                            }
                        }
                    }
                    else -> {
                        withContext(Dispatchers.Main) {
                            callback.onAuthenticationFailure(
                                "Failed to find api root: $apiDiscoveryResult"
                            )
                        }
                    }
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    callback.onAuthenticationFailure("Authentication error: ${e.message}")
                }
            }
        }
    }

    private fun launchApplicationPasswordsFlow(success: AutoDiscoveryAttemptSuccess) {
        val authUrl = applicationPasswordsUrl(success.authentication)
            ?: run {
                currentCallback?.onAuthenticationFailure("No application passwords URL found")
                return
            }

        val uriBuilder = authUrl.url().toUri().buildUpon()
        uriBuilder
            .appendQueryParameter("app_name", APP_NAME)
            .appendQueryParameter("app_id", APP_ID)
            .appendQueryParameter("success_url", SELF_HOSTED_REDIRECT_URI)

        uriBuilder.build().let { uri ->
            context.startActivity(Intent(Intent.ACTION_VIEW, uri))
        }
    }

    private fun launchOAuthFlow(success: AutoDiscoveryAttemptSuccess) {
        val credentials = loadOAuthCredentials()
        if (credentials == null) {
            currentCallback?.onAuthenticationFailure(
                "WP.com OAuth credentials not configured. " +
                    "Add wp_com_oauth_credentials.json to app assets."
            )
            return
        }

        val config = wordpressComOauth2Configuration(
            clientId = credentials.clientId,
            clientSecret = credentials.clientSecret,
            redirectUri = WPCOM_REDIRECT_URI,
            scope = listOf(WpComOauthScope.GLOBAL)
        )
        currentOAuthConfig = config

        val host = success.parsedSiteUrl.toURL().toURI().host
        val state = java.util.UUID.randomUUID().toString()
        currentOAuthState = state

        val authUrl = config.buildTokenRequestUrl(
            state = state,
            blog = WpComSiteIdentifier.Slug(value = host)
        )

        context.startActivity(Intent(Intent.ACTION_VIEW, authUrl.url().toUri()))
    }

    fun processAuthenticationResult(intent: Intent, callback: AuthenticationCallback) {
        currentCallback = callback
        intent.data?.let { uri ->
            when (uri.host) {
                "authorized" -> handleApplicationPasswordsCallback(uri, callback)
                "wpcom-authorized" -> handleOAuthCallback(uri, callback)
            }
        }
    }

    private fun handleApplicationPasswordsCallback(
        data: Uri,
        callback: AuthenticationCallback
    ) {
        scope.launch {
            try {
                val siteUrl = data.getQueryParameter("site_url")
                    ?: throw IllegalStateException("site_url is missing from authentication")
                val username = data.getQueryParameter("user_login")
                    ?: throw IllegalStateException("username is missing from authentication")
                val password = data.getQueryParameter("password")
                    ?: throw IllegalStateException("password is missing from authentication")

                val discoverySuccess = currentDiscoverySuccess
                    ?: throw IllegalStateException("API discovery result is not available")
                val siteApiRoot = discoverySuccess.apiRootUrl.toURL().toString()

                val account = Account.SelfHostedSite(
                    id = 0u,
                    domain = siteUrl,
                    username = username,
                    password = password,
                    siteApiRoot = siteApiRoot
                )
                val stored = app.withAccountRepository { repo ->
                    repo.store(account)
                    repo.all().last()
                }
                currentDiscoverySuccess = null
                withContext(Dispatchers.Main) {
                    callback.onAuthenticationSuccess(stored)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    callback.onAuthenticationFailure("Authentication error: ${e.message}")
                }
            }
        }
    }

    private fun handleOAuthCallback(data: Uri, callback: AuthenticationCallback) {
        val config = currentOAuthConfig
        val state = currentOAuthState

        if (config == null || state == null) {
            callback.onAuthenticationFailure("OAuth state not available")
            return
        }

        scope.launch(Dispatchers.IO) {
            try {
                val result = config.parseTokenResponse(
                    url = data.toString(),
                    expectedState = state
                )
                val tokenParams = config.buildTokenRequestParameters(code = result.code)

                val wpComClient = WpComApiClient(
                    authProvider = WpAuthenticationProvider.none(),
                    interceptors = emptyList(),
                    networkAvailabilityProvider = networkAvailabilityProvider
                )

                val tokenResult = wpComClient.request { client ->
                    client.oauth2().requestToken(tokenParams)
                }

                when (tokenResult) {
                    is WpRequestResult.Success -> {
                        val token = tokenResult.response.data
                        val blogId = token.blogId ?: throw OAuthException.MissingBlogId()
                        val stored = persistOAuthAccount(blogId, token.accessToken)
                        withContext(Dispatchers.Main) {
                            callback.onAuthenticationSuccess(stored)
                        }
                    }
                    else -> {
                        withContext(Dispatchers.Main) {
                            callback.onAuthenticationFailure("Token exchange failed")
                        }
                    }
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    callback.onAuthenticationFailure("OAuth error: ${e.message}")
                }
            }
        }
    }

    /**
     * Persists an [Account.WpCom] derived from the given OAuth blogId and
     * access token via [GutenbergKitApplication.withAccountRepository] (off
     * the main thread) and clears OAuth scratch state. Returns the stored
     * [Account].
     */
    private suspend fun persistOAuthAccount(blogId: ULong, accessToken: String): Account {
        val siteHost = currentDiscoverySuccess?.parsedSiteUrl?.toURL()?.toURI()?.host
            ?: throw OAuthException.MissingSiteHost()

        val account = Account.WpCom(
            id = 0u,
            username = siteHost,
            token = accessToken,
            siteApiRoot = wordpressComSiteApiRoot(blogId)
        )

        val stored = app.withAccountRepository { repo ->
            repo.store(account)
            repo.all().last()
        }

        currentOAuthConfig = null
        currentOAuthState = null
        currentDiscoverySuccess = null

        return stored
    }

    private fun loadOAuthCredentials(): OAuthCredentials? {
        return try {
            val json = context.assets.open("wp_com_oauth_credentials.json")
                .bufferedReader()
                .use { it.readText() }
            val jsonObject = JSONObject(json)
            val clientId = jsonObject.optLong("client_id", 0)
            val clientSecret = jsonObject.optString("client_secret", "")
            if (clientId == 0L || clientSecret.isEmpty()) null
            else OAuthCredentials(clientId.toULong(), clientSecret)
        } catch (e: Exception) {
            null
        }
    }

    private data class OAuthCredentials(val clientId: ULong, val clientSecret: String)

    sealed class OAuthException(message: String) : Exception(message) {
        class MissingBlogId : OAuthException(
            "WordPress.com did not return a blog ID. The site may not be associated with the authenticated account."
        )
        class MissingSiteHost : OAuthException(
            "Could not determine the site host from API discovery."
        )
    }
}
