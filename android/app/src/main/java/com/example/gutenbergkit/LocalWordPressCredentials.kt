package com.example.gutenbergkit

data class LocalWordPressCredentials(
    val siteUrl: String,
    val siteApiRoot: String,
    val authHeader: String
) {
    companion object {
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
                authHeader = BuildConfig.WP_ENV_AUTH_HEADER
            )
        }

        private fun remapLocalhost(url: String): String =
            url.replace("localhost", "10.0.2.2")
    }
}
