package com.example.gutenbergkit

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.lifecycleScope
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.outlined.Computer
import androidx.compose.material.icons.outlined.Article
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.ui.platform.LocalContext
import org.wordpress.gutenberg.GutenbergView
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
import org.wordpress.gutenberg.BuildConfig
import uniffi.wp_mobile.Account

class MainActivity : ComponentActivity(), AuthenticationManager.AuthenticationCallback {
    private val configurations = mutableStateListOf<ConfigurationItem>()
    private val isDiscoveringSite = mutableStateOf(false)
    private val isLoadingCapabilities = mutableStateOf(false)
    private val authError = mutableStateOf<String?>(null)
    private val gutenbergKitApp by lazy { application as GutenbergKitApplication }
    private val accountRepository by lazy { gutenbergKitApp.accountRepository }
    private val networkAvailabilityProvider by lazy { gutenbergKitApp.networkAvailabilityProvider }
    private lateinit var authenticationManager: AuthenticationManager
    private val siteCapabilitiesDiscovery = SiteCapabilitiesDiscovery()

    companion object {
        const val EXTRA_CONFIGURATION = "configuration"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        authenticationManager = AuthenticationManager(this, accountRepository, networkAvailabilityProvider, lifecycleScope)

        // Add default bundled editor configuration
        configurations.add(ConfigurationItem.BundledEditor)

        // Add local WordPress option
        configurations.add(ConfigurationItem.LocalWordPress)

        // Load saved accounts
        configurations.addAll(
            accountRepository.all().map { ConfigurationItem.ConfiguredEditor.fromAccount(it) }
        )

        setContent {
            AppTheme {
                MainScreen(
                    configurations = configurations,
                    onConfigurationClick = { config ->
                        when (config) {
                            is ConfigurationItem.BundledEditor -> launchSitePreparation(config)
                            is ConfigurationItem.LocalWordPress -> launchSitePreparation(config)
                            is ConfigurationItem.ConfiguredEditor -> launchSitePreparation(config)
                        }
                    },
                    onConfigurationLongClick = { config ->
                        when (config) {
                            is ConfigurationItem.BundledEditor -> false
                            is ConfigurationItem.LocalWordPress -> false
                            is ConfigurationItem.ConfiguredEditor -> true
                        }
                    },
                    onAddConfiguration = { siteUrl ->
                        isDiscoveringSite.value = true
                        authenticationManager.startAuthentication(siteUrl, this)
                    },
                    onDeleteConfiguration = { config ->
                        if (config is ConfigurationItem.ConfiguredEditor) {
                            accountRepository.remove(config.accountId)
                        }
                        configurations.remove(config)
                    },
                    onMediaProxyServer = {
                        startActivity(Intent(this, MediaProxyServerActivity::class.java))
                    },
                    isDiscoveringSite = isDiscoveringSite.value,
                    onDismissDiscovering = { isDiscoveringSite.value = false },
                    isLoadingCapabilities = isLoadingCapabilities.value,
                    authError = authError.value,
                    onDismissAuthError = { authError.value = null }
                )
            }
        }
    }

    private fun launchSitePreparation(config: ConfigurationItem) {
        val intent = SitePreparationActivity.createIntent(this, config)
        startActivity(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        authenticationManager.processAuthenticationResult(intent, this)
    }

    override fun onAuthenticationSuccess(account: Account) {
        isDiscoveringSite.value = false
        configurations.add(ConfigurationItem.ConfiguredEditor.fromAccount(account))
    }

    override fun onAuthenticationFailure(errorMessage: String) {
        isDiscoveringSite.value = false
        authError.value = errorMessage
    }
}

private fun isDevServerRunning(): Boolean {
    return BuildConfig.GUTENBERG_EDITOR_URL.isNotEmpty()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(
    configurations: List<ConfigurationItem>,
    onConfigurationClick: (ConfigurationItem) -> Unit,
    onConfigurationLongClick: (ConfigurationItem) -> Boolean,
    onAddConfiguration: (String) -> Unit,
    onDeleteConfiguration: (ConfigurationItem) -> Unit,
    onMediaProxyServer: () -> Unit = {},
    isDiscoveringSite: Boolean = false,
    onDismissDiscovering: () -> Unit = {},
    isLoadingCapabilities: Boolean = false,
    authError: String? = null,
    onDismissAuthError: () -> Unit = {}
) {
    var showAddDialog = remember { mutableStateOf(false) }
    var showDeleteDialog = remember { mutableStateOf<ConfigurationItem.ConfiguredEditor?>(null) }
    var siteUrlInput = remember { mutableStateOf("") }
    var showOverflowMenu = remember { mutableStateOf(false) }
    val context = LocalContext.current

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.demo_title)) },
                actions = {
                    IconButton(onClick = { showOverflowMenu.value = true }) {
                        Icon(
                            imageVector = Icons.Default.MoreVert,
                            contentDescription = stringResource(R.string.more_options)
                        )
                    }
                    DropdownMenu(
                        expanded = showOverflowMenu.value,
                        onDismissRequest = { showOverflowMenu.value = false }
                    ) {
                        DropdownMenuItem(
                            text = { Text("Media Proxy Server") },
                            onClick = {
                                showOverflowMenu.value = false
                                onMediaProxyServer()
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("Reset Photo Permissions Prompts") },
                            onClick = {
                                showOverflowMenu.value = false
                                GutenbergView.resetBlockPickerPhotoPreferences(context)
                            }
                        )
                    }
                }
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = { showAddDialog.value = true }
            ) {
                Icon(
                    imageVector = Icons.Default.Add,
                    contentDescription = stringResource(R.string.add_wordpress_site_description)
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
            item {
                val editorSourceNote = if (isDevServerRunning()) {
                    stringResource(R.string.editor_source_dev_server)
                } else {
                    stringResource(R.string.editor_source_built)
                }
                Text(
                    text = editorSourceNote,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp)
                )
            }

            // Standalone editor
            item {
                ConfigurationCard(
                    configuration = ConfigurationItem.BundledEditor,
                    onClick = { onConfigurationClick(ConfigurationItem.BundledEditor) },
                    onLongClick = { }
                )
            }

            // WordPress Sites section
            val configuredEditors = configurations.filterIsInstance<ConfigurationItem.ConfiguredEditor>()

            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp)
                ) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = stringResource(R.string.wordpress_sites_section).uppercase(),
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(vertical = 8.dp)
                    )
                    Text(
                        text = stringResource(R.string.wordpress_sites_section_description),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(bottom = 8.dp)
                    )
                }
            }

            // Local WordPress
            item {
                ConfigurationCard(
                    configuration = ConfigurationItem.LocalWordPress,
                    onClick = { onConfigurationClick(ConfigurationItem.LocalWordPress) },
                    onLongClick = { }
                )
            }

            items(configuredEditors) { config ->
                ConfigurationCard(
                    configuration = config,
                    onClick = { onConfigurationClick(config) },
                    onLongClick = {
                        showDeleteDialog.value = config
                    }
                )
            }

            item {
                AddNewConfigurationCard(
                    onClick = { showAddDialog.value = true }
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

    if (isLoadingCapabilities) {
        DiscoveringSiteDialog(
            onDismiss = { /* Cannot dismiss while loading */ }
        )
    }

    authError?.let { error ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = onDismissAuthError,
            title = { Text("Authentication Error") },
            text = { Text(error) },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = onDismissAuthError) {
                    Text("OK")
                }
            }
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
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
                        is ConfigurationItem.LocalWordPress -> stringResource(R.string.local_wordpress)
                        is ConfigurationItem.ConfiguredEditor -> configuration.name
                    }
                )
            },
            supportingContent = when (configuration) {
                is ConfigurationItem.BundledEditor -> {
                    { Text(stringResource(R.string.bundled_editor_subtitle)) }
                }
                is ConfigurationItem.LocalWordPress -> {
                    {
                        val isConfigured = LocalWordPressCredentials.load() != null
                        Text(
                            if (isConfigured) stringResource(R.string.local_wordpress_subtitle)
                            else stringResource(R.string.local_wordpress_subtitle_not_configured)
                        )
                    }
                }
                is ConfigurationItem.ConfiguredEditor -> null
            },
            leadingContent = {
                Icon(
                    imageVector = when (configuration) {
                        is ConfigurationItem.BundledEditor -> Icons.Outlined.Article
                        is ConfigurationItem.LocalWordPress -> Icons.Outlined.Computer
                        is ConfigurationItem.ConfiguredEditor -> Icons.Default.Language
                    },
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary
                )
            }
        )
    }
}

@Composable
fun AddNewConfigurationCard(
    onClick: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth(),
        onClick = onClick
    ) {
        ListItem(
            headlineContent = {
                Text(stringResource(R.string.add_wordpress_site))
            },
            leadingContent = {
                Icon(
                    imageVector = Icons.Default.Add,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary
                )
            }
        )
    }
}
