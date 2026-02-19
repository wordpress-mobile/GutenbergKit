package com.example.gutenbergkit

import org.json.JSONObject
import java.io.File

data class LocalWordPressCredentials(
    val siteUrl: String,
    val siteApiRoot: String,
    val username: String,
    val appPassword: String,
    val authHeader: String
) {
    companion object {
        /**
         * Loads credentials from the file path specified in `BuildConfig.WP_ENV_CREDENTIALS_PATH`.
         *
         * Remaps `localhost` to `10.0.2.2` so the Android emulator can reach the host machine.
         */
        fun load(): LocalWordPressCredentials? {
            val path = BuildConfig.WP_ENV_CREDENTIALS_PATH
            if (path.isEmpty()) return null

            val file = File(path)
            if (!file.exists()) return null

            return try {
                val json = JSONObject(file.readText())
                LocalWordPressCredentials(
                    siteUrl = remapLocalhost(json.getString("siteUrl")),
                    siteApiRoot = remapLocalhost(json.getString("siteApiRoot")),
                    username = json.getString("username"),
                    appPassword = json.getString("appPassword"),
                    authHeader = json.getString("authHeader")
                )
            } catch (e: Exception) {
                null
            }
        }

        private fun remapLocalhost(url: String): String =
            url.replace("localhost", "10.0.2.2")
    }
}
