package com.example.gutenbergkit

import android.content.Intent
import android.os.Bundle
import android.view.ViewGroup
import android.webkit.WebView
import android.content.pm.ApplicationInfo
import android.os.Build
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
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
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.lifecycleScope
import com.example.gutenbergkit.ui.theme.AppTheme
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import org.wordpress.gutenberg.model.EditorConfiguration
import org.wordpress.gutenberg.GutenbergView
import org.wordpress.gutenberg.EditorLoadingListener
import org.wordpress.gutenberg.MediaUploadDelegate
import org.wordpress.gutenberg.RecordedNetworkRequest
import org.wordpress.gutenberg.model.EditorDependencies
import org.wordpress.gutenberg.model.EditorDependenciesSerializer
import org.wordpress.gutenberg.model.EditorProgress
import java.io.File

class EditorActivity : ComponentActivity() {

    companion object {
        const val EXTRA_DEPENDENCIES_PATH = "dependencies_path"
        const val EXTRA_ENABLE_NATIVE_MEDIA_UPLOAD = "enable_native_media_upload"
    }

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
                val uris = gutenbergView?.extractUrisFromIntent(result.data)
                val processedUris = gutenbergView?.processFileUris(this@EditorActivity, uris)
                gutenbergView?.filePathCallback?.onReceiveValue(processedUris)
                gutenbergView?.resetFilePathCallback()
            }
        }

        if (0 != (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE)) {
            WebView.setWebContentsDebuggingEnabled(true)
        }

        // Get the configuration from the intent
        val configuration =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(
                    MainActivity.EXTRA_CONFIGURATION,
                    EditorConfiguration::class.java
                )
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<EditorConfiguration>(MainActivity.EXTRA_CONFIGURATION)
            } ?: EditorConfiguration.bundled()

        // Read dependencies from disk if a file path was provided
        val dependenciesPath = intent.getStringExtra(EXTRA_DEPENDENCIES_PATH)
        val dependencies = dependenciesPath?.let { EditorDependenciesSerializer.readFromDisk(it) }

        val enableNativeMediaUpload = intent.getBooleanExtra(EXTRA_ENABLE_NATIVE_MEDIA_UPLOAD, true)

        setContent {
            AppTheme {
                EditorScreen(
                    configuration = configuration,
                    dependencies = dependencies,
                    enableNativeMediaUpload = enableNativeMediaUpload,
                    coroutineScope =  this.lifecycleScope,
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

/**
 * Loading state for the editor.
 */
enum class EditorLoadingState {
    /** Dependencies are being loaded from the network */
    LOADING_DEPENDENCIES,
    /** Dependencies loaded, waiting for WebView to initialize */
    LOADING_EDITOR,
    /** Editor is fully ready */
    READY,
    /** Loading failed with an error */
    ERROR
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditorScreen(
    configuration: EditorConfiguration,
    dependencies: EditorDependencies? = null,
    enableNativeMediaUpload: Boolean = true,
    coroutineScope: CoroutineScope,
    onClose: () -> Unit,
    onGutenbergViewCreated: (GutenbergView) -> Unit = {}
) {
    var showMenu by remember { mutableStateOf(false) }
    var isModalDialogOpen by remember { mutableStateOf(false) }
    var hasUndoState by remember { mutableStateOf(false) }
    var hasRedoState by remember { mutableStateOf(false) }
    var isCodeEditorEnabled by remember { mutableStateOf(false) }
    var gutenbergViewRef by remember { mutableStateOf<GutenbergView?>(null) }

    // Loading state
    var loadingState by remember {
        mutableStateOf(
            if (dependencies != null) EditorLoadingState.LOADING_EDITOR
            else EditorLoadingState.LOADING_DEPENDENCIES
        )
    }
    var loadingProgress by remember { mutableFloatStateOf(0f) }
    var loadingError by remember { mutableStateOf<String?>(null) }

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
                GutenbergView(
                    configuration = configuration,
                    dependencies = dependencies,
                    coroutineScope = coroutineScope,
                    context = context
                ).apply {
                    // Explicitly set layoutParams to MATCH_PARENT to ensure proper
                    // viewport dimension communication to the WebView for CSS units.
                    layoutParams = ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT
                    )

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
                    setNetworkRequestListener(object : GutenbergView.NetworkRequestListener {
                        override fun onNetworkRequest(request: RecordedNetworkRequest) {
                            Log.d("EditorActivity", "🌐 Network Request: ${request.method} ${request.url}")
                            Log.d("EditorActivity", "   Status: ${request.status} ${request.statusText}, Duration: ${request.duration}ms")

                            // Log request headers
                            if (request.requestHeaders.isNotEmpty()) {
                                Log.d("EditorActivity", "   Request Headers:")
                                request.requestHeaders.toSortedMap().forEach { (key, value) ->
                                    Log.d("EditorActivity", "      $key: $value")
                                }
                            }

                            request.requestBody?.let {
                                Log.d("EditorActivity", "   Request Body: ${it.take(200)}...")
                            }

                            // Log response headers
                            if (request.responseHeaders.isNotEmpty()) {
                                Log.d("EditorActivity", "   Response Headers:")
                                request.responseHeaders.toSortedMap().forEach { (key, value) ->
                                    Log.d("EditorActivity", "      $key: $value")
                                }
                            }

                            request.responseBody?.let {
                                Log.d("EditorActivity", "   Response Body: ${it.take(200)}...")
                            }
                        }
                    })
                    setEditorLoadingListener(object : EditorLoadingListener {
                        override fun onDependencyLoadingStarted() {
                            loadingState = EditorLoadingState.LOADING_DEPENDENCIES
                            loadingProgress = 0f
                        }

                        override fun onDependencyLoadingProgress(progress: EditorProgress) {
                            loadingProgress = progress.fractionCompleted.toFloat()
                        }

                        override fun onDependencyLoadingFinished() {
                            loadingState = EditorLoadingState.LOADING_EDITOR
                        }

                        override fun onEditorReady() {
                            loadingState = EditorLoadingState.READY
                        }

                        override fun onDependencyLoadingFailed(error: Throwable) {
                            loadingState = EditorLoadingState.ERROR
                            loadingError = error.message ?: "Unknown error"
                        }
                    })
                    // Demo app has no persistence layer, so return null.
                    // In a real app, return the persisted title and content from autosave.
                    setLatestContentProvider(object : GutenbergView.LatestContentProvider {
                        override fun getLatestContent(): GutenbergView.LatestContent? {
                            return null
                        }
                    })
                    if (enableNativeMediaUpload) {
                        mediaUploadDelegate = DemoMediaUploadDelegate(context)
                    }
                    onGutenbergViewCreated(this)
                }
            },
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        )

        // Loading overlay
        when (loadingState) {
            EditorLoadingState.LOADING_DEPENDENCIES -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
                    contentAlignment = Alignment.Center
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        LinearProgressIndicator(
                            progress = { loadingProgress },
                            modifier = Modifier.fillMaxWidth(0.6f)
                        )
                        Text("Loading Editor...")
                    }
                }
            }
            EditorLoadingState.LOADING_EDITOR -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
                    contentAlignment = Alignment.Center
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        CircularProgressIndicator()
                        Text("Starting Editor...")
                    }
                }
            }
            EditorLoadingState.ERROR -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
                    contentAlignment = Alignment.Center
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        Text("Failed to load editor")
                        loadingError?.let { Text(it) }
                    }
                }
            }
            EditorLoadingState.READY -> {
                // Editor is ready, no overlay needed
            }
        }
    }
}

/**
 * Demo media upload delegate that resizes images to a maximum dimension of 2000px.
 *
 * Only overrides [processFile] — [uploadFile] returns null so the default uploader is used.
 */
private class DemoMediaUploadDelegate(private val context: android.content.Context) : MediaUploadDelegate {
    override suspend fun processFile(file: File, mimeType: String): File {
        if (!mimeType.startsWith("image/") || mimeType == "image/gif") {
            return file
        }

        val maxDimension = 2000

        val options = android.graphics.BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        android.graphics.BitmapFactory.decodeFile(file.absolutePath, options)

        val width = options.outWidth
        val height = options.outHeight
        if (width <= 0 || height <= 0) return file

        val longestSide = maxOf(width, height)
        if (longestSide <= maxDimension) return file

        // Calculate sample size for memory-efficient decoding
        val sampleSize = Integer.highestOneBit(longestSide / maxDimension)
        val decodeOptions = android.graphics.BitmapFactory.Options().apply {
            inSampleSize = sampleSize
        }
        val sampled = android.graphics.BitmapFactory.decodeFile(file.absolutePath, decodeOptions) ?: return file

        // Scale to exact target dimensions
        val scale = maxDimension.toFloat() / longestSide.toFloat()
        val targetWidth = (width * scale).toInt()
        val targetHeight = (height * scale).toInt()
        val scaled = android.graphics.Bitmap.createScaledBitmap(sampled, targetWidth, targetHeight, true)
        if (scaled !== sampled) sampled.recycle()

        val outputFile = File(file.parent, "resized-${file.name}")
        val format = if (mimeType == "image/png") android.graphics.Bitmap.CompressFormat.PNG
                     else android.graphics.Bitmap.CompressFormat.JPEG

        outputFile.outputStream().use { out ->
            scaled.compress(format, 85, out)
        }
        scaled.recycle()

        Log.d("DemoMediaUploadDelegate", "Resized image from ${width}×${height} to ${targetWidth}×${targetHeight}")
        return outputFile
    }
}
