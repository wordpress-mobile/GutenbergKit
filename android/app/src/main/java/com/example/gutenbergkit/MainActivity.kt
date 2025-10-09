package com.example.gutenbergkit

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.example.gutenbergkit.ui.theme.AppTheme
import org.wordpress.gutenberg.EditorConfiguration

class MainActivity : ComponentActivity(), AuthenticationManager.AuthenticationCallback {
    private val configurations = mutableStateListOf<ConfigurationItem>()
    private lateinit var configurationStorage: ConfigurationStorage
    private lateinit var authenticationManager: AuthenticationManager

    companion object {
        const val EXTRA_CONFIGURATION = "configuration"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        configurationStorage = ConfigurationStorage(this)
        authenticationManager = AuthenticationManager(this)

        // Add default bundled editor configuration
        configurations.add(ConfigurationItem.BundledEditor)

        // Load saved configurations
        configurations.addAll(configurationStorage.loadConfigurations())

        setContent {
            AppTheme {
                MainScreen(
                    configurations = configurations,
                    onConfigurationClick = { config ->
                        when (config) {
                            is ConfigurationItem.BundledEditor -> launchEditor(createBundledConfiguration())
                            is ConfigurationItem.RemoteEditor -> launchEditor(createRemoteConfiguration(config))
                        }
                    },
                    onConfigurationLongClick = { config ->
                        when (config) {
                            is ConfigurationItem.BundledEditor -> false
                            is ConfigurationItem.RemoteEditor -> true
                        }
                    },
                    onAddConfiguration = { siteUrl ->
                        authenticationManager.startAuthentication(siteUrl, this)
                    },
                    onDeleteConfiguration = { config ->
                        configurations.remove(config)
                        configurationStorage.saveConfigurations(configurations)
                    }
                )
            }
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
        configurationStorage.saveConfigurations(configurations)
    }

    override fun onAuthenticationFailure(errorMessage: String) {
        // Error will be shown in Compose UI
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(
    configurations: List<ConfigurationItem>,
    onConfigurationClick: (ConfigurationItem) -> Unit,
    onConfigurationLongClick: (ConfigurationItem) -> Boolean,
    onAddConfiguration: (String) -> Unit,
    onDeleteConfiguration: (ConfigurationItem) -> Unit
) {
    var showAddDialog by remember { mutableStateOf(false) }
    var showDeleteDialog by remember { mutableStateOf<ConfigurationItem.RemoteEditor?>(null) }
    var siteUrlInput by remember { mutableStateOf("") }

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.demo_title)) }
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = { showAddDialog = true }
            ) {
                Icon(
                    imageVector = Icons.Default.Add,
                    contentDescription = stringResource(R.string.add_remote_editor_description)
                )
            }
        }
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(configurations) { config ->
                ConfigurationCard(
                    configuration = config,
                    onClick = { onConfigurationClick(config) },
                    onLongClick = {
                        if (config is ConfigurationItem.RemoteEditor) {
                            showDeleteDialog = config
                        }
                    }
                )
            }
        }
    }

    // Add Configuration Dialog
    if (showAddDialog) {
        AlertDialog(
            onDismissRequest = { showAddDialog = false },
            title = { Text(stringResource(R.string.add_remote_editor)) },
            text = {
                OutlinedTextField(
                    value = siteUrlInput,
                    onValueChange = { siteUrlInput = it },
                    label = { Text(stringResource(R.string.site_url)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        if (siteUrlInput.isNotBlank()) {
                            onAddConfiguration(siteUrlInput.trim())
                            showAddDialog = false
                            siteUrlInput = ""
                        }
                    }
                ) {
                    Text(stringResource(R.string.add))
                }
            },
            dismissButton = {
                TextButton(onClick = { showAddDialog = false }) {
                    Text(stringResource(R.string.cancel))
                }
            }
        )
    }

    // Delete Configuration Dialog
    showDeleteDialog?.let { config ->
        AlertDialog(
            onDismissRequest = { showDeleteDialog = null },
            title = { Text(stringResource(R.string.delete_site_title)) },
            text = { Text(stringResource(R.string.delete_site_message)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        onDeleteConfiguration(config)
                        showDeleteDialog = null
                    }
                ) {
                    Text(stringResource(R.string.delete))
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteDialog = null }) {
                    Text(stringResource(R.string.cancel))
                }
            }
        )
    }
}

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun ConfigurationCard(
    configuration: ConfigurationItem,
    onClick: () -> Unit,
    onLongClick: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(
                onClick = onClick,
                onLongClick = onLongClick
            )
    ) {
        ListItem(
            headlineContent = {
                Text(
                    when (configuration) {
                        is ConfigurationItem.BundledEditor -> stringResource(R.string.bundled_editor)
                        is ConfigurationItem.RemoteEditor -> configuration.name
                    }
                )
            },
            supportingContent = {
                Text(
                    when (configuration) {
                        is ConfigurationItem.BundledEditor -> stringResource(R.string.bundled_editor_subtitle)
                        is ConfigurationItem.RemoteEditor -> configuration.siteUrl
                    }
                )
            },
            leadingContent = {
                Icon(
                    imageVector = when (configuration) {
                        is ConfigurationItem.BundledEditor -> Icons.Outlined.Inventory2
                        is ConfigurationItem.RemoteEditor -> Icons.Default.Language
                    },
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary
                )
            }
        )
    }
}