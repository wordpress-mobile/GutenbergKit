package com.example.gutenbergkit

import uniffi.wp_mobile.Account

data class LocalWordPressCredentials(
    val siteUrl: String,
    val siteApiRoot: String,
    val username: String,
    val appPassword: String
) {
    /**
     * An in-memory account for the local site, as the iOS demo builds, so the
     * posts list and Save button can reach it without a stored account.
     */
    fun toAccount(): Account = Account.SelfHostedSite(
        id = ACCOUNT_ID,
        domain = siteUrl,
        username = username,
        password = appPassword,
        siteApiRoot = siteApiRoot
    )

    companion object {
        /** Never assigned to a stored account, whose IDs start at 1. */
        const val ACCOUNT_ID: ULong = 0u

        /**
         * Loads credentials from BuildConfig fields populated at build time from
         * `.wp-env.credentials.json`. Remaps `localhost` to `10.0.2.2` so the
         * Android emulator can reach the host machine.
         */
        fun load(): LocalWordPressCredentials? {
            val siteUrl = BuildConfig.WP_ENV_SITE_URL
            if (siteUrl.isEmpty()) return null

            return LocalWordPressCredentials(
                siteUrl = remapLocalhost(siteUrl),
                siteApiRoot = remapLocalhost(BuildConfig.WP_ENV_SITE_API_ROOT),
                username = BuildConfig.WP_ENV_USERNAME,
                appPassword = BuildConfig.WP_ENV_APP_PASSWORD
            )
        }

        private fun remapLocalhost(url: String): String =
            url.replace("://localhost", "://10.0.2.2")
    }
}
