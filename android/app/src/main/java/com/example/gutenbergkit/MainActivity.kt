package com.example.gutenbergkit

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.floatingactionbutton.FloatingActionButton
import org.wordpress.gutenberg.EditorConfiguration
import org.json.JSONArray
import org.json.JSONObject
import androidx.core.content.edit

class MainActivity : AppCompatActivity() {

    private lateinit var recyclerView: RecyclerView
    private lateinit var adapter: ConfigurationAdapter
    private val configurations = mutableListOf<ConfigurationItem>()
    private lateinit var sharedPrefs: SharedPreferences

    companion object {
        private const val PREFS_NAME = "gutenberg_configs"
        private const val KEY_REMOTE_CONFIGS = "remote_configurations"
        const val EXTRA_CONFIGURATION = "configuration"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_configuration)

        title = getString(R.string.demo_title)
        sharedPrefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        recyclerView = findViewById(R.id.configurationsRecyclerView)
        recyclerView.layoutManager = LinearLayoutManager(this)

        // Add default bundled editor configuration
        configurations.add(ConfigurationItem.BundledEditor)

        // Load saved configurations
        loadSavedConfigurations()

        adapter = ConfigurationAdapter(
            configurations,
            onItemClick = { config ->
                when (config) {
                    is ConfigurationItem.BundledEditor -> launchEditor(createBundledConfiguration())
                    is ConfigurationItem.RemoteEditor -> {
                        launchEditor(createRemoteConfiguration(config))
                    }
                }
            },
            onItemLongClick = { config ->
                when (config) {
                    is ConfigurationItem.BundledEditor -> false // Can't delete bundled editor
                    is ConfigurationItem.RemoteEditor -> {
                        showDeleteDialog(config)
                        true
                    }
                }
            }
        )
        recyclerView.adapter = adapter

        // Add FAB for adding new remote configurations
        findViewById<FloatingActionButton>(R.id.addConfigurationFab).setOnClickListener {
            showAddConfigurationDialog()
        }
    }

    private fun createBundledConfiguration(): EditorConfiguration =
        createCommonConfigurationBuilder()
            .setPlugins(false)
            .setSiteURL("")
            .setSiteApiRoot("")
            .setSiteApiNamespace(arrayOf())
            .setNamespaceExcludedPaths(arrayOf())
            .setAuthHeader("")
            .setWebViewGlobals(emptyList())
            .setCookies(emptyMap())
            .build()

    private fun createRemoteConfiguration(config: ConfigurationItem.RemoteEditor): EditorConfiguration =
        createCommonConfigurationBuilder()
            .setPlugins(true) // Enable plugins for remote editor
            .setSiteURL(config.siteUrl)
            .setSiteApiRoot(config.siteApiRoot)
            .setSiteApiNamespace(arrayOf("wp/v2"))
            .setNamespaceExcludedPaths(arrayOf())
            .setAuthHeader(config.authHeader)
            .build()

    private fun createCommonConfigurationBuilder(): EditorConfiguration.Builder =
        EditorConfiguration.builder()
            .setTitle("")
            .setContent("")
            .setPostType("post")
            .setThemeStyles(false)
            .setHideTitle(false)
            .setWebViewGlobals(emptyList())
            .setCookies(emptyMap())

    private fun launchEditor(configuration: EditorConfiguration) {
        val intent = Intent(this, EditorActivity::class.java)
        intent.putExtra(EXTRA_CONFIGURATION, configuration)
        startActivity(intent)
    }


    private fun showAddConfigurationDialog() {
        val dialogView = layoutInflater.inflate(R.layout.dialog_configuration, null)
        val siteUrlInput = dialogView.findViewById<EditText>(R.id.siteUrlInput)

        AlertDialog.Builder(this)
            .setTitle(getString(R.string.add_remote_configuration))
            .setView(dialogView)
            .setPositiveButton(getString(R.string.add)) { _, _ ->
                val siteUrl = siteUrlInput.text.toString().trim()
                if (siteUrl.isNotEmpty()) {
                    authenticateWithSite(siteUrl)
                }
            }
            .setNegativeButton(getString(R.string.cancel), null)
            .show()
    }
    
    private fun authenticateWithSite(siteUrl: String) {
        // TODO: Implement authentication logic
    }
    
    fun onAuthenticationSuccess(siteUrl: String, siteApiRoot: String, authToken: String) {
        val siteName = siteUrl.removePrefix("https://").removePrefix("http://").substringBefore("/")
        val newConfig = ConfigurationItem.RemoteEditor(
            name = siteName,
            siteUrl = siteUrl,
            siteApiRoot = siteApiRoot,
            authHeader = authToken
        )
        configurations.add(newConfig)
        adapter.notifyItemInserted(configurations.size - 1)
        saveConfigurations()
    }
    
    fun onAuthenticationFailure(errorMessage: String) {
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.authentication_failed))
            .setMessage(errorMessage)
            .setPositiveButton(getString(R.string.ok), null)
            .setCancelable(true)
            .show()
    }

    private fun showDeleteDialog(config: ConfigurationItem.RemoteEditor) {
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.delete_site_title))
            .setMessage(getString(R.string.delete_site_message))
            .setPositiveButton(getString(R.string.delete)) { _, _ ->
                val index = configurations.indexOf(config)
                configurations.removeAt(index)
                adapter.notifyItemRemoved(index)
                saveConfigurations()
            }
            .setNegativeButton(getString(R.string.cancel), null)
            .show()
    }

    private fun saveConfigurations() {
        val jsonArray = JSONArray()
        configurations.forEach { config ->
            if (config is ConfigurationItem.RemoteEditor) {
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
            putString(KEY_REMOTE_CONFIGS, jsonArray.toString())
        }
    }

    private fun loadSavedConfigurations() {
        val savedData = sharedPrefs.getString(KEY_REMOTE_CONFIGS, null) ?: return
        try {
            val jsonArray = JSONArray(savedData)
            for (i in 0 until jsonArray.length()) {
                val jsonObject = jsonArray.getJSONObject(i)
                val config = ConfigurationItem.RemoteEditor(
                    name = jsonObject.getString("name"),
                    siteUrl = jsonObject.getString("siteUrl"),
                    siteApiRoot = jsonObject.optString("siteApiRoot", jsonObject.getString("siteUrl") + "/wp-json/"),
                    authHeader = jsonObject.getString("authHeader")
                )
                configurations.add(config)
            }
        } catch (e: Exception) {
            // Ignore parsing errors
        }
    }
}

sealed class ConfigurationItem {
    object BundledEditor : ConfigurationItem()
    data class RemoteEditor(
        val name: String,
        val siteUrl: String,
        val siteApiRoot: String,
        val authHeader: String
    ) : ConfigurationItem()
}

class ConfigurationAdapter(
    private val items: List<ConfigurationItem>,
    private val onItemClick: (ConfigurationItem) -> Unit,
    private val onItemLongClick: (ConfigurationItem) -> Boolean
) : RecyclerView.Adapter<ConfigurationAdapter.ViewHolder>() {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_configuration, parent, false)
        return ViewHolder(view)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val item = items[position]
        when (item) {
            is ConfigurationItem.BundledEditor -> {
                holder.titleText.text = holder.itemView.context.getString(R.string.bundled_editor)
                holder.subtitleText.text =
                    holder.itemView.context.getString(R.string.bundled_editor_subtitle)
                holder.subtitleText.visibility = View.VISIBLE
            }

            is ConfigurationItem.RemoteEditor -> {
                holder.titleText.text = item.name
                holder.subtitleText.text = item.siteUrl
                holder.subtitleText.visibility = View.VISIBLE
            }
        }

        holder.itemView.setOnClickListener {
            onItemClick(item)
        }

        holder.itemView.setOnLongClickListener {
            onItemLongClick(item)
        }
    }

    override fun getItemCount() = items.size

    class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val titleText: TextView = view.findViewById(R.id.titleText)
        val subtitleText: TextView = view.findViewById(R.id.subtitleText)
    }
}