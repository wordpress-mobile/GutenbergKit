package com.example.gutenbergkit

import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.floatingactionbutton.FloatingActionButton
import org.wordpress.gutenberg.EditorConfiguration

class MainActivity : AppCompatActivity() {

    private lateinit var recyclerView: RecyclerView
    private lateinit var adapter: ConfigurationAdapter
    private val configurations = mutableListOf<ConfigurationItem>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_configuration)

        title = getString(R.string.demo_title)

        recyclerView = findViewById(R.id.configurationsRecyclerView)
        recyclerView.layoutManager = LinearLayoutManager(this)

        // Add default bundled editor configuration
        configurations.add(ConfigurationItem.BundledEditor)

        // Add a sample remote configuration (similar to iOS template)
        configurations.add(
            ConfigurationItem.RemoteEditor(
                name = getString(R.string.sample_site),
                siteUrl = "",
                authHeader = ""
            )
        )

        adapter = ConfigurationAdapter(configurations) { config ->
            when (config) {
                is ConfigurationItem.BundledEditor -> launchEditor(createBundledConfiguration())
                is ConfigurationItem.RemoteEditor -> {
                    if (config.siteUrl.isEmpty()) {
                        // Show dialog to configure the site
                        showEditConfigurationDialog(config)
                    } else {
                        launchEditor(createRemoteConfiguration(config))
                    }
                }
            }
        }
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
            .setSiteApiRoot("${config.siteUrl}/wp-json/")
            .setSiteApiNamespace(arrayOf("wp/v2"))
            .setAuthHeader(config.authHeader)
            .build()

    private fun createCommonConfigurationBuilder(): EditorConfiguration.Builder =
        EditorConfiguration.builder()
            .setTitle("")
            .setContent("")
            .setPostType("post")
            .setThemeStyles(false)
            .setHideTitle(false)

    private fun launchEditor(configuration: EditorConfiguration) {
        val intent = Intent(this, EditorActivity::class.java)
        intent.putExtra("configuration", configuration)
        startActivity(intent)
    }

    private fun showEditConfigurationDialog(config: ConfigurationItem.RemoteEditor) {
        val dialogView = layoutInflater.inflate(R.layout.dialog_configuration, null)
        val siteUrlInput = dialogView.findViewById<EditText>(R.id.siteUrlInput)
        val authHeaderInput = dialogView.findViewById<EditText>(R.id.authHeaderInput)

        siteUrlInput.setText(config.siteUrl)
        authHeaderInput.setText(config.authHeader)

        AlertDialog.Builder(this)
            .setTitle(getString(R.string.edit_configuration))
            .setView(dialogView)
            .setPositiveButton(getString(R.string.save)) { _, _ ->
                val newConfig = ConfigurationItem.RemoteEditor(
                    name = config.name,
                    siteUrl = siteUrlInput.text.toString(),
                    authHeader = authHeaderInput.text.toString()
                )
                val index = configurations.indexOf(config)
                configurations[index] = newConfig
                adapter.notifyItemChanged(index)
            }
            .setNegativeButton(getString(R.string.cancel), null)
            .show()
    }

    private fun showAddConfigurationDialog() {
        val dialogView = layoutInflater.inflate(R.layout.dialog_configuration, null)
        val siteUrlInput = dialogView.findViewById<EditText>(R.id.siteUrlInput)
        val authHeaderInput = dialogView.findViewById<EditText>(R.id.authHeaderInput)

        AlertDialog.Builder(this)
            .setTitle(getString(R.string.add_remote_configuration))
            .setView(dialogView)
            .setPositiveButton(getString(R.string.add)) { _, _ ->
                val siteUrl = siteUrlInput.text.toString()
                if (siteUrl.isNotEmpty()) {
                    val newConfig = ConfigurationItem.RemoteEditor(
                        name = siteUrl.removePrefix("https://").removePrefix("http://")
                            .substringBefore("/"),
                        siteUrl = siteUrl,
                        authHeader = authHeaderInput.text.toString()
                    )
                    configurations.add(newConfig)
                    adapter.notifyItemInserted(configurations.size - 1)
                }
            }
            .setNegativeButton(getString(R.string.cancel), null)
            .show()
    }
}

sealed class ConfigurationItem {
    object BundledEditor : ConfigurationItem()
    data class RemoteEditor(
        val name: String,
        val siteUrl: String,
        val authHeader: String
    ) : ConfigurationItem()
}

class ConfigurationAdapter(
    private val items: List<ConfigurationItem>,
    private val onItemClick: (ConfigurationItem) -> Unit
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
                holder.subtitleText.visibility = View.GONE
            }

            is ConfigurationItem.RemoteEditor -> {
                holder.titleText.text = item.name
                holder.subtitleText.text = if (item.siteUrl.isEmpty()) {
                    holder.itemView.context.getString(R.string.tap_to_configure)
                } else {
                    item.siteUrl
                }
                holder.subtitleText.visibility = View.VISIBLE
            }
        }

        holder.itemView.setOnClickListener {
            onItemClick(item)
        }
    }

    override fun getItemCount() = items.size

    class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val titleText: TextView = view.findViewById(R.id.titleText)
        val subtitleText: TextView = view.findViewById(R.id.subtitleText)
    }
}