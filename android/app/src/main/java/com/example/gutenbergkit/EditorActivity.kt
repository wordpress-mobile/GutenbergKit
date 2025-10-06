package com.example.gutenbergkit

import android.os.Bundle
import android.webkit.WebView
import android.content.pm.ApplicationInfo
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
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
import androidx.compose.ui.viewinterop.AndroidView
import org.wordpress.gutenberg.EditorConfiguration
import org.wordpress.gutenberg.GutenbergView

class EditorActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

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
            EditorScreen(
                configuration = configuration,
                onClose = { finish() }
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditorScreen(
    configuration: EditorConfiguration,
    onClose: () -> Unit
) {
    var showMenu by remember { mutableStateOf(false) }
    var isModalDialogOpen by remember { mutableStateOf(false) }

    BackHandler(enabled = isModalDialogOpen) {
        // Do nothing - prevent back navigation when modal is open
        // The web layer will handle closing the modal
    }

    Scaffold(
        modifier = Modifier.fillMaxSize(),
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
                            contentDescription = "Close"
                        )
                    }
                },
                actions = {
                    IconButton(onClick = { }, enabled = false) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.Undo,
                            contentDescription = "Undo"
                        )
                    }
                    IconButton(onClick = { }, enabled = false) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.Redo,
                            contentDescription = "Redo"
                        )
                    }
                    TextButton(onClick = { }, enabled = false) {
                        Text("PUBLISH")
                    }

                    // Overflow menu button and dropdown in Box for proper anchoring
                    Box {
                        IconButton(
                            onClick = { showMenu = true },
                            enabled = !isModalDialogOpen
                        ) {
                            Icon(
                                imageVector = Icons.Default.MoreVert,
                                contentDescription = "More options"
                            )
                        }
                        DropdownMenu(
                            expanded = showMenu,
                            onDismissRequest = { showMenu = false }
                        ) {
                            DropdownMenuItem(
                                text = { Text("Save") },
                                onClick = { },
                                enabled = false
                            )
                            DropdownMenuItem(
                                text = { Text("Preview") },
                                onClick = { },
                                enabled = false
                            )
                            DropdownMenuItem(
                                text = { Text("Code editor") },
                                onClick = { },
                                enabled = false
                            )
                            DropdownMenuItem(
                                text = { Text("Post settings") },
                                onClick = { },
                                enabled = false
                            )
                            DropdownMenuItem(
                                text = { Text("Help") },
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
                    setModalDialogStateListener(object : GutenbergView.ModalDialogStateListener {
                        override fun onModalDialogOpened(dialogType: String) {
                            isModalDialogOpen = true
                        }

                        override fun onModalDialogClosed(dialogType: String) {
                            isModalDialogOpen = false
                        }
                    })
                    start(configuration)
                }
            },
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        )
    }
}