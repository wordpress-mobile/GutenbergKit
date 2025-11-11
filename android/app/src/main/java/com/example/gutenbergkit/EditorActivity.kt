package com.example.gutenbergkit

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.webkit.WebView
import android.content.pm.ApplicationInfo
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Redo
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.lifecycleScope
import com.example.gutenbergkit.ui.theme.AppTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.wordpress.gutenberg.EditorConfiguration
import org.wordpress.gutenberg.FileCache
import org.wordpress.gutenberg.GutenbergView

class EditorActivity : ComponentActivity() {
    private var gutenbergView: GutenbergView? = null
    private lateinit var filePickerLauncher: ActivityResultLauncher<Intent>
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        // Register file picker launcher before setContent
        filePickerLauncher = registerForActivityResult(
            ActivityResultContracts.StartActivityForResult()
        ) { result ->
            val data = result.data
            val uris = if (data != null) {
                if (data.clipData != null) {
                    // Multiple files selected
                    val clipData = data.clipData!!
                    Array(clipData.itemCount) { i ->
                        clipData.getItemAt(i).uri
                    }
                } else if (data.data != null) {
                    // Single file selected
                    arrayOf(data.data)
                } else {
                    null
                }
            } else {
                null
            }

            // Process URIs asynchronously to avoid blocking the main thread
            lifecycleScope.launch {
                val processedUris = processSelectedFiles(uris)
                // Pass the result back to the WebView on the main thread
                gutenbergView?.filePathCallback?.onReceiveValue(processedUris)
                gutenbergView?.resetFilePathCallback()
            }
        }

        if (0 != (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE)) {
            WebView.setWebContentsDebuggingEnabled(true)
        }

        // Get the configuration from the intent
        val configuration =
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(
                    MainActivity.EXTRA_CONFIGURATION,
                    EditorConfiguration::class.java
                )
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<EditorConfiguration>(MainActivity.EXTRA_CONFIGURATION)
            } ?: EditorConfiguration.builder().build()

        setContent {
            AppTheme {
                EditorScreen(
                    configuration = configuration,
                    onClose = { finish() },
                    onGutenbergViewCreated = { view ->
                        gutenbergView = view
                        setupFileChooserListener(view)
                    }
                )
            }
        }
    }

    private fun setupFileChooserListener(view: GutenbergView) {
        view.setOnFileChooserRequestedListener { intent, _ ->
            filePickerLauncher.launch(intent)
        }
    }

    /**
     * Processes selected files by copying content:// URIs to cache to avoid
     * ERR_UPLOAD_FILE_CHANGED errors when uploading from cloud storage providers.
     *
     * @param uris Array of selected file URIs
     * @return Array of processed URIs (cached for content:// URIs, original for others)
     */
    private suspend fun processSelectedFiles(uris: Array<Uri?>?): Array<Uri?>? {
        if (uris == null) {
            return null
        }

        return withContext(Dispatchers.IO) {
            uris.map { uri ->
                if (uri == null) {
                    return@map null
                }

                // Only process content:// URIs that are media files
                if (uri.scheme == "content" && FileCache.isMediaFile(this@EditorActivity, uri)) {
                    val cachedUri = FileCache.copyToCache(this@EditorActivity, uri)
                    if (cachedUri != null) {
                        Log.i("EditorActivity", "Copied content URI to cache: $uri -> $cachedUri")
                        cachedUri
                    } else {
                        Log.w("EditorActivity", "Failed to copy content URI to cache, using original: $uri")
                        uri
                    }
                } else {
                    // Pass through file:// URIs and non-media content:// URIs unchanged
                    uri
                }
            }.toTypedArray()
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditorScreen(
    configuration: EditorConfiguration,
    onClose: () -> Unit,
    onGutenbergViewCreated: (GutenbergView) -> Unit = {}
) {
    var showMenu by remember { mutableStateOf(false) }
    var isModalDialogOpen by remember { mutableStateOf(false) }
    var hasUndoState by remember { mutableStateOf(false) }
    var hasRedoState by remember { mutableStateOf(false) }
    var isCodeEditorEnabled by remember { mutableStateOf(false) }
    var gutenbergViewRef by remember { mutableStateOf<GutenbergView?>(null) }

    BackHandler(enabled = isModalDialogOpen) {
        gutenbergViewRef?.dismissTopModal()
    }

    Scaffold(
        modifier = Modifier
            .fillMaxSize()
            .imePadding(),
        topBar = {
            TopAppBar(
                title = { },
                navigationIcon = {
                    IconButton(
                        onClick = onClose,
                        enabled = !isModalDialogOpen
                    ) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.close)
                        )
                    }
                },
                actions = {
                    IconButton(
                        onClick = { gutenbergViewRef?.undo() },
                        enabled = hasUndoState && !isModalDialogOpen
                    ) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.Undo,
                            contentDescription = stringResource(R.string.undo)
                        )
                    }
                    IconButton(
                        onClick = { gutenbergViewRef?.redo() },
                        enabled = hasRedoState && !isModalDialogOpen
                    ) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.Redo,
                            contentDescription = stringResource(R.string.redo)
                        )
                    }
                    TextButton(onClick = { }, enabled = false) {
                        Text(stringResource(R.string.publish))
                    }

                    // Overflow menu button and dropdown in Box for proper anchoring
                    Box {
                        IconButton(
                            onClick = { showMenu = true },
                            enabled = !isModalDialogOpen
                        ) {
                            Icon(
                                imageVector = Icons.Default.MoreVert,
                                contentDescription = stringResource(R.string.more_options)
                            )
                        }
                        DropdownMenu(
                            expanded = showMenu,
                            onDismissRequest = { showMenu = false }
                        ) {
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.save)) },
                                onClick = { },
                                enabled = false
                            )
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.preview)) },
                                onClick = { },
                                enabled = false
                            )
                            DropdownMenuItem(
                                text = { Text(stringResource(if (isCodeEditorEnabled) R.string.visual_editor else R.string.code_editor)) },
                                onClick = {
                                    isCodeEditorEnabled = !isCodeEditorEnabled
                                    gutenbergViewRef?.textEditorEnabled = isCodeEditorEnabled
                                    showMenu = false
                                }
                            )
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.post_settings)) },
                                onClick = { },
                                enabled = false
                            )
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.help)) },
                                onClick = { },
                                enabled = false
                            )
                        }
                    }
                }
            )
        }
    ) { innerPadding ->
        AndroidView(
            factory = { context ->
                GutenbergView(context).apply {
                    gutenbergViewRef = this
                    setModalDialogStateListener(object : GutenbergView.ModalDialogStateListener {
                        override fun onModalDialogOpened(dialogType: String) {
                            isModalDialogOpen = true
                        }

                        override fun onModalDialogClosed(dialogType: String) {
                            isModalDialogOpen = false
                        }
                    })
                    setHistoryChangeListener(object : GutenbergView.HistoryChangeListener {
                        override fun onHistoryChanged(hasUndo: Boolean, hasRedo: Boolean) {
                            hasUndoState = hasUndo
                            hasRedoState = hasRedo
                        }
                    })
                    start(configuration)
                    onGutenbergViewCreated(this)
                }
            },
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        )
    }
}
