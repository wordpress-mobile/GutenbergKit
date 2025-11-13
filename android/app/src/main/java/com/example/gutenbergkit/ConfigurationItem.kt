package com.example.gutenbergkit

sealed class ConfigurationItem {
    object BundledEditor : ConfigurationItem()
    data class ConfiguredEditor(
        val name: String,
        val siteUrl: String,
        val siteApiRoot: String,
        val authHeader: String
    ) : ConfigurationItem()
}