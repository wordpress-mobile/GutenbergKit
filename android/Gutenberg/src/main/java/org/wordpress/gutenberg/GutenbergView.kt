package org.wordpress.gutenberg

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.inputmethod.InputMethodManager
import android.webkit.ConsoleMessage
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ProgressBar
import android.widget.Toast
import androidx.webkit.WebViewAssetLoader
import androidx.webkit.WebViewAssetLoader.AssetsPathHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONException
import org.json.JSONObject
import org.wordpress.gutenberg.inserter.BlockPickerDialog
import org.wordpress.gutenberg.model.BlockInserterPayload
import org.wordpress.gutenberg.model.EditorConfiguration
import org.wordpress.gutenberg.model.EditorDependencies
import org.wordpress.gutenberg.model.GBKitGlobal
import org.wordpress.gutenberg.services.EditorService
import org.wordpress.gutenberg.views.EditorErrorView
import org.wordpress.gutenberg.views.EditorProgressView
import java.util.Collections
import java.util.Locale

const val DEFAULT_ASSET_DOMAIN = "appassets.androidplatform.net"
const val ASSET_PATH_INDEX = "/assets/index.html"

/**
 * A WebView-based Gutenberg block editor for Android.
 *
 * This view manages its own loading UI internally (progress bar during dependency
 * fetching, spinner during WebView initialization, error state on failure).
 * Consumers do not need to implement loading UI — it is handled automatically.
 *
 * ## Creating a GutenbergView
 *
 * This view must be created programmatically - XML layout inflation is not supported.
 * Use the constructor directly or create it within a Compose `AndroidView`:
 *
 * ```kotlin
 * // In an Activity or Fragment:
 * val editor = GutenbergView(
 *     configuration = EditorConfiguration.builder(...).build(),
 *     dependencies = null,  // or pre-fetched dependencies
 *     coroutineScope = lifecycleScope,
 *     context = this
 * )
 *
 * // In Jetpack Compose:
 * AndroidView(factory = { context ->
 *     GutenbergView(configuration, dependencies, lifecycleScope, context)
 * })
 * ```
 *
 * ## Coroutine Scope Requirements
 *
 * The `coroutineScope` parameter is used for async operations like fetching editor
 * dependencies. The caller owns this scope and is responsible for its lifecycle:
 *
 * - **Use a lifecycle-aware scope** (e.g., `lifecycleScope`, `viewModelScope`)
 *   to automatically cancel operations when the host is destroyed
 * - The view does **not** cancel the scope in `onDetachedFromWindow()`
 * - If using a custom scope, ensure it's cancelled when the editor is no longer needed
 *
 * ## Loading Behavior
 *
 * - If `dependencies` is provided, the editor loads immediately (fast path)
 * - If `dependencies` is null, dependencies are fetched asynchronously before loading
 */
class GutenbergView : FrameLayout {
    private val webView: WebView
    private var isEditorLoaded = false
    private var didFireEditorLoaded = false
    private lateinit var assetLoader: WebViewAssetLoader
    private lateinit var assetDomain: String
    private val configuration: EditorConfiguration
    private lateinit var dependencies: EditorDependencies

    private val handler = Handler(Looper.getMainLooper())
    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    @Volatile private var lastKnownConnectivity: Boolean? = null
    private val availableNetworks = Collections.synchronizedSet(mutableSetOf<Network>())
    var filePathCallback: ValueCallback<Array<Uri?>?>? = null
    val pickImageRequestCode = 1

    var requestInterceptor: GutenbergRequestInterceptor = DefaultGutenbergRequestInterceptor()

    /** Optional delegate for customizing media upload behavior (resize, transcode, custom upload). */
    var mediaUploadDelegate: MediaUploadDelegate? = null
        set(value) {
            if (field === value) return
            field = value
            // Stop any previously running server before starting a new one.
            uploadServer?.stop()
            uploadServer = null
            // (Re)start the upload server so it captures the delegate.
            // This handles the common case where the delegate is set after
            // construction but before the editor finishes loading.
            if (value != null) {
                startUploadServer()
            }
        }

    private var uploadServer: MediaUploadServer? = null
    private val uploadHttpClient: okhttp3.OkHttpClient by lazy {
        // Match EditorHTTPClient's 60s policy. The bare OkHttpClient() default is
        // a 10s read timeout, which routinely fires while WordPress generates
        // image sub-sizes synchronously inside POST /wp/v2/media. Because the
        // attachment row is created before sub-size generation completes, a
        // client-side timeout orphans the attachment server-side and duplicates
        // it on retry.
        okhttp3.OkHttpClient.Builder()
            .callTimeout(UPLOAD_TIMEOUT_SECONDS, java.util.concurrent.TimeUnit.SECONDS)
            .connectTimeout(UPLOAD_TIMEOUT_SECONDS, java.util.concurrent.TimeUnit.SECONDS)
            .readTimeout(UPLOAD_TIMEOUT_SECONDS, java.util.concurrent.TimeUnit.SECONDS)
            .writeTimeout(UPLOAD_TIMEOUT_SECONDS, java.util.concurrent.TimeUnit.SECONDS)
            .build()
    }

    private var onFileChooserRequested: ((Intent, Int) -> Unit)? = null
    private var contentChangeListener: ContentChangeListener? = null
    private var historyChangeListener: HistoryChangeListener? = null
    private var featuredImageChangeListener: FeaturedImageChangeListener? = null
    private var openMediaLibraryListener: OpenMediaLibraryListener? = null
    private var editorDidBecomeAvailableListener: EditorAvailableListener? = null
    private var logJsExceptionListener: LogJsExceptionListener? = null
    private var autocompleterTriggeredListener: AutocompleterTriggeredListener? = null
    private var modalDialogStateListener: ModalDialogStateListener? = null
    private var networkRequestListener: NetworkRequestListener? = null
    private var latestContentProvider: LatestContentProvider? = null
    private var blockInserterDialog: BlockPickerDialog? = null

    /**
     * Stores the contextId from the most recent openMediaLibrary call
     * to pass back to JavaScript when media is selected
     */
    private var currentMediaContextId: String? = null

    private val coroutineScope: CoroutineScope

    // Internal loading overlay views
    private val progressView: EditorProgressView
    private val spinnerView: ProgressBar
    private val errorView: EditorErrorView

    /**
     * Provides access to the internal WebView for tests and advanced use cases.
     */
    val editorWebView: WebView get() = webView

    var textEditorEnabled: Boolean = false
        set(value) {
            field = value
            val mode = if (value) "text" else "visual"
            handler.post {
                webView.evaluateJavascript("editor.switchEditorMode('$mode');", null)
            }
        }

    fun setContentChangeListener(listener: ContentChangeListener) {
        contentChangeListener = listener
    }

    fun setHistoryChangeListener(listener: HistoryChangeListener) {
        historyChangeListener = listener
    }

    fun setFeaturedImageChangeListener(listener: FeaturedImageChangeListener) {
        featuredImageChangeListener = listener
    }

    fun setOpenMediaLibraryListener(listener: OpenMediaLibraryListener) {
        openMediaLibraryListener = listener
    }

    fun setLogJsExceptionListener(listener: LogJsExceptionListener) {
        logJsExceptionListener = listener
    }

    fun setAutocompleterTriggeredListener(listener: AutocompleterTriggeredListener) {
        autocompleterTriggeredListener = listener
    }

    fun setModalDialogStateListener(listener: ModalDialogStateListener) {
        modalDialogStateListener = listener
    }

    fun setNetworkRequestListener(listener: NetworkRequestListener) {
        networkRequestListener = listener
    }

    fun setLatestContentProvider(provider: LatestContentProvider?) {
        latestContentProvider = provider
    }

    fun setOnFileChooserRequestedListener(listener: (Intent, Int) -> Unit) {
        onFileChooserRequested = listener
    }

    fun setEditorDidBecomeAvailable(listener: EditorAvailableListener?) {
        editorDidBecomeAvailableListener = listener
    }

    constructor(context: Context) : this(
        configuration = EditorConfiguration.bundled(),
        dependencies = null,
        coroutineScope = CoroutineScope(Dispatchers.IO),
        context = context
    ) {
        Log.e("GutenbergView", "Using the default constructor for `GutenbergView` – this is probably not what you want.")
    }

    /**
     * Creates a new GutenbergView with the specified configuration.
     *
     * @param configuration The editor configuration specifying site details and capabilities.
     * @param dependencies Pre-fetched editor dependencies, or null to fetch asynchronously.
     *                     Providing dependencies enables instant editor loading.
     * @param coroutineScope The scope for async operations. **Caller owns this scope** -
     *                       use a lifecycle-aware scope like `lifecycleScope` to ensure
     *                       operations are cancelled when the Activity/Fragment is destroyed.
     * @param context The Android context.
     */
    constructor(configuration: EditorConfiguration, dependencies: EditorDependencies?, coroutineScope: CoroutineScope, context: Context) : super(context) {
        this.configuration = configuration
        this.coroutineScope = coroutineScope

        // Initialize the asset loader now that context is available
        assetLoader = WebViewAssetLoader.Builder()
            .addPathHandler("/assets/", AssetsPathHandler(context))
            .build()

        // Create the internal WebView as first child (behind overlays)
        webView = WebView(context).apply {
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
            alpha = 0f
        }
        addView(webView)

        // Create loading overlay views
        progressView = EditorProgressView(context).apply {
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.CENTER)
            loadingText = "Loading Editor..."
            visibility = GONE
        }
        addView(progressView)

        spinnerView = ProgressBar(context).apply {
            layoutParams = LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, Gravity.CENTER)
            isIndeterminate = true
            visibility = GONE
        }
        addView(spinnerView)

        errorView = EditorErrorView(context).apply {
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.CENTER)
            visibility = GONE
        }
        addView(errorView)

        if (dependencies != null) {
            this.dependencies = dependencies

            // FAST PATH: Dependencies were provided - load immediately
            showSpinnerPhase()
            loadEditor(dependencies)
        } else {
            // ASYNC FLOW: No dependencies - fetch them asynchronously
            showProgressPhase()
            prepareAndLoadEditor()
        }
    }

    /**
     * Transitions to the progress bar phase (dependency fetching).
     */
    private fun showProgressPhase() {
        handler.post {
            progressView.visibility = VISIBLE
            spinnerView.visibility = GONE
            errorView.visibility = GONE
            webView.alpha = 0f
        }
    }

    /**
     * Transitions to the spinner phase (WebView initialization).
     */
    private fun showSpinnerPhase() {
        handler.post {
            progressView.animate().alpha(0f).setDuration(200).withEndAction {
                progressView.visibility = GONE
            }.start()
            spinnerView.alpha = 0f
            spinnerView.visibility = VISIBLE
            spinnerView.animate().alpha(1f).setDuration(200).start()
            errorView.visibility = GONE
            webView.alpha = 0f
        }
    }

    /**
     * Transitions to the ready phase (editor visible).
     */
    private fun showReadyPhase() {
        handler.post {
            spinnerView.animate().alpha(0f).setDuration(200).withEndAction {
                spinnerView.visibility = GONE
            }.start()
            progressView.animate().alpha(0f).setDuration(200).withEndAction {
                progressView.visibility = GONE
            }.start()
            errorView.visibility = GONE
            webView.animate().alpha(1f).setDuration(200).start()
        }
    }

    /**
     * Transitions to the error phase (loading failed).
     */
    private fun showErrorPhase(error: Throwable) {
        handler.post {
            progressView.animate().alpha(0f).setDuration(200).withEndAction {
                progressView.visibility = GONE
            }.start()
            spinnerView.animate().alpha(0f).setDuration(200).withEndAction {
                spinnerView.visibility = GONE
            }.start()
            errorView.setError(error)
            errorView.alpha = 0f
            errorView.visibility = VISIBLE
            errorView.animate().alpha(1f).setDuration(200).start()
            webView.alpha = 0f
        }
    }

    @SuppressLint("SetJavaScriptEnabled") // Without JavaScript we have no Gutenberg
    private fun initializeWebView() {
        webView.settings.javaScriptCanOpenWindowsAutomatically = true
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true

        // Set custom user agent
        val defaultUserAgent = webView.settings.userAgentString
        webView.settings.userAgentString = "$defaultUserAgent GutenbergKit/${GutenbergKitVersion.VERSION}"

        webView.addJavascriptInterface(this, "editorDelegate")

        webView.webViewClient = object : WebViewClient() {
            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?
            ) {
                Log.e("GutenbergView", "Received web error: $error")
                super.onReceivedError(view, request, error)
            }

            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                super.onPageStarted(view, url, favicon)
                setGlobalJavaScriptVariables()
            }

            override fun shouldInterceptRequest(
                view: WebView,
                request: WebResourceRequest
            ): WebResourceResponse? {
                if (request.url == null) {
                    return super.shouldInterceptRequest(view, request)
                }

                // Check the cache interceptor first — it handles JS/CSS
                // assets from any allowed host, which may include the asset
                // domain when it matches the site domain.
                if (requestInterceptor.canIntercept(request)) {
                    val response = requestInterceptor.handleRequest(request)
                    if (response != null) return response
                }

                if (request.url.host == assetDomain) {
                    return assetLoader.shouldInterceptRequest(request.url)
                }

                return super.shouldInterceptRequest(view, request)
            }

            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest): Boolean {
                val url = request.url

                // Allow local file URLs
                if (url.scheme == "file") {
                    return false
                }

                // Allow blob URLs (used by block inserter)
                if (url.scheme == "blob") {
                    return false
                }

                // Allow data URLs (used by block inserter)
                if (url.scheme == "data") {
                    return false
                }

                // Allow about:blank URLs
                if (url.scheme == "about") {
                    return false
                }

                // Allow asset URLs (restrict to the asset path prefix so that
                // arbitrary site pages don't load inside the WebView when the
                // asset domain matches the site domain)
                if (url.host == assetDomain && url.path?.startsWith("/assets/") == true) {
                    return false
                }

                // Allow WordPress.com REST API
                if (url.host == "public-api.wordpress.com") {
                    return false
                }

                // Allow WordPress REST API
                if (url.host == configuration.siteApiRoot.removePrefix("https://").removePrefix("http://")) {
                    if (url.path?.contains("/wp-json/") == true || url.query?.contains("rest_route=") == true) {
                        return false
                    }
                }

                // Allow local development server if configured
                if (BuildConfig.GUTENBERG_EDITOR_URL.isNotEmpty()) {
                    val editorUrl = Uri.parse(BuildConfig.GUTENBERG_EDITOR_URL)
                    if (url.host == editorUrl.host) {
                        return false
                    }
                }

                // For all other URLs, open in external browser
                val intent = Intent(Intent.ACTION_VIEW, url)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                view?.context?.startActivity(intent)
                return true
            }
        }

        webView.webChromeClient = object : WebChromeClient() {
            override fun onConsoleMessage(consoleMessage: ConsoleMessage?): Boolean {
                if (consoleMessage != null) {
                    Log.i("GutenbergView", consoleMessage.message())
                } else {
                    Log.i("GutenbergView", "null message")
                }
                return super.onConsoleMessage(consoleMessage)
            }
            override fun onShowFileChooser(
                webView: WebView?,
                newFilePathCallback: ValueCallback<Array<Uri?>?>?,
                fileChooserParams: FileChooserParams?
            ): Boolean {
                // Cancel any existing callback to prevent WebView state corruption
                filePathCallback?.onReceiveValue(null)

                filePathCallback = newFilePathCallback
                val allowMultiple = fileChooserParams?.mode == FileChooserParams.MODE_OPEN_MULTIPLE
                // Only use `acceptTypes` if it is not merely an empty string
                val mimeTypes = fileChooserParams?.acceptTypes?.takeUnless { it.size == 1 && it[0].isEmpty() } ?: arrayOf("*/*")

                // Use ACTION_OPEN_DOCUMENT instead of ACTION_PICK_IMAGES to
                // bypass the Android Photo Picker, which returns proxy URIs
                // that trigger Chromium's ERR_UPLOAD_FILE_CHANGED error.
                // ACTION_OPEN_DOCUMENT routes directly to DocumentsUI, which
                // returns stable content URIs suitable for WebView uploads.
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
                intent.setType(mimeTypes[0])
                intent.putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes)
                intent.addCategory(Intent.CATEGORY_OPENABLE)

                if (allowMultiple) {
                    intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                }

                onFileChooserRequested?.let { callback ->
                    handler.post {
                        callback(intent, pickImageRequestCode)
                    }
                }
                return true
            }
        }
    }

    /**
     * Fetches all required dependencies and then loads the editor.
     *
     * This method is the entry point for the async flow when no dependencies were provided.
     */
    private fun prepareAndLoadEditor() {
        Log.i("GutenbergView", "Fetching dependencies...")

        coroutineScope.launch {
            Log.i("GutenbergView", "In coroutine scope")
            Log.i("GutenbergView", "Fetching dependencies in IO context")
            try {
                val editorService = EditorService.create(
                    context = context,
                    configuration = configuration,
                    coroutineScope = coroutineScope
                )
                Log.i("GutenbergView", "Created editor service")
                val fetchedDependencies = editorService.prepare { progress ->
                    progressView.setProgress(progress)

                    Log.i("GutenbergView", "Progress: $progress")
                }

                Log.i("GutenbergView", "Finished fetching dependencies")

                // Store dependencies and load the editor
                loadEditor(fetchedDependencies)
            } catch (e: Exception) {
                Log.e("GutenbergView", "Failed to load dependencies", e)
                showErrorPhase(e)
            }
        }
    }

    /**
     * Loads the editor with the given dependencies.
     *
     * This is the shared loading path used by both flows after dependencies are available.
     */
    private fun loadEditor(dependencies: EditorDependencies) {
        this.dependencies = dependencies

        // Derive the asset loader domain from the site URL so that the editor
        // document shares the site's origin, making REST API and AJAX requests
        // same-origin and eliminating CORS restrictions.
        assetDomain = Uri.parse(configuration.siteURL).host ?: DEFAULT_ASSET_DOMAIN

        // Set up asset caching
        requestInterceptor = CachedAssetRequestInterceptor(
            dependencies.assetBundle,
            configuration.cachedAssetHosts
        )

        // Build the asset loader. When the site is a local dev server over HTTP,
        // serve assets over HTTP too so that Android WebView doesn't block site
        // resources as mixed content. Only allow this for known local hosts to
        // avoid accidentally downgrading asset traffic for production sites.
        val siteUri = Uri.parse(configuration.siteURL)
        val isLocalHttpSite = siteUri.scheme == "http" && siteUri.host in LOCAL_HOSTS
        assetLoader = WebViewAssetLoader.Builder()
            .setDomain(assetDomain)
            .setHttpAllowed(isLocalHttpSite)
            .addPathHandler("/assets/", AssetsPathHandler(this.context))
            .build()

        // Transition to spinner phase (WebView initialization)
        showSpinnerPhase()

        initializeWebView()

        val scheme = if (isLocalHttpSite) "http" else "https"
        val assetUrl = "$scheme://$assetDomain$ASSET_PATH_INDEX"
        val editorUrl = BuildConfig.GUTENBERG_EDITOR_URL.ifEmpty {
            assetUrl
        }

        WebStorage.getInstance().deleteAllData()
        webView.clearCache(true)
        // All cookies are third-party cookies because the root of this document
        // lives under the configured asset domain (e.g., `https://appassets.androidplatform.net`)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)

        // Erase all local cookies before loading the URL – we don't want to persist
        // anything between uses – otherwise we might send the wrong cookies
        CookieManager.getInstance().removeAllCookies {
            CookieManager.getInstance().flush()
            for (cookie in configuration.cookies) {
                CookieManager.getInstance().setCookie(cookie.key, cookie.value)
            }
            webView.loadUrl(editorUrl)

            Log.i("GutenbergView", "Startup Complete")
        }
    }

    private fun setGlobalJavaScriptVariables() {
        val gbKit = GBKitGlobal.fromConfiguration(
            configuration,
            dependencies,
            nativeUploadPort = uploadServer?.port,
            nativeUploadToken = uploadServer?.token
        )
        val gbKitJson = gbKit.toJsonString()
        val gbKitConfig = """
            window.GBKit = $gbKitJson;
            localStorage.setItem('GBKit', JSON.stringify(window.GBKit));
        """.trimIndent()

        webView.evaluateJavascript(gbKitConfig, null)
    }

    /**
     * Pushes the current upload server's port and token into the already-loaded
     * page.
     *
     * The initial injection is handled by [setGlobalJavaScriptVariables] from
     * `onPageStarted`. This is needed when the server is (re)started *after* the
     * page has loaded — e.g. when [mediaUploadDelegate] is assigned or replaced,
     * which binds a new port and mints a new token. Without this, JS keeps
     * fetching the old (now-dead) port and every upload fails.
     *
     * The `window.GBKit` guard makes this a no-op before the page has loaded, so
     * it is safe to call on the initial start too.
     */
    private fun updateUploadServerJavaScriptVariables() {
        val port = uploadServer?.port ?: return
        val token = uploadServer?.token ?: return
        val js = """
            if (window.GBKit) {
                window.GBKit.nativeUploadPort = $port;
                window.GBKit.nativeUploadToken = ${JSONObject.quote(token)};
                localStorage.setItem('GBKit', JSON.stringify(window.GBKit));
            }
        """.trimIndent()
        webView.evaluateJavascript(js, null)
    }

    private fun startUploadServer() {
        // The default REST-API uploader needs a site root and an auth header, but
        // a cookie-auth host (empty authHeader by design) can still process and
        // upload through a delegate that implements uploadFile. So build the
        // default uploader only when we can, and start the server as long as a
        // delegate can handle uploads — rather than refusing to start and
        // silently forcing every upload down the unprocessed WebView path.
        val canBuildDefaultUploader =
            configuration.siteApiRoot.isNotEmpty() && configuration.authHeader.isNotEmpty()
        if (mediaUploadDelegate == null && !canBuildDefaultUploader) return

        try {
            val defaultUploader = if (canBuildDefaultUploader) {
                DefaultMediaUploader(
                    httpClient = uploadHttpClient,
                    siteApiRoot = configuration.siteApiRoot,
                    authHeader = configuration.authHeader,
                    siteApiNamespace = configuration.siteApiNamespace.toList()
                )
            } else {
                null
            }
            uploadServer = MediaUploadServer(
                uploadDelegate = mediaUploadDelegate,
                defaultUploader = defaultUploader,
                cacheDir = context.cacheDir
            )
            // Re-advertise the (new) port/token to the live page. No-ops before
            // the page has loaded (onPageStarted handles the initial injection);
            // on a delegate-driven restart after load it re-syncs JS onto the new
            // port so uploads keep working.
            updateUploadServerJavaScriptVariables()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to start upload server", e)
        }
    }

    fun clearConfig() {
        val jsCode = """
            delete window.GBKit;
            localStorage.removeItem('GBKit');
        """.trimIndent()

        webView.evaluateJavascript(jsCode, null)
    }

    fun setContent(newContent: String) {
        if (!isEditorLoaded) {
            Log.e("GutenbergView", "You can't change the editor content until it has loaded")
            return
        }
        val encodedContent = newContent.encodeForEditor()
        webView.evaluateJavascript("editor.setContent('$encodedContent');", null)
    }

    fun setTitle(newTitle: String) {
        if (!isEditorLoaded) {
            Log.e("GutenbergView", "You can't change the editor content until it has loaded")
            return
        }
        val encodedTitle = newTitle.encodeForEditor()
        webView.evaluateJavascript("editor.setTitle('$encodedTitle');", null)
    }

    interface TitleAndContentCallback {
        fun onResult(title: CharSequence, content: CharSequence)
    }

    interface ContentChangeListener {
        fun onContentChanged()
    }

    interface HistoryChangeListener {
        fun onHistoryChanged(hasUndo: Boolean, hasRedo: Boolean)
    }

    interface FeaturedImageChangeListener {
        fun onFeaturedImageChanged(mediaID: Long)
    }

    sealed class Value {
        data class Single(val value: Int): Value()
        data class Multiple(val values: IntArray): Value() {
            fun toList(): List<Int> {
                return values.toList()
            }
        }
    }

    data class OpenMediaLibraryConfig(
        val allowedTypes: Array<MediaType>,
        val multiple: Boolean,
        val value: Value?,
        val contextId: String
    )

    interface OpenMediaLibraryListener {
        fun onOpenMediaLibrary(config: OpenMediaLibraryConfig)
    }

    fun interface EditorAvailableListener {
        fun onEditorAvailable(view: GutenbergView?)
    }

    interface LogJsExceptionListener {
        fun onLogJsException(exception: GutenbergJsException)
    }

    interface AutocompleterTriggeredListener {
        fun onAutocompleterTriggered(type: String)
    }

    interface ModalDialogStateListener {
        fun onModalDialogOpened(dialogType: String)
        fun onModalDialogClosed(dialogType: String)
    }

    interface NetworkRequestListener {
        fun onNetworkRequest(request: RecordedNetworkRequest)
    }

    /**
     * Provides the latest persisted content for recovery after WebView refresh.
     *
     * When the WebView reinitializes (e.g., due to OS memory pressure or page refresh),
     * the editor requests the latest content from this provider. The host app should
     * return the most recently persisted title and content from autosave.
     */
    interface LatestContentProvider {
        /**
         * Returns the most recently persisted title and content from autosave.
         * @return LatestContent if available, null if no persisted content exists.
         */
        fun getLatestContent(): LatestContent?
    }

    /**
     * Represents persisted editor content for recovery.
     */
    data class LatestContent(
        val title: String,
        val content: String
    )

    fun getTitleAndContent(originalContent: CharSequence, callback: TitleAndContentCallback, completeComposition: Boolean = false) {
        if (!isEditorLoaded) {
            Log.e("GutenbergView", "You can't change the editor content until it has loaded")
            return
        }
        handler.post {
            webView.evaluateJavascript("editor.getTitleAndContent($completeComposition);") { result ->
                var lastUpdatedTitle: CharSequence? = null
                var lastUpdatedContent: CharSequence? = null
                var changed = false
                try {
                    val jsonObject = JSONObject(result)
                    lastUpdatedTitle = jsonObject.getString("title")
                    lastUpdatedContent = jsonObject.getString("content")
                    changed = jsonObject.getBoolean("changed")
                } catch (e: JSONException) {
                    Log.e("GutenbergView", "Received invalid JSON from editor.getTitleAndContent")
                }

                val title = lastUpdatedTitle ?: ""
                val content = if (changed) {
                    lastUpdatedContent ?: ""
                } else {
                    originalContent
                }
                callback.onResult(title, content)
            }
        }
    }

    fun undo() {
        handler.post {
            webView.evaluateJavascript("editor.undo();", null)
        }
    }

    fun redo() {
        handler.post {
            webView.evaluateJavascript("editor.redo();", null)
        }
    }

    fun dismissTopModal() {
        handler.post {
            webView.evaluateJavascript("editor.dismissTopModal();", null)
        }
    }

    fun appendTextAtCursor(text: String) {
        if (!isEditorLoaded) {
            Log.e("GutenbergView", "You can't append text until the editor has loaded")
            return
        }
        val encodedText = text.encodeForEditor()
        handler.post {
            webView.evaluateJavascript("editor.appendTextAtCursor(decodeURIComponent('$encodedText'));", null)
        }
    }

    @JavascriptInterface
    fun onEditorLoaded() {
        Log.i("GutenbergView", "EditorLoaded received in native code")
        isEditorLoaded = true
        handler.post {
            lastKnownConnectivity?.let { isConnected ->
                if (!isConnected) dispatchConnectivityEvent(false)
            }
            if(!didFireEditorLoaded) {
                editorDidBecomeAvailableListener?.onEditorAvailable(this)
                this.didFireEditorLoaded = true
                showReadyPhase()

                if (configuration.content.isEmpty()) {
                    // Focus the editor content
                    webView.evaluateJavascript("editor.focus();", null)

                    // Request focus on the WebView and show the soft keyboard
                    handler.postDelayed({
                        webView.requestFocus()
                        val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
                        imm?.showSoftInput(webView, InputMethodManager.SHOW_IMPLICIT)
                    }, 100)
                }
            }
        }
    }

    @JavascriptInterface
    fun onEditorContentChanged() {
        contentChangeListener?.onContentChanged()
    }

    @JavascriptInterface
    fun onEditorHistoryChanged(hasUndo: Boolean, hasRedo: Boolean) {
        historyChangeListener?.onHistoryChanged(hasUndo, hasRedo)
    }

    @JavascriptInterface
    fun onEditorFeaturedImageChanged(mediaID: Long) {
        featuredImageChangeListener?.onFeaturedImageChanged(mediaID)
    }

    @JavascriptInterface
    fun onBlocksChanged(isEmpty: Boolean) {
        if(isEmpty) {
            Log.i("GutenbergView", "BlocksChanged (empty)")
        } else {
            Log.i("GutenbergView", "BlocksChanged (not empty)")
        }
    }

    @JavascriptInterface
    fun openMediaLibrary(jsonString: String) {
        try {
            val jsonObj = JSONObject(jsonString)

            // Parse allowedTypes
            val allowedTypes = if (jsonObj.has("allowedTypes")) {
                val allowedTypesArray = jsonObj.getJSONArray("allowedTypes")
                Array(allowedTypesArray.length()) { index ->
                    MediaType.getEnum(allowedTypesArray.getString(index))
                }
            } else {
                emptyArray()
            }

            // Parse multiple
            val multiple = jsonObj.getBoolean("multiple")

            // Parse value
            val value = if (jsonObj.has("value")) {
                if (multiple) {
                    val valueArray = jsonObj.getJSONArray("value")
                    Value.Multiple(IntArray(valueArray.length()) { index ->
                        valueArray.getInt(index)
                    })
                } else {
                    Value.Single(jsonObj.getInt("value"))
                }
            } else {
                null
            }

            // Store contextId to pass back when media is selected
            val contextId = jsonObj.getString("contextId")
            currentMediaContextId = contextId

            val config = OpenMediaLibraryConfig(allowedTypes = allowedTypes, multiple = multiple, value = value, contextId = contextId)
            openMediaLibraryListener?.onOpenMediaLibrary(config)
        } catch (e: JSONException) {
            e.printStackTrace()
        }
    }

    fun setMediaUploadAttachment(media: String) {
        if (!isEditorLoaded) {
            Log.e("GutenbergView", "You can't change the editor content until it has loaded")
            return
        }

        val contextId = currentMediaContextId
        if (contextId == null) {
            Log.e("GutenbergView", "setMediaUploadAttachment called without contextId")
            return
        }

        val escapedContextId = contextId.replace("'", "\\'")
        webView.evaluateJavascript("editor.setMediaUploadAttachment($media, '$escapedContextId');", null)

        currentMediaContextId = null
    }

    private fun insertBlock(blockId: String) {
        if (!isEditorLoaded) return
        handler.post {
            webView.evaluateJavascript(
                "window.blockInserter?.insertBlock(${JSONObject.quote(blockId)});",
                null,
            )
        }
    }

    private fun dismissBlockInserter() {
        if (!isEditorLoaded) return
        handler.post {
            webView.evaluateJavascript("window.blockInserter?.onClose?.();", null)
        }
    }

    @JavascriptInterface
    fun onEditorExceptionLogged(exception: String) {
        val parsedException = GutenbergJsException.fromString(exception)
        logJsExceptionListener?.onLogJsException(parsedException)
    }

    @JavascriptInterface
    fun showBlockInserter(payload: String) {
        val parsed = try {
            BlockInserterPayload.fromJson(payload)
        } catch (e: Exception) {
            Log.e("GutenbergView", "Failed to parse showBlockInserter payload", e)
            handler.post {
                Toast.makeText(
                    context,
                    R.string.gbk_block_inserter_failure,
                    Toast.LENGTH_LONG,
                ).show()
            }
            return
        }

        handler.post { presentBlockInserter(parsed) }
    }

    private fun presentBlockInserter(payload: BlockInserterPayload) {
        blockInserterDialog?.dismiss()
        val dialog = BlockPickerDialog(
            context = context,
            payload = payload,
            showMediaStrip = configuration.enableInserterMediaStrip,
            onBlockSelected = { block -> insertBlock(block.id) },
        )
        dialog.setOnDismissListener {
            if (blockInserterDialog === dialog) {
                blockInserterDialog = null
            }
            dismissBlockInserter()
        }
        blockInserterDialog = dialog
        dialog.show()
    }

    @JavascriptInterface
    fun onAutocompleterTriggered(type: String) {
        handler.post {
            autocompleterTriggeredListener?.onAutocompleterTriggered(type)
        }
    }

    @JavascriptInterface
    fun onModalDialogOpened(dialogType: String) {
        handler.post {
            modalDialogStateListener?.onModalDialogOpened(dialogType)
        }
    }

    @JavascriptInterface
    fun onModalDialogClosed(dialogType: String) {
        handler.post {
            modalDialogStateListener?.onModalDialogClosed(dialogType)
        }
    }

    @JavascriptInterface
    fun onNetworkRequest(requestData: String) {
        handler.post {
            try {
                val json = JSONObject(requestData)
                val request = RecordedNetworkRequest.fromJson(json)
                networkRequestListener?.onNetworkRequest(request)
            } catch (e: Exception) {
                Log.e("GutenbergView", "Error parsing network request: ${e.message}")
            }
        }
    }

    /**
     * Called by JavaScript to request the latest persisted content.
     *
     * This method is invoked during editor initialization to recover content
     * after WebView refresh. The host app provides content via [LatestContentProvider].
     *
     * @return JSON string with title and content fields, or null if unavailable.
     */
    @JavascriptInterface
    fun requestLatestContent(): String? {
        val content = latestContentProvider?.getLatestContent() ?: return null
        return try {
            JSONObject().apply {
                put("title", content.title)
                put("content", content.content)
            }.toString()
        } catch (e: JSONException) {
            Log.e("GutenbergView", "Failed to serialize latest content", e)
            null
        }
    }

    fun resetFilePathCallback() {
        filePathCallback = null
    }

    /**
     * Extracts file URIs from a file picker Intent result.
     *
     * Handles both single file selection (Intent.data) and multiple file selection
     * (Intent.clipData). This is a utility method for processing ActivityResult data
     * from file picker requests.
     *
     * @param data Intent data from file picker result
     * @return Array of selected URIs, or null if no files were selected
     */
    fun extractUrisFromIntent(data: Intent?): Array<Uri?>? {
        return if (data != null) {
            if (data.clipData != null) {
                val clipData = data.clipData!!
                Array(clipData.itemCount) { i -> clipData.getItemAt(i).uri }
            } else if (data.data != null) {
                arrayOf(data.data)
            } else null
        } else null
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        startNetworkMonitoring()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        stopNetworkMonitoring()
        uploadServer?.stop()
        uploadServer = null
        clearConfig()
        // Cancel in-flight animations to prevent withEndAction callbacks from
        // firing on detached views.
        progressView.animate().cancel()
        spinnerView.animate().cancel()
        errorView.animate().cancel()
        webView.animate().cancel()
        webView.stopLoading()
        contentChangeListener = null
        historyChangeListener = null
        featuredImageChangeListener = null
        openMediaLibraryListener = null
        logJsExceptionListener = null
        editorDidBecomeAvailableListener = null
        filePathCallback = null
        onFileChooserRequested = null
        autocompleterTriggeredListener = null
        modalDialogStateListener = null
        networkRequestListener = null
        requestInterceptor = DefaultGutenbergRequestInterceptor()
        latestContentProvider = null
        blockInserterDialog?.dismiss()
        blockInserterDialog = null
        handler.removeCallbacksAndMessages(null)
        webView.destroy()
    }

    // Network Monitoring

    private fun startNetworkMonitoring() {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
        connectivityManager = cm
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                availableNetworks.add(network)
                handleConnectivityChange(true)
            }
            override fun onLost(network: Network) {
                availableNetworks.remove(network)
                handleConnectivityChange(availableNetworks.isNotEmpty())
            }
        }
        networkCallback = callback
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        cm.registerNetworkCallback(request, callback)
    }

    private fun stopNetworkMonitoring() {
        try {
            connectivityManager?.let { cm -> networkCallback?.let { cb -> cm.unregisterNetworkCallback(cb) } }
        } catch (e: IllegalArgumentException) {
            Log.w("GutenbergView", "NetworkCallback was not registered: ${e.message}")
        }
        connectivityManager = null
        networkCallback = null
        availableNetworks.clear()
    }

    private fun handleConnectivityChange(isConnected: Boolean) {
        if (lastKnownConnectivity == isConnected) return
        lastKnownConnectivity = isConnected
        if (!isEditorLoaded) return
        handler.post { dispatchConnectivityEvent(isConnected) }
    }

    private fun dispatchConnectivityEvent(isConnected: Boolean) {
        val eventName = if (isConnected) "online" else "offline"
        webView.evaluateJavascript("window.dispatchEvent(new Event('$eventName'));", null)
    }

    companion object {
        private const val TAG = "GutenbergView"

        /** Hosts that are safe to serve assets over HTTP (local development only). */
        private val LOCAL_HOSTS = setOf("localhost", "127.0.0.1", "10.0.2.2")

        private const val ASSET_LOADING_TIMEOUT_MS = 5000L

        /** Timeout for media uploads, matching [EditorHTTPClient]'s default policy. */
        private const val UPLOAD_TIMEOUT_SECONDS = 60L

        // Warmup state management
        private var warmupHandler: Handler? = null
        private var warmupRunnable: Runnable? = null
        private var warmupWebView: GutenbergView? = null

        /**
         * Clean up warmup resources.
         */
        private fun cleanupWarmup() {
            warmupWebView?.let { view ->
                view.webView.stopLoading()
                view.clearConfig()
                view.webView.destroy()
            }
            warmupWebView = null
            warmupHandler = null
            warmupRunnable = null
        }
    }
}

data class Media(
    val id: Int,
    val url: String,
    val type: String,
    val caption: String = "",
    val title: String = "",
    val alt: String = "",
    val metadata: Bundle = Bundle()
) {
    companion object {
        private fun convertToType(mimeType: String?): String {
            val isMediaType = { mediaType: MediaType ->
                mimeType?.startsWith(mediaType.name.lowercase(Locale.ROOT)) == true
            }
            val type = when {
                        isMediaType(MediaType.IMAGE) -> MediaType.IMAGE
                        isMediaType(MediaType.VIDEO) -> MediaType.VIDEO
                        else -> MediaType.OTHER
                    }.name.lowercase(Locale.ROOT)
            return type
        }

        @JvmStatic
        fun createMediaUsingMimeType(
            id: Int,
            url: String,
            mimeType: String?,
            caption: String?,
            title: String?,
            alt: String?,
        ): Media {
            val type = convertToType(mimeType)
            return Media(id, url, type, caption ?: "", title ?: "", alt ?: "")
        }
        @JvmStatic
        fun createMediaUsingMimeType(
            id: Int,
            url: String,
            mimeType: String?,
            caption: String?,
            title: String?,
            alt: String?,
            metadata: Bundle = Bundle()
        ): Media {
            val type = convertToType(mimeType)
            return Media(id, url, type, caption ?: "", title ?: "", alt ?: "", metadata)
        }
    }
}

enum class MediaType(var label: String) {
    IMAGE("image"),
    VIDEO("video"),
    MEDIA("media"),
    AUDIO("audio"),
    ANY("any"),
    OTHER("other");

    companion object {
        fun getEnum(value: String): MediaType {
            for (mediaType in entries) {
                if (mediaType.label == value) {
                    return mediaType
                }
            }

            return OTHER
        }
    }
}
