package com.example.gutenbergkit

import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.ViewGroup
import android.webkit.WebView
import android.widget.Toast
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
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.lifecycleScope
import com.example.gutenbergkit.ui.theme.AppTheme
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import org.wordpress.gutenberg.model.EditorConfiguration
import org.wordpress.gutenberg.GutenbergView
import org.wordpress.gutenberg.RecordedNetworkRequest
import org.wordpress.gutenberg.model.EditorDependencies
import org.wordpress.gutenberg.model.EditorDependenciesSerializer
import rs.wordpress.api.kotlin.WpRequestResult
import uniffi.wp_api.PostEndpointType
import uniffi.wp_api.PostUpdateParams
import kotlin.coroutines.resume

class EditorActivity : ComponentActivity() {

    companion object {
        const val EXTRA_DEPENDENCIES_PATH = "dependencies_path"
        const val EXTRA_ACCOUNT_ID = "account_id"
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
            val uris = gutenbergView?.extractUrisFromIntent(result.data)
            gutenbergView?.filePathCallback?.onReceiveValue(uris)
            gutenbergView?.resetFilePathCallback()
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

        // The dependencies blob is on disk; deserialize it off the main thread
        // and feed the editor once it's ready.
        val dependenciesLoad = loadDependenciesFromIntent()

        // Optional account ID for REST API persistence (set when launched from PostsListActivity)
        val accountId = intent.getLongExtra(EXTRA_ACCOUNT_ID, -1L).takeIf { it >= 0 }?.toULong()

        setContent {
            AppTheme {
                when (val load = dependenciesLoad.value) {
                    is DependenciesLoad.Loading -> DependenciesLoadingScreen()
                    is DependenciesLoad.Failed -> DependenciesErrorScreen(
                        message = load.message,
                        onClose = { finish() }
                    )
                    is DependenciesLoad.Ready -> EditorScreen(
                        configuration = configuration,
                        dependencies = load.dependencies,
                        accountId = accountId,
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
    }

    private sealed interface DependenciesLoad {
        data object Loading : DependenciesLoad
        data class Failed(val message: String) : DependenciesLoad
        data class Ready(val dependencies: EditorDependencies?) : DependenciesLoad
    }

    /**
     * Reads [EditorDependencies] from the intent's [EXTRA_DEPENDENCIES_PATH]
     * off the main thread. Returns a state holder that flips from
     * [DependenciesLoad.Loading] to [DependenciesLoad.Ready] or
     * [DependenciesLoad.Failed]. When no path was provided, starts in
     * [DependenciesLoad.Ready] with null dependencies (the editor will load
     * from the network).
     */
    private fun loadDependenciesFromIntent(): MutableState<DependenciesLoad> {
        val path = intent.getStringExtra(EXTRA_DEPENDENCIES_PATH)
        val state = mutableStateOf<DependenciesLoad>(
            if (path == null) DependenciesLoad.Ready(null) else DependenciesLoad.Loading
        )
        if (path != null) {
            lifecycleScope.launch {
                val deps = withContext(Dispatchers.IO) {
                    EditorDependenciesSerializer.readFromDisk(path)
                }
                state.value = if (deps != null) {
                    DependenciesLoad.Ready(deps)
                } else {
                    DependenciesLoad.Failed("The editor data file was missing or could not be read.")
                }
            }
        }
        return state
    }

    private fun setupFileChooserListener(view: GutenbergView) {
        view.setOnFileChooserRequestedListener { intent, _ ->
            filePickerLauncher.launch(intent)
        }
    }
}

@Composable
private fun DependenciesLoadingScreen() {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        CircularProgressIndicator()
    }
}

@Composable
private fun DependenciesErrorScreen(message: String, onClose: () -> Unit) {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
            modifier = Modifier.padding(24.dp)
        ) {
            Text("Couldn't load editor data")
            Text(message)
            TextButton(onClick = onClose) { Text("Close") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditorScreen(
    configuration: EditorConfiguration,
    dependencies: EditorDependencies? = null,
    accountId: ULong? = null,
    coroutineScope: CoroutineScope,
    onClose: () -> Unit,
    onGutenbergViewCreated: (GutenbergView) -> Unit = {}
) {
    var showMenu by remember { mutableStateOf(false) }
    var isModalDialogOpen by remember { mutableStateOf(false) }
    var hasUndoState by remember { mutableStateOf(false) }
    var hasRedoState by remember { mutableStateOf(false) }
    var isCodeEditorEnabled by remember { mutableStateOf(false) }
    var isSaving by remember { mutableStateOf(false) }
    var gutenbergViewRef by remember { mutableStateOf<GutenbergView?>(null) }
    val saveScope = rememberCoroutineScope()
    val context = LocalContext.current

    val canSave = !isSaving && accountId != null && configuration.postId != null

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
                    TextButton(
                        onClick = {
                            val view = gutenbergViewRef ?: return@TextButton
                            val postId = configuration.postId
                            if (accountId == null || postId == null) return@TextButton
                            isSaving = true
                            saveScope.launch {
                                try {
                                    val errorMessage = persistPost(
                                        context = context,
                                        view = view,
                                        configuration = configuration,
                                        accountId = accountId,
                                        postId = postId
                                    )
                                    if (errorMessage != null) {
                                        Toast.makeText(context, errorMessage, Toast.LENGTH_LONG).show()
                                    }
                                } finally {
                                    isSaving = false
                                }
                            }
                        },
                        enabled = canSave && !isModalDialogOpen
                    ) {
                        Text(stringResource(R.string.save))
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
                                text = { Text(stringResource(if (isCodeEditorEnabled) R.string.visual_editor else R.string.code_editor)) },
                                onClick = {
                                    isCodeEditorEnabled = !isCodeEditorEnabled
                                    gutenbergViewRef?.textEditorEnabled = isCodeEditorEnabled
                                    showMenu = false
                                }
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
                            Log.d("EditorActivity", "Network Request: ${request.method} ${request.url}")
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
                    setAutocompleterTriggeredListener(object : GutenbergView.AutocompleterTriggeredListener {
                        override fun onAutocompleterTriggered(type: String) {
                            val suggestions = when (type) {
                                "at-symbol" -> arrayOf("alice", "bob", "charlie")
                                "plus-symbol" -> arrayOf("photoblog", "traveldiaries", "dailydev")
                                else -> return
                            }
                            AlertDialog.Builder(context)
                                .setTitle("Select a suggestion")
                                .setItems(suggestions) { _, which ->
                                    appendTextAtCursor(suggestions[which] + " ")
                                }
                                .setNegativeButton("Cancel", null)
                                .show()
                        }
                    })
                    // Demo app has no persistence layer, so return null.
                    // In a real app, return the persisted title and content from autosave.
                    setLatestContentProvider(object : GutenbergView.LatestContentProvider {
                        override fun getLatestContent(): GutenbergView.LatestContent? {
                            return null
                        }
                    })
                    onGutenbergViewCreated(this)
                }
            },
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        )
    }
}

/**
 * Reads the latest title/content from the editor and PUTs it to the WordPress REST API.
 */
private suspend fun persistPost(
    context: Context,
    view: GutenbergView,
    configuration: EditorConfiguration,
    accountId: ULong,
    postId: UInt
): String? {
    return try {
        val titleAndContent = suspendCancellableCoroutine<Pair<CharSequence, CharSequence>> { cont ->
            view.getTitleAndContent(
                originalContent = configuration.content,
                callback = object : GutenbergView.TitleAndContentCallback {
                    override fun onResult(title: CharSequence, content: CharSequence) {
                        if (cont.isActive) cont.resume(title to content)
                    }
                }
            )
        }

        val app = context.applicationContext as GutenbergKitApplication
        val account = app.withAccountRepository { repo ->
            repo.all().firstOrNull { it.id() == accountId }
        } ?: error("Account not found")
        val client = app.createApiClient(account)

        val endpointType = when (configuration.postType.postType) {
            "page" -> PostEndpointType.Pages
            "post" -> PostEndpointType.Posts
            else -> PostEndpointType.Custom(configuration.postType.postType)
        }

        val params = PostUpdateParams(
            title = titleAndContent.first.toString(),
            content = titleAndContent.second.toString(),
            meta = null
        )

        val result = client.request { builder ->
            builder.posts().update(
                postEndpointType = endpointType,
                postId = postId.toLong(),
                params = params
            )
        }

        when (result) {
            is WpRequestResult.Success -> {
                Log.i("EditorActivity", "Post $postId persisted via REST API")
                null
            }
            else -> {
                Log.e("EditorActivity", "Failed to persist post $postId: $result")
                context.getString(R.string.save_failed_generic)
            }
        }
    } catch (e: Exception) {
        Log.e("EditorActivity", "Failed to persist post $postId", e)
        context.getString(R.string.save_failed_with_reason, e.message ?: "unknown error")
    }
}
