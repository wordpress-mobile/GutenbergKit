package com.example.gutenbergkit

import android.content.Intent
import android.os.Bundle
import android.widget.EditText
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.floatingactionbutton.FloatingActionButton
import org.wordpress.gutenberg.EditorConfiguration

class MainActivity : AppCompatActivity(), AuthenticationManager.AuthenticationCallback {
    private lateinit var recyclerView: RecyclerView
    private lateinit var adapter: ConfigurationAdapter
    private val configurations = mutableListOf<ConfigurationItem>()
    private lateinit var configurationStorage: ConfigurationStorage
    private lateinit var authenticationManager: AuthenticationManager

    companion object {
        const val EXTRA_CONFIGURATION = "configuration"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_configuration)

        title = getString(R.string.demo_title)
        configurationStorage = ConfigurationStorage(this)
        authenticationManager = AuthenticationManager(this)

        recyclerView = findViewById(R.id.configurationsRecyclerView)
        recyclerView.layoutManager = LinearLayoutManager(this)

        // Add default bundled editor configuration
        configurations.add(ConfigurationItem.BundledEditor)

        // Load saved configurations
        configurations.addAll(configurationStorage.loadConfigurations())

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
            .setCookies(emptyMap())
            .build()

    private fun createRemoteConfiguration(config: ConfigurationItem.RemoteEditor): EditorConfiguration =
        createCommonConfigurationBuilder()
            .setPlugins(true) // Enable plugins for remote editor
            .setSiteURL(config.siteUrl)
            .setSiteApiRoot(config.siteApiRoot)
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
            .setPositiveButton(getString(R.string.add)) { dialog, _ ->
                val siteUrl = siteUrlInput.text.toString().trim()
                if (siteUrl.isNotEmpty()) {
                    dialog.dismiss()
                    authenticationManager.startAuthentication(siteUrl, this)
                }
            }
            .setNegativeButton(getString(R.string.cancel), null)
            .show()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        authenticationManager.processAuthenticationResult(intent, this)
    }

    override fun onAuthenticationSuccess(siteUrl: String, siteApiRoot: String, authToken: String) {
        val siteName = siteUrl.removePrefix("https://").removePrefix("http://").substringBefore("/")
        val newConfig = ConfigurationItem.RemoteEditor(
            name = siteName,
            siteUrl = siteUrl,
            siteApiRoot = siteApiRoot,
            authHeader = authToken
        )
        configurations.add(newConfig)
        adapter.notifyItemInserted(configurations.size - 1)
        configurationStorage.saveConfigurations(configurations)
    }

    override fun onAuthenticationFailure(errorMessage: String) {
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
                configurationStorage.saveConfigurations(configurations)
            }
            .setNegativeButton(getString(R.string.cancel), null)
            .show()
    }
}