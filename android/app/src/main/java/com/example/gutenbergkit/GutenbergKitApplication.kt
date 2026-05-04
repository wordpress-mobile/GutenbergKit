package com.example.gutenbergkit

import android.app.Application
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.StrictMode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.withContext
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
    /**
     * The [AccountRepository] is initialized off the main thread because its
     * constructor touches `filesDir` (a `getDataDir()` disk access) and loads
     * JNA's native dispatch library, which itself does several disk reads
     * during `<clinit>`. Both would trip [StrictMode] with `penaltyDeath`.
     *
     * Access via [accountRepository] from a coroutine.
     */
    private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val accountRepositoryAsync: Deferred<AccountRepository> =
        applicationScope.async(start = CoroutineStart.LAZY) {
            AccountRepository(
                rootPath = filesDir.resolve("accounts").absolutePath,
                passwordTransformer = KeystorePasswordTransformer("GutenbergKit")
            )
        }

    /**
     * The [NetworkAvailabilityProvider] constructor only stores a SAM lambda,
     * so it is safe to initialize eagerly on the main thread.
     */
    lateinit var networkAvailabilityProvider: NetworkAvailabilityProvider
        private set

    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.DEBUG) {
            enableStrictMode()
        }
        networkAvailabilityProvider = NetworkAvailabilityProvider {
            val cm = getSystemService(ConnectivityManager::class.java)
            val capabilities = cm.getNetworkCapabilities(cm.activeNetwork)
            capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
        }
        // Kick off background init so the first caller doesn't pay the cost.
        accountRepositoryAsync.start()
    }

    /**
     * Suspends until the [AccountRepository] is ready. Subsequent calls are
     * cheap. Callers that then read or write the repository must still hop to
     * [Dispatchers.IO] for the actual call.
     */
    suspend fun accountRepository(): AccountRepository = accountRepositoryAsync.await()

    /**
     * Awaits the repository, then runs [block] on [Dispatchers.IO]. This is
     * the standard pattern for repository access from the demo UI.
     */
    suspend fun <T> withAccountRepository(block: suspend (AccountRepository) -> T): T {
        val repo = accountRepository()
        return withContext(Dispatchers.IO) { block(repo) }
    }

    private fun enableStrictMode() {
        // ThreadPolicy uses penaltyDeath so any new main-thread disk/network
        // I/O introduced in the library crashes the demo immediately. VmPolicy
        // stays on penaltyLog — VM violations like LeakedClosableObject fire
        // during GC and would crash at unpredictable times unrelated to the
        // offending code path.
        StrictMode.setThreadPolicy(
            StrictMode.ThreadPolicy.Builder()
                .detectAll()
                .penaltyLog()
                .penaltyDeath()
                .build()
        )
        StrictMode.setVmPolicy(
            StrictMode.VmPolicy.Builder()
                .detectAll()
                .penaltyLog()
                .build()
        )
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
