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
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.example.gutenbergkit.ui.dialogs.AddConfigurationDialog
import com.example.gutenbergkit.ui.dialogs.DeleteConfigurationDialog
import com.example.gutenbergkit.ui.dialogs.DiscoveringSiteDialog
import com.example.gutenbergkit.ui.theme.AppTheme
import org.wordpress.gutenberg.EditorConfiguration

class MainActivity : ComponentActivity(), AuthenticationManager.AuthenticationCallback {
    private val configurations = mutableStateListOf<ConfigurationItem>()
    private val isDiscoveringSite = mutableStateOf(false)
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
                        isDiscoveringSite.value = true
                        authenticationManager.startAuthentication(siteUrl, this)
                    },
                    onDeleteConfiguration = { config ->
                        configurations.remove(config)
                        configurationStorage.saveConfigurations(configurations)
                    },
                    isDiscoveringSite = isDiscoveringSite.value,
                    onDismissDiscovering = { isDiscoveringSite.value = false }
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
            .setPlugins(true)
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
        isDiscoveringSite.value = false
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
        isDiscoveringSite.value = false
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
    onDeleteConfiguration: (ConfigurationItem) -> Unit,
    isDiscoveringSite: Boolean = false,
    onDismissDiscovering: () -> Unit = {}
) {
    var showAddDialog = remember { mutableStateOf(false) }
    var showDeleteDialog = remember { mutableStateOf<ConfigurationItem.RemoteEditor?>(null) }
    var siteUrlInput = remember { mutableStateOf("") }

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.demo_title)) }
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = { showAddDialog.value = true }
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
                            showDeleteDialog.value = config
                        }
                    }
                )
            }
        }
    }

    if (showAddDialog.value) {
        AddConfigurationDialog(
            siteUrlInput = siteUrlInput.value,
            onSiteUrlChange = { siteUrlInput.value = it },
            onConfirm = {
                if (siteUrlInput.value.isNotBlank()) {
                    onAddConfiguration(siteUrlInput.value.trim())
                    showAddDialog.value = false
                    siteUrlInput.value = ""
                }
            },
            onDismiss = { showAddDialog.value = false }
        )
    }

    showDeleteDialog.value?.let { config ->
        DeleteConfigurationDialog(
            onConfirm = {
                onDeleteConfiguration(config)
                showDeleteDialog.value = null
            },
            onDismiss = { showDeleteDialog.value = null }
        )
    }

    if (isDiscoveringSite) {
        DiscoveringSiteDialog(
            onDismiss = onDismissDiscovering
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
