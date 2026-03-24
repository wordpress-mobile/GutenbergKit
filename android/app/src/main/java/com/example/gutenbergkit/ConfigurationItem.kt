package com.example.gutenbergkit

import android.util.Base64
import uniffi.wp_mobile.Account

sealed class ConfigurationItem {
    object BundledEditor : ConfigurationItem()
    object LocalWordPress : ConfigurationItem()
    data class ConfiguredEditor(
        val accountId: ULong,
        val name: String,
        val siteUrl: String,
        val siteApiRoot: String,
        val authHeader: String
    ) : ConfigurationItem() {
        companion object {
            fun fromAccount(account: Account): ConfiguredEditor = when (account) {
                is Account.SelfHostedSite -> ConfiguredEditor(
                    accountId = account.id,
                    name = account.domain
                        .removePrefix("https://")
                        .removePrefix("http://")
                        .trimEnd('/'),
                    siteUrl = account.domain,
                    siteApiRoot = account.siteApiRoot,
                    authHeader = "Basic " + Base64.encodeToString(
                        "${account.username}:${account.password}".toByteArray(),
                        Base64.NO_WRAP
                    )
                )
                is Account.WpCom -> ConfiguredEditor(
                    accountId = account.id,
                    name = account.username,
                    siteUrl = account.username,
                    siteApiRoot = account.siteApiRoot,
                    authHeader = "Bearer ${account.token}"
                )
            }
        }
    }
}
