package com.example.gutenbergkit

import android.content.Context
import android.content.Intent
import android.os.Bundle
import org.json.JSONObject
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModelProvider
import com.example.gutenbergkit.ui.theme.AppTheme
import org.wordpress.gutenberg.model.EditorConfiguration
import org.wordpress.gutenberg.model.EditorDependenciesSerializer

class SitePreparationActivity : ComponentActivity() {

    companion object {
        private const val EXTRA_CONFIGURATION_ITEM = "configuration_item"
        private const val KEY_TYPE = "type"
        private const val KEY_NAME = "name"
        private const val KEY_SITE_URL = "siteUrl"
        private const val KEY_SITE_API_ROOT = "siteApiRoot"
        private const val KEY_AUTH_HEADER = "authHeader"
        private const val TYPE_BUNDLED = "bundled"
        private const val TYPE_CONFIGURED = "configured"

        fun createIntent(context: Context, configurationItem: ConfigurationItem): Intent {
            return Intent(context, SitePreparationActivity::class.java).apply {
                putExtra(EXTRA_CONFIGURATION_ITEM, configurationItem.toJson())
            }
        }

        private fun ConfigurationItem.toJson(): String {
            return when (this) {
                is ConfigurationItem.BundledEditor -> {
                    JSONObject().apply {
                        put(KEY_TYPE, TYPE_BUNDLED)
                    }.toString()
                }
                is ConfigurationItem.ConfiguredEditor -> {
                    JSONObject().apply {
                        put(KEY_TYPE, TYPE_CONFIGURED)
                        put(KEY_NAME, name)
                        put(KEY_SITE_URL, siteUrl)
                        put(KEY_SITE_API_ROOT, siteApiRoot)
                        put(KEY_AUTH_HEADER, authHeader)
                    }.toString()
                }
            }
        }

        private fun parseConfigurationItem(extra: String?): ConfigurationItem {
            if (extra == null) {
                return ConfigurationItem.BundledEditor
            }

            return try {
                val json = JSONObject(extra)
                when (json.optString(KEY_TYPE)) {
                    TYPE_CONFIGURED -> {
                        ConfigurationItem.ConfiguredEditor(
                            name = json.getString(KEY_NAME),
                            siteUrl = json.getString(KEY_SITE_URL),
                            siteApiRoot = json.getString(KEY_SITE_API_ROOT),
                            authHeader = json.getString(KEY_AUTH_HEADER)
                        )
                    }
                    else -> ConfigurationItem.BundledEditor
                }
            } catch (e: Exception) {
                ConfigurationItem.BundledEditor
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val configurationItem = parseConfigurationItem(
            intent.getStringExtra(EXTRA_CONFIGURATION_ITEM)
        )

        val viewModel = ViewModelProvider(
            this,
            SitePreparationViewModelFactory(application, configurationItem)
        )[SitePreparationViewModel::class.java]

        setContent {
            AppTheme {
                SitePreparationScreen(
                    viewModel = viewModel,
                    onClose = { finish() },
                    onStartEditor = { configuration, dependencies ->
                        launchEditor(configuration, dependencies)
                    }
                )
            }
        }
    }

    private fun launchEditor(
        configuration: EditorConfiguration,
        dependencies: org.wordpress.gutenberg.model.EditorDependencies?
    ) {
        val intent = Intent(this, EditorActivity::class.java).apply {
            putExtra(MainActivity.EXTRA_CONFIGURATION, configuration)

            // Serialize dependencies to disk and pass the file path
            if (dependencies != null) {
                val filePath = EditorDependenciesSerializer.writeToDisk(this@SitePreparationActivity, dependencies)
                putExtra(EditorActivity.EXTRA_DEPENDENCIES_PATH, filePath)
            }
        }
        startActivity(intent)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SitePreparationScreen(
    viewModel: SitePreparationViewModel,
    onClose: () -> Unit,
    onStartEditor: (EditorConfiguration, org.wordpress.gutenberg.model.EditorDependencies?) -> Unit
) {
    val uiState by viewModel.uiState.collectAsState()

    LaunchedEffect(Unit) {
        viewModel.startLoading()
    }

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text("Editor Configuration") },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back"
                        )
                    }
                },
                actions = {
                    if (uiState.editorConfiguration != null) {
                        Button(
                            onClick = {
                                viewModel.buildConfiguration()?.let { config ->
                                    onStartEditor(config, uiState.editorDependencies)
                                }
                            },
                            modifier = Modifier.padding(end = 8.dp)
                        ) {
                            Text("Start")
                        }
                    }
                }
            )
        }
    ) { innerPadding ->
        if (uiState.editorConfiguration == null) {
            LoadingView(modifier = Modifier.padding(innerPadding))
        } else {
            LoadedView(
                uiState = uiState,
                viewModel = viewModel,
                modifier = Modifier.padding(innerPadding)
            )
        }
    }
}

@Composable
private fun LoadingView(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            CircularProgressIndicator()
            Text("Loading Site Configuration")
        }
    }
}

@Composable
private fun LoadedView(
    uiState: SitePreparationUiState,
    viewModel: SitePreparationViewModel,
    modifier: Modifier = Modifier
) {
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Dependencies Status
        item {
            DependenciesStatusCard(
                hasDependencies = uiState.editorDependencies != null
            )
        }

        // Feature Configuration
        item {
            FeatureConfigurationCard(
                enableNativeInserter = uiState.enableNativeInserter,
                onEnableNativeInserterChange = viewModel::setEnableNativeInserter,
                enableNetworkLogging = uiState.enableNetworkLogging,
                onEnableNetworkLoggingChange = viewModel::setEnableNetworkLogging,
                postType = uiState.postType,
                onPostTypeChange = viewModel::setPostType
            )
        }

        // Editor Configuration Details
        uiState.editorConfiguration?.let { config ->
            item {
                EditorConfigurationDetailsCard(configuration = config)
            }
        }

        // Local Caches
        item {
            LocalCachesCard(
                isLoading = uiState.isLoading,
                loadingProgress = uiState.loadingProgress,
                cacheBundleCount = uiState.cacheBundleCount,
                onPrepareEditor = viewModel::prepareEditor,
                onPrepareEditorIgnoringCache = viewModel::prepareEditorFromScratch,
                onClearCache = viewModel::resetEditorCaches
            )
        }

        // Error
        uiState.error?.let { error ->
            item {
                ErrorCard(error = error)
            }
        }
    }
}

@Composable
private fun DependenciesStatusCard(hasDependencies: Boolean) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = if (hasDependencies) {
                MaterialTheme.colorScheme.primaryContainer
            } else {
                MaterialTheme.colorScheme.surfaceVariant
            }
        )
    ) {
        ListItem(
            headlineContent = {
                Text(
                    if (hasDependencies) {
                        "Editor Dependencies Loaded"
                    } else {
                        "Editor Dependencies Missing"
                    }
                )
            },
            supportingContent = {
                Text(
                    if (hasDependencies) {
                        "The editor should load instantly"
                    } else {
                        "The editor will need to load them when it starts"
                    }
                )
            },
            leadingContent = {
                Icon(
                    imageVector = if (hasDependencies) Icons.Default.CheckCircle else Icons.Default.Cancel,
                    contentDescription = null,
                    tint = if (hasDependencies) Color(0xFF4CAF50) else MaterialTheme.colorScheme.outline
                )
            }
        )
    }
}

@Composable
private fun FeatureConfigurationCard(
    enableNativeInserter: Boolean,
    onEnableNativeInserterChange: (Boolean) -> Unit,
    enableNetworkLogging: Boolean,
    onEnableNetworkLoggingChange: (Boolean) -> Unit,
    postType: String,
    onPostTypeChange: (String) -> Unit
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "Feature Configuration",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(bottom = 8.dp)
            )

            // Enable Native Inserter Toggle
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("Enable Native Inserter")
                Switch(
                    checked = enableNativeInserter,
                    onCheckedChange = onEnableNativeInserterChange
                )
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

            // Enable Network Logging Toggle
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("Enable Network Logging")
                Switch(
                    checked = enableNetworkLogging,
                    onCheckedChange = onEnableNetworkLoggingChange
                )
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

            // Post Type Picker
            Text(
                text = "Post Type",
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(bottom = 8.dp)
            )
            Column(modifier = Modifier.selectableGroup()) {
                listOf("post" to "Post", "page" to "Page").forEach { (value, label) ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .selectable(
                                selected = postType == value,
                                onClick = { onPostTypeChange(value) },
                                role = Role.RadioButton
                            )
                            .padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        RadioButton(
                            selected = postType == value,
                            onClick = null
                        )
                        Text(
                            text = label,
                            modifier = Modifier.padding(start = 8.dp)
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun EditorConfigurationDetailsCard(configuration: EditorConfiguration) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "Editor Configuration Details",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(bottom = 8.dp)
            )

            KeyValueRow(key = "Site URL", value = configuration.siteURL)
            KeyValueRow(key = "API Root", value = configuration.siteApiRoot)
            KeyValueBooleanRow(key = "Supports Block Assets", value = configuration.plugins)
            KeyValueBooleanRow(key = "Supports Theme Styles", value = configuration.themeStyles)
        }
    }
}

@Composable
private fun LocalCachesCard(
    isLoading: Boolean,
    loadingProgress: Float?,
    cacheBundleCount: Int?,
    onPrepareEditor: () -> Unit,
    onPrepareEditorIgnoringCache: () -> Unit,
    onClearCache: () -> Unit
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "Local Caches",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(bottom = 8.dp)
            )

            cacheBundleCount?.let { count ->
                Text(
                    text = "Asset bundles on disk: $count",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(bottom = 8.dp)
                )
            }

            Button(
                onClick = onPrepareEditor,
                enabled = !isLoading,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Prepare Editor")
            }

            Spacer(modifier = Modifier.height(8.dp))

            OutlinedButton(
                onClick = onPrepareEditorIgnoringCache,
                enabled = !isLoading,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Prepare Editor Ignoring Cache")
            }

            Spacer(modifier = Modifier.height(8.dp))

            OutlinedButton(
                onClick = onClearCache,
                enabled = !isLoading,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Clear Preload Cache")
            }

            loadingProgress?.let { progress ->
                Spacer(modifier = Modifier.height(16.dp))
                LinearProgressIndicator(
                    progress = { progress },
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }
    }
}

@Composable
private fun ErrorCard(error: String) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.errorContainer
        )
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "Error",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onErrorContainer
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = error,
                color = MaterialTheme.colorScheme.onErrorContainer
            )
        }
    }
}

@Composable
private fun KeyValueRow(key: String, value: String) {
    Column(modifier = Modifier.padding(vertical = 4.dp)) {
        Text(
            text = key,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium
        )
    }
}

@Composable
private fun KeyValueBooleanRow(key: String, value: Boolean) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(text = key)
        Icon(
            imageVector = if (value) Icons.Default.CheckCircle else Icons.Default.Cancel,
            contentDescription = if (value) "Yes" else "No",
            tint = if (value) Color(0xFF4CAF50) else Color(0xFFF44336),
            modifier = Modifier.size(20.dp)
        )
    }
}
