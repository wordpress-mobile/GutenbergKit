package com.example.gutenbergkit

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import org.json.JSONArray
import org.json.JSONObject

class ConfigurationStorage(context: Context) {
    private val sharedPrefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    companion object {
        private const val PREFS_NAME = "gutenberg_configs"
        private const val KEY_EDITOR_CONFIGS = "remote_configurations"
    }

    fun saveConfigurations(configurations: List<ConfigurationItem>) {
        val jsonArray = JSONArray()
        configurations.forEach { config ->
            if (config is ConfigurationItem.ConfiguredEditor) {
                val jsonObject = JSONObject().apply {
                    put("name", config.name)
                    put("siteUrl", config.siteUrl)
                    put("siteApiRoot", config.siteApiRoot)
                    put("authHeader", config.authHeader)
                }
                jsonArray.put(jsonObject)
            }
        }
        sharedPrefs.edit {
            putString(KEY_EDITOR_CONFIGS, jsonArray.toString())
        }
    }

    fun loadConfigurations(): List<ConfigurationItem.ConfiguredEditor> {
        val savedData = sharedPrefs.getString(KEY_EDITOR_CONFIGS, null) ?: return emptyList()
        val configurations = mutableListOf<ConfigurationItem.ConfiguredEditor>()

        try {
            val jsonArray = JSONArray(savedData)
            for (i in 0 until jsonArray.length()) {
                val jsonObject = jsonArray.getJSONObject(i)
                val config = ConfigurationItem.ConfiguredEditor(
                    name = jsonObject.getString("name"),
                    siteUrl = jsonObject.getString("siteUrl"),
                    siteApiRoot = jsonObject.optString(
                        "siteApiRoot",
                        jsonObject.getString("siteUrl") + "/wp-json/"
                    ),
                    authHeader = jsonObject.getString("authHeader")
                )
                configurations.add(config)
            }
        } catch (e: Exception) {
            // Ignore parsing errors
        }

        return configurations
    }
}