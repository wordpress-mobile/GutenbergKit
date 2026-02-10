package org.wordpress.gutenberg

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
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
import androidx.webkit.WebViewAssetLoader
import androidx.webkit.WebViewAssetLoader.AssetsPathHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONException
import org.json.JSONObject
import org.wordpress.gutenberg.model.EditorConfiguration
import org.wordpress.gutenberg.model.EditorDependencies
import org.wordpress.gutenberg.model.GBKitGlobal
import org.wordpress.gutenberg.services.EditorService
import org.wordpress.gutenberg.views.EditorErrorView
import org.wordpress.gutenberg.views.EditorProgressView
import java.io.ByteArrayInputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale

const val ASSET_URL = "https://appassets.androidplatform.net/assets/index.html"

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
    private val configuration: EditorConfiguration
    private lateinit var dependencies: EditorDependencies

    private val handler = Handler(Looper.getMainLooper())
    var filePathCallback: ValueCallback<Array<Uri?>?>? = null
    val pickImageRequestCode = 1

    var requestInterceptor: GutenbergRequestInterceptor = DefaultGutenbergRequestInterceptor()

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
     * Internal loading states for the editor.
     */
    private enum class LoadingState {
        /** Dependencies are being loaded from the network */
        PROGRESS,
        /** Dependencies loaded, waiting for WebView to initialize */
        SPINNER,
        /** Editor is fully ready */
        READY,
        /** Loading failed with an error */
        ERROR
    }

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
            Log.d(TAG, "Constructor: dependencies provided – using fast path")
            showSpinnerPhase()
            loadEditor(dependencies)
        } else {
            // ASYNC FLOW: No dependencies - fetch them asynchronously
            Log.d(TAG, "Constructor: no dependencies provided – using async path")
            showProgressPhase()
            prepareAndLoadEditor()
        }
    }

    /**
     * Transitions to the progress bar phase (dependency fetching).
     */
    private fun showProgressPhase() {
        Log.d(TAG, "Phase transition -> PROGRESS (fetching dependencies)")
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
        Log.d(TAG, "Phase transition -> SPINNER (initializing WebView)")
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
        Log.d(TAG, "Phase transition -> READY (editor visible)")
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
        Log.d(TAG, "Phase transition -> ERROR: ${error.message}")
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
        Log.d(TAG, "initializeWebView: configuring WebView settings")
        webView.settings.javaScriptCanOpenWindowsAutomatically = true
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true

        // Set custom user agent
        val defaultUserAgent = webView.settings.userAgentString
        webView.settings.userAgentString = "$defaultUserAgent GutenbergKit/${GutenbergKitVersion.VERSION}"
        Log.d(TAG, "initializeWebView: user agent set to ${webView.settings.userAgentString}")

        Log.d(TAG, "initializeWebView: registering JavaScript interface 'editorDelegate'")
        webView.addJavascriptInterface(this, "editorDelegate")

        webView.webViewClient = object : WebViewClient() {
            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?
            ) {
                Log.e(TAG, "onReceivedError: url=${request?.url}" +
                    " isMainFrame=${request?.isForMainFrame} error=$error")
                super.onReceivedError(view, request, error)
            }

            override fun onReceivedHttpError(
                view: WebView?,
                request: WebResourceRequest?,
                errorResponse: WebResourceResponse?
            ) {
                Log.e(TAG, "onReceivedHttpError: url=${request?.url}" +
                    " status=${errorResponse?.statusCode} reason=${errorResponse?.reasonPhrase}")
                super.onReceivedHttpError(view, request, errorResponse)
            }

            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                Log.d(TAG, "onPageStarted: url=$url")
                super.onPageStarted(view, url, favicon)
                setGlobalJavaScriptVariables()
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                Log.d(TAG, "onPageFinished: url=$url")
                super.onPageFinished(view, url)
            }

            override fun shouldInterceptRequest(
                view: WebView,
                request: WebResourceRequest
            ): WebResourceResponse? {
                if (request.url == null) {
                    Log.d(TAG, "shouldInterceptRequest: null URL – passing to super")
                    return super.shouldInterceptRequest(view, request)
                }

                // Serve bundled assets from the app package
                if (request.url.host?.contains("appassets.androidplatform.net") == true) {
                    Log.d(TAG, "shouldInterceptRequest: asset URL – delegating to assetLoader: ${request.url}")
                    return assetLoader.shouldInterceptRequest(request.url)
                }

                // Try serving from the asset cache
                if (requestInterceptor.canIntercept(request)) {
                    val cached = requestInterceptor.handleRequest(request)
                    if (cached != null) {
                        Log.d(TAG, "shouldInterceptRequest: served from cache: ${request.url}")
                        return cached
                    }
                    // Cache miss – fall through to proxy below
                }

                // Proxy all other requests natively so they bypass CORS
                // (the editor page is served from appassets.androidplatform.net,
                // making every API call cross-origin). This doesn't use `EditorHTTPClient` because
                // it's not actually a native call – the editor is building the request so we don't
                // want to modify it in any way.
                Log.d(TAG, "shouldInterceptRequest: proxying request: ${request.url}")
                return proxyRequest(request)
            }

            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest): Boolean {
                val url = request.url

                // Allow local file URLs
                if (url.scheme == "file") {
                    Log.d(TAG, "shouldOverrideUrlLoading: allowing file:// URL")
                    return false
                }

                // Allow blob URLs (used by block inserter)
                if (url.scheme == "blob") {
                    Log.d(TAG, "shouldOverrideUrlLoading: allowing blob:// URL")
                    return false
                }

                // Allow data URLs (used by block inserter)
                if (url.scheme == "data") {
                    Log.d(TAG, "shouldOverrideUrlLoading: allowing data: URL")
                    return false
                }

                // Allow about:blank URLs
                if (url.scheme == "about") {
                    Log.d(TAG, "shouldOverrideUrlLoading: allowing about: URL")
                    return false
                }

                // Allow asset URLs
                if (url.host == Uri.parse(ASSET_URL).host) {
                    Log.d(TAG, "shouldOverrideUrlLoading: allowing asset URL")
                    return false
                }

                // Allow WordPress.com REST API
                if (url.host == "public-api.wordpress.com") {
                    Log.d(TAG, "shouldOverrideUrlLoading: allowing public-api.wordpress.com")
                    return false
                }

                // Allow WordPress REST API
                if (url.host == configuration.siteApiRoot.removePrefix("https://").removePrefix("http://")) {
                    if (url.path?.contains("/wp-json/") == true || url.query?.contains("rest_route=") == true) {
                        Log.d(TAG, "shouldOverrideUrlLoading: allowing site API request – $url")
                        return false
                    }
                }

                // Allow local development server if configured
                if (BuildConfig.GUTENBERG_EDITOR_URL.isNotEmpty()) {
                    val editorUrl = Uri.parse(BuildConfig.GUTENBERG_EDITOR_URL)
                    if (url.host == editorUrl.host) {
                        Log.d(TAG, "shouldOverrideUrlLoading: allowing dev server URL")
                        return false
                    }
                }

                // For all other URLs, open in external browser
                Log.d(TAG, "shouldOverrideUrlLoading: opening in external browser – $url")
                val intent = Intent(Intent.ACTION_VIEW, url)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                view?.context?.startActivity(intent)
                return true
            }
        }

        webView.webChromeClient = object : WebChromeClient() {
            override fun onConsoleMessage(consoleMessage: ConsoleMessage?): Boolean {
                if (consoleMessage != null) {
                    Log.i(TAG, consoleMessage.message())
                } else {
                    Log.i(TAG, "null message")
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

                val intent = Intent(Intent.ACTION_GET_CONTENT)
                intent.setType(mimeTypes[0])
                intent.putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes)
                intent.addCategory(Intent.CATEGORY_OPENABLE)

                if (allowMultiple) {
                    intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                }

                onFileChooserRequested?.let { callback ->
                    handler.post {
                        callback(Intent.createChooser(intent, "Select Files"), pickImageRequestCode)
                    }
                }
                return true
            }
        }
    }

    /**
     * Proxies an HTTP request natively to bypass CORS restrictions.
     *
     * The editor page is served from `https://appassets.androidplatform.net`, so every
     * `fetch()` call the JavaScript makes to the WordPress REST API is cross-origin.
     * Rather than requiring the server to whitelist the synthetic WebView origin, this
     * method intercepts the request in [shouldInterceptRequest] and performs it with
     * [HttpURLConnection], which is not subject to CORS.
     */
    private fun proxyRequest(request: WebResourceRequest): WebResourceResponse? {
        // Handle CORS preflight – return permissive headers immediately
        // without forwarding the OPTIONS request to the server.
        if (request.method.equals("OPTIONS", ignoreCase = true)) {
            Log.d(TAG, "proxyRequest: CORS preflight for ${request.url}")
            val requestedHeaders = request.requestHeaders?.get("Access-Control-Request-Headers")
            return createCorsPreflightResponse(requestedHeaders)
        }

        try {
            val connection = URL(request.url.toString()).openConnection() as HttpURLConnection
            connection.requestMethod = request.method ?: "GET"
            connection.connectTimeout = 30_000
            connection.readTimeout = 30_000

            // Forward headers set by the JavaScript fetch() call (e.g. Authorization)
            request.requestHeaders?.forEach { (key, value) ->
                connection.setRequestProperty(key, value)
            }

            // Include cookies from CookieManager (set during loadEditor)
            val cookies = CookieManager.getInstance().getCookie(request.url.toString())
            if (cookies != null) {
                connection.setRequestProperty("Cookie", cookies)
            }

            val statusCode = connection.responseCode
            val reasonPhrase = connection.responseMessage ?: "OK"

            // Parse Content-Type for the MIME type and charset
            val contentTypeHeader = connection.contentType ?: "application/octet-stream"
            val mimeType = contentTypeHeader.split(";").first().trim()
            val charset = contentTypeHeader
                .split(";")
                .map { it.trim() }
                .find { it.startsWith("charset=", ignoreCase = true) }
                ?.substringAfter("=")
                ?.trim()
                ?: "UTF-8"

            val responseHeaders = mutableMapOf<String, String>()
            connection.headerFields?.forEach { (key, values) ->
                if (key != null && values.isNotEmpty()) {
                    responseHeaders[key] = values.last()
                }
            }

            // Add CORS headers so the WebView allows the JavaScript to read the response
            addCorsHeaders(responseHeaders)

            val inputStream = if (statusCode >= 400) {
                connection.errorStream ?: ByteArrayInputStream(ByteArray(0))
            } else {
                connection.inputStream
            }

            Log.d(TAG, "proxyRequest: $statusCode ${request.method ?: "GET"} ${request.url}")
            return WebResourceResponse(mimeType, charset, statusCode, reasonPhrase, responseHeaders, inputStream)
        } catch (e: Exception) {
            Log.e(TAG, "proxyRequest: failed to proxy ${request.url}", e)
            return null
        }
    }

    /**
     * Returns a synthetic 204 response for CORS preflight (OPTIONS) requests,
     * echoing back whatever headers the JavaScript intends to send.
     */
    private fun createCorsPreflightResponse(requestedHeaders: String?): WebResourceResponse {
        val headers = mutableMapOf<String, String>()
        addCorsHeaders(headers)
        headers["Access-Control-Max-Age"] = "86400"
        if (!requestedHeaders.isNullOrEmpty()) {
            headers["Access-Control-Allow-Headers"] = requestedHeaders
        }

        return WebResourceResponse(
            "text/plain", "UTF-8", 204, "No Content",
            headers, ByteArrayInputStream(ByteArray(0))
        )
    }

    private fun addCorsHeaders(headers: MutableMap<String, String>) {
        val origin = if (BuildConfig.GUTENBERG_EDITOR_URL.isNotEmpty()) {
            val uri = Uri.parse(BuildConfig.GUTENBERG_EDITOR_URL)
            "${uri.scheme}://${uri.host}${if (uri.port != -1) ":${uri.port}" else ""}"
        } else {
            "https://appassets.androidplatform.net"
        }
        headers["Access-Control-Allow-Origin"] = origin
        headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, PATCH, OPTIONS, HEAD"
        headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type, Accept, X-WP-Nonce"
        headers["Access-Control-Allow-Credentials"] = "true"
    }

    /**
     * Fetches all required dependencies and then loads the editor.
     *
     * This method is the entry point for the async flow when no dependencies were provided.
     */
    private fun prepareAndLoadEditor() {
        val prepareStartTime = System.currentTimeMillis()
        Log.d(TAG, "prepareAndLoadEditor: starting async dependency fetch")

        coroutineScope.launch {
            try {
                Log.d(TAG, "prepareAndLoadEditor: creating EditorService")
                val editorService = EditorService.create(
                    context = context,
                    configuration = configuration,
                    coroutineScope = coroutineScope
                )
                Log.d(TAG, "prepareAndLoadEditor: EditorService created")

                Log.d(TAG, "prepareAndLoadEditor: calling EditorService.prepare()")
                val fetchedDependencies = editorService.prepare { progress ->
                    progressView.setProgress(progress)
                    Log.d(TAG, "prepareAndLoadEditor: progress ${progress.completed}/${progress.total}")
                }

                val elapsed = System.currentTimeMillis() - prepareStartTime
                Log.d(TAG, "prepareAndLoadEditor: dependencies fetched in ${elapsed}ms")

                loadEditor(fetchedDependencies)
            } catch (e: Exception) {
                val elapsed = System.currentTimeMillis() - prepareStartTime
                Log.e(TAG, "prepareAndLoadEditor: failed after ${elapsed}ms", e)
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
        val loadStartTime = System.currentTimeMillis()
        Log.d(TAG, "loadEditor: starting")

        this.dependencies = dependencies

        // Set up asset caching
        Log.d(TAG, "loadEditor: configuring CachedAssetRequestInterceptor" +
            " (cachedAssetHosts=${configuration.cachedAssetHosts})")
        requestInterceptor = CachedAssetRequestInterceptor(
            dependencies.assetBundle,
            configuration.cachedAssetHosts
        )

        // Transition to spinner phase (WebView initialization)
        showSpinnerPhase()

        Log.d(TAG, "loadEditor: initializing WebView")
        initializeWebView()
        Log.d(TAG, "loadEditor: WebView initialized")

        val editorUrl = BuildConfig.GUTENBERG_EDITOR_URL.ifEmpty {
            ASSET_URL
        }
        Log.d(TAG, "loadEditor: editor URL = $editorUrl")

        Log.d(TAG, "loadEditor: clearing WebStorage and cache")
        WebStorage.getInstance().deleteAllData()
        webView.clearCache(true)

        // All cookies are third-party cookies because the root of this document
        // lives under `https://appassets.androidplatform.net`
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)

        // Erase all local cookies before loading the URL – we don't want to persist
        // anything between uses – otherwise we might send the wrong cookies
        Log.d(TAG, "loadEditor: clearing cookies and setting ${configuration.cookies.size}" +
            " cookie(s) from configuration")
        CookieManager.getInstance().removeAllCookies {
            CookieManager.getInstance().flush()
            for (cookie in configuration.cookies) {
                CookieManager.getInstance().setCookie(cookie.key, cookie.value)
            }

            val elapsed = System.currentTimeMillis() - loadStartTime
            Log.d(TAG, "loadEditor: loading URL (setup took ${elapsed}ms)")
            webView.loadUrl(editorUrl)
        }
    }

    private fun setGlobalJavaScriptVariables() {
        Log.d(TAG, "setGlobalJavaScriptVariables: injecting GBKit configuration into WebView")
        val gbKit = GBKitGlobal.fromConfiguration(configuration, dependencies)
        val gbKitJson = gbKit.toJsonString()
        val gbKitConfig = """
            window.GBKit = $gbKitJson;
            localStorage.setItem('GBKit', JSON.stringify(window.GBKit));
        """.trimIndent()

        webView.evaluateJavascript(gbKitConfig, null)
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
            Log.e(TAG, "You can't change the editor content until it has loaded")
            return
        }
        val encodedContent = newContent.encodeForEditor()
        webView.evaluateJavascript("editor.setContent('$encodedContent');", null)
    }

    fun setTitle(newTitle: String) {
        if (!isEditorLoaded) {
            Log.e(TAG, "You can't change the editor content until it has loaded")
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
            Log.e(TAG, "You can't change the editor content until it has loaded")
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
                    Log.e(TAG, "Received invalid JSON from editor.getTitleAndContent")
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
            Log.e(TAG, "You can't append text until the editor has loaded")
            return
        }
        val encodedText = text.encodeForEditor()
        handler.post {
            webView.evaluateJavascript("editor.appendTextAtCursor(decodeURIComponent('$encodedText'));", null)
        }
    }

    @JavascriptInterface
    fun onEditorLoaded() {
        Log.d(TAG, "onEditorLoaded: received from JavaScript (didFireEditorLoaded=$didFireEditorLoaded)")
        isEditorLoaded = true
        handler.post {
            if(!didFireEditorLoaded) {
                Log.d(TAG, "onEditorLoaded: notifying EditorAvailableListener and transitioning to ready")
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
            Log.i(TAG, "BlocksChanged (empty)")
        } else {
            Log.i(TAG, "BlocksChanged (not empty)")
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
            Log.e(TAG, "You can't change the editor content until it has loaded")
            return
        }

        val contextId = currentMediaContextId
        if (contextId == null) {
            Log.e(TAG, "setMediaUploadAttachment called without contextId")
            return
        }

        val escapedContextId = contextId.replace("'", "\\'")
        webView.evaluateJavascript("editor.setMediaUploadAttachment($media, '$escapedContextId');", null)

        currentMediaContextId = null
    }

    @JavascriptInterface
    fun onEditorExceptionLogged(exception: String) {
        val parsedException = GutenbergJsException.fromString(exception)
        logJsExceptionListener?.onLogJsException(parsedException)
    }

    @JavascriptInterface
    fun showBlockPicker() {
        Log.i(TAG, "BlockPickerShouldShow")
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
                Log.e(TAG, "Error parsing network request: ${e.message}")
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
            Log.e(TAG, "Failed to serialize latest content", e)
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

    /**
     * Processes file URIs to work around Chrome ERR_UPLOAD_FILE_CHANGED bug.
     *
     * This method caches files from cloud storage providers (Google Drive, OneDrive, etc.)
     * to local storage to prevent upload failures. Files from known-safe local providers
     * (MediaStore, Downloads) are passed through unchanged for optimal performance.
     *
     * Apps should call this method with URIs from the file picker, then pass the result
     * to filePathCallback.onReceiveValue() to complete the file selection.
     *
     * @param context Android context for file operations
     * @param uris Array of URIs from file picker
     * @return Array of processed URIs (cached for cloud URIs, original for local URIs)
     */
    suspend fun processFileUris(context: Context, uris: Array<Uri?>?): Array<Uri?>? {
        if (uris == null) return null

        return withContext(Dispatchers.IO) {
            uris.map { uri ->
                if (uri == null) return@map null

                if (uri.scheme == "content") {
                    if (FileCache.isKnownSafeLocalProvider(uri)) {
                        Log.i(TAG, "Using local provider URI directly: $uri")
                        uri
                    } else {
                        val cachedUri = FileCache.copyToCache(context, uri)
                        if (cachedUri != null) {
                            Log.i(TAG, "Copied content URI to cache: $uri -> $cachedUri")
                            cachedUri
                        } else {
                            Log.w(TAG, "Failed to copy content URI to cache, using original: $uri")
                            uri
                        }
                    }
                } else {
                    uri
                }
            }.toTypedArray()
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        clearConfig()
        webView.stopLoading()
        FileCache.clearCache(context)
        contentChangeListener = null
        historyChangeListener = null
        featuredImageChangeListener = null
        editorDidBecomeAvailableListener = null
        filePathCallback = null
        onFileChooserRequested = null
        autocompleterTriggeredListener = null
        modalDialogStateListener = null
        networkRequestListener = null
        requestInterceptor = DefaultGutenbergRequestInterceptor()
        latestContentProvider = null
        handler.removeCallbacksAndMessages(null)
        webView.destroy()
    }

    companion object {
        private const val TAG = "GutenbergView"
        private const val ASSET_LOADING_TIMEOUT_MS = 5000L

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
