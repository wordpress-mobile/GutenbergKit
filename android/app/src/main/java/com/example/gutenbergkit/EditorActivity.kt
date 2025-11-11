package com.example.gutenbergkit

import android.content.Intent
import android.os.Bundle
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
import kotlinx.coroutines.launch
import org.wordpress.gutenberg.EditorConfiguration
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
            lifecycleScope.launch {
                gutenbergView?.handleFilePickerResult(this@EditorActivity, result.data)
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
