package org.wordpress.gutenberg

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.AttributeSet
import android.util.Log
import android.view.View
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
import androidx.webkit.WebViewAssetLoader
import androidx.webkit.WebViewAssetLoader.AssetsPathHandler
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONException
import org.json.JSONObject
import java.util.Locale

/**
 * Custom path for serving bundled assets when using loadDataWithBaseURL.
 * This allows the WebView to load local assets while having the site URL as document origin.
 */
const val BUNDLED_ASSET_PATH = "/gbk-assets/"

class GutenbergView : WebView {
    private var isEditorLoaded = false
    private var didFireEditorLoaded = false
    private var assetLoader: WebViewAssetLoader? = null
    private var configuration: EditorConfiguration = EditorConfiguration.builder().build()

    /**
     * Tracks whether we're using dev server mode.
     * In dev server mode, assets are loaded from a local development server.
     */
    private var devServerURL: String? = null

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

    /**
     * Stores the contextId from the most recent openMediaLibrary call
     * to pass back to JavaScript when media is selected
     */
    private var currentMediaContextId: String? = null

    var textEditorEnabled: Boolean = false
        set(value) {
            field = value
            val mode = if (value) "text" else "visual"
            handler.post {
                this.evaluateJavascript("editor.switchEditorMode('$mode');", null)
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

    fun setOnFileChooserRequestedListener(listener: (Intent, Int) -> Unit) {
        onFileChooserRequested = listener
    }

    fun setEditorDidBecomeAvailable(listener: EditorAvailableListener?) {
        editorDidBecomeAvailableListener = listener
    }

    constructor(context: Context) : super(context)
    constructor(context: Context, attrs: AttributeSet) : super(context, attrs)
    constructor(context: Context, attrs: AttributeSet, defStyle: Int) : super(
        context,
        attrs,
        defStyle
    )

    @SuppressLint("SetJavaScriptEnabled") // Without JavaScript we have no Gutenberg
    fun initializeWebView() {
        this.settings.javaScriptCanOpenWindowsAutomatically = true
        this.settings.javaScriptEnabled = true
        this.settings.domStorageEnabled = true
        this.addJavascriptInterface(this, "editorDelegate")
        this.visibility = View.GONE

        this.webViewClient = object : WebViewClient() {
            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?
            ) {
                Log.e("GutenbergView", error.toString())
                super.onReceivedError(view, request, error)
            }

            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
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

                // Intercept requests to our bundled asset path
                val path = request.url.path
                if (path?.startsWith(BUNDLED_ASSET_PATH) == true) {
                    return assetLoader?.shouldInterceptRequest(request.url)
                        ?: super.shouldInterceptRequest(view, request)
                }

                // Handle request interceptor (for API requests, cached assets, etc.)
                if (requestInterceptor.canIntercept(request)) {
                    return requestInterceptor.handleRequest(request)
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

                // Allow WordPress.com REST API
                if (url.host == "public-api.wordpress.com") {
                    return false
                }

                // Allow WordPress REST API
                val siteHost = Uri.parse(configuration.siteApiRoot).host
                if (url.host == siteHost) {
                    if (url.path?.contains("/wp-json/") == true || url.query?.contains("rest_route=") == true) {
                        return false
                    }

                    // Intercept navigation to site root (reload scenario)
                    if (url.path == "/" || url.path.isNullOrEmpty()) {
                        reloadEditorHTML()
                        return true
                    }
                }

                // Allow local development server if configured
                if (devServerURL != null) {
                    val editorUrl = Uri.parse(devServerURL)
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

        this.webChromeClient = object : WebChromeClient() {
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

    fun start(configuration: EditorConfiguration) {
        this.configuration = configuration

        // Set up asset caching if enabled
        if (configuration.enableAssetCaching) {
            val library = EditorAssetsLibrary(context, configuration)
            val cachedInterceptor = CachedAssetRequestInterceptor(
                library,
                configuration.cachedAssetHosts
            )
            requestInterceptor = cachedInterceptor
        }

        // Set up asset loader with site domain for same-origin loading
        // This allows the WebView to serve bundled assets while using the site URL as document origin
        val siteHost = Uri.parse(configuration.siteApiRoot).host ?: "localhost"
        assetLoader = WebViewAssetLoader.Builder()
            .setDomain(siteHost)
            .addPathHandler(BUNDLED_ASSET_PATH, AssetsPathHandler(this.context))
            .build()

        initializeWebView()

        // Check for dev server URL
        devServerURL = if (BuildConfig.GUTENBERG_EDITOR_URL.isNotEmpty()) {
            BuildConfig.GUTENBERG_EDITOR_URL
        } else {
            null
        }

        WebStorage.getInstance().deleteAllData()
        this.clearCache(true)
        // Accept third-party cookies since plugin stylesheets may set them
        CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)

        // Erase all local cookies before loading the URL – we don't want to persist
        // anything between uses – otherwise we might send the wrong cookies
        CookieManager.getInstance().removeAllCookies {
            CookieManager.getInstance().flush()
            for(cookie in configuration.cookies) {
                CookieManager.getInstance().setCookie(cookie.key, cookie.value)
            }

            if (devServerURL != null) {
                loadDevServerHTML()
            } else {
                loadBundledHTML()
            }

            Log.i("GutenbergView", "Startup Complete")
        }
    }

    /**
     * Load the editor HTML from bundled assets.
     * Transforms relative URLs to use the bundled asset path.
     */
    private fun loadBundledHTML() {
        try {
            val inputStream = context.assets.open("index.html")
            var html = inputStream.bufferedReader().use { it.readText() }

            // Transform relative URLs to use our bundled asset path
            html = html.replace("src=\"/", "src=\"$BUNDLED_ASSET_PATH")
            html = html.replace("href=\"/", "href=\"$BUNDLED_ASSET_PATH")

            // Load with site URL as base to enable same-origin stylesheet access
            val baseUrl = configuration.siteApiRoot.removeSuffix("/wp-json")
            loadDataWithBaseURL(baseUrl, html, "text/html", "UTF-8", null)
        } catch (e: Exception) {
            Log.e("GutenbergView", "Failed to load bundled index.html: ${e.message}")
        }
    }

    /**
     * Load the editor HTML from a development server.
     * Transforms relative URLs to absolute dev server URLs.
     */
    private fun loadDevServerHTML() {
        val serverUrl = devServerURL ?: return

        Thread {
            try {
                val url = java.net.URL(serverUrl)
                val connection = url.openConnection() as java.net.HttpURLConnection
                connection.requestMethod = "GET"
                connection.connectTimeout = 5000
                connection.readTimeout = 5000

                val responseCode = connection.responseCode
                if (responseCode == java.net.HttpURLConnection.HTTP_OK) {
                    var html = connection.inputStream.bufferedReader().use { it.readText() }

                    // Transform relative URLs to absolute dev server URLs
                    val devServerBase = serverUrl.trimEnd('/')
                    html = html.replace("src=\"/", "src=\"$devServerBase/")
                    html = html.replace("href=\"/", "href=\"$devServerBase/")

                    // Load with site URL as base to enable same-origin stylesheet access
                    val baseUrl = configuration.siteApiRoot.removeSuffix("/wp-json")
                    handler.post {
                        loadDataWithBaseURL(baseUrl, html, "text/html", "UTF-8", null)
                    }
                } else {
                    Log.e("GutenbergView", "Failed to load dev server HTML: HTTP $responseCode")
                }
                connection.disconnect()
            } catch (e: Exception) {
                Log.e("GutenbergView", "Failed to load dev server HTML: ${e.message}")
            }
        }.start()
    }

    /**
     * Reload the editor HTML (used when intercepting reload navigation).
     */
    private fun reloadEditorHTML() {
        if (devServerURL != null) {
            loadDevServerHTML()
        } else {
            loadBundledHTML()
        }
    }

    private fun setGlobalJavaScriptVariables() {
        val escapedTitle = encodeForEditor(configuration.title)
        val escapedContent = encodeForEditor(configuration.content)
        val editorSettings = configuration.editorSettings ?: "undefined"

        val gbKitConfig = """
            window.GBKit = {
                "siteApiRoot": "${configuration.siteApiRoot}",
                "siteApiNamespace": ${configuration.siteApiNamespace.joinToString(",", "[", "]") { "\"$it\"" }},
                "namespaceExcludedPaths": ${configuration.namespaceExcludedPaths.joinToString(",", "[", "]") { "\"$it\"" }},
                "authHeader": "${configuration.authHeader}",
                "themeStyles": ${configuration.themeStyles},
                "plugins": ${configuration.plugins},
                "hideTitle": ${configuration.hideTitle},
                "editorSettings": $editorSettings,
                "locale": "${configuration.locale}",
                ${if (configuration.editorAssetsEndpoint != null) "\"editorAssetsEndpoint\": \"${configuration.editorAssetsEndpoint}\"," else ""}
                "enableNetworkLogging": ${configuration.enableNetworkLogging},
                "post": {
                    "id": ${configuration.postId ?: -1},
                    "title": "$escapedTitle",
                    "content": "$escapedContent"
                }
            };
            localStorage.setItem('GBKit', JSON.stringify(window.GBKit));
        """.trimIndent()

        this.evaluateJavascript(gbKitConfig, null)
    }

    private fun encodeForEditor(value: String): String {
        return java.net.URLEncoder.encode(value, "UTF-8").replace("+", "%20")
    }

    fun clearConfig() {
        val jsCode = """
            delete window.GBKit;
            localStorage.removeItem('GBKit');
        """.trimIndent()

        this.evaluateJavascript(jsCode, null)
    }

    fun setContent(newContent: String) {
        if (!isEditorLoaded) {
            Log.e("GutenbergView", "You can't change the editor content until it has loaded")
            return
        }
        val encodedContent = encodeForEditor(newContent)
        this.evaluateJavascript("editor.setContent('$encodedContent');", null)
    }

    fun setTitle(newTitle: String) {
        if (!isEditorLoaded) {
            Log.e("GutenbergView", "You can't change the editor content until it has loaded")
            return
        }
        val encodedTitle = encodeForEditor(newTitle)
        this.evaluateJavascript("editor.setTitle('$encodedTitle');", null)
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

    fun getTitleAndContent(originalContent: CharSequence, callback: TitleAndContentCallback, completeComposition: Boolean = false) {
        if (!isEditorLoaded) {
            Log.e("GutenbergView", "You can't change the editor content until it has loaded")
            return
        }
        handler.post {
            this.evaluateJavascript("editor.getTitleAndContent($completeComposition);") { result ->
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
            this.evaluateJavascript("editor.undo();", null)
        }
    }

    fun redo() {
        handler.post {
            this.evaluateJavascript("editor.redo();", null)
        }
    }

    fun dismissTopModal() {
        handler.post {
            this.evaluateJavascript("editor.dismissTopModal();", null)
        }
    }

    fun appendTextAtCursor(text: String) {
        if (!isEditorLoaded) {
            Log.e("GutenbergView", "You can't append text until the editor has loaded")
            return
        }
        val encodedText = encodeForEditor(text)
        handler.post {
            this.evaluateJavascript("editor.appendTextAtCursor(decodeURIComponent('$encodedText'));", null)
        }
    }

    @JavascriptInterface
    fun onEditorLoaded() {
        Log.i("GutenbergView", "EditorLoaded received in native code")
        isEditorLoaded = true
        handler.post {
            if(!didFireEditorLoaded) {
                editorDidBecomeAvailableListener?.onEditorAvailable(this)
                this.didFireEditorLoaded = true
                this.visibility = View.VISIBLE
                this.alpha = 0f
                this.animate()
                    .alpha(1f)
                    .setDuration(300)
                    .start()

                if (configuration.content.isEmpty()) {
                    // Focus the editor content
                    this.evaluateJavascript("editor.focus();", null)

                    // Request focus on the WebView and show the soft keyboard
                    handler.postDelayed({
                        this.requestFocus()
                        val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
                        imm?.showSoftInput(this, InputMethodManager.SHOW_IMPLICIT)
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
        this.evaluateJavascript("editor.setMediaUploadAttachment($media, '$escapedContextId');", null)

        currentMediaContextId = null
    }

    @JavascriptInterface
    fun onEditorExceptionLogged(exception: String) {
        val parsedException = GutenbergJsException.fromString(exception)
        logJsExceptionListener?.onLogJsException(parsedException)
    }

    @JavascriptInterface
    fun showBlockPicker() {
        Log.i("GutenbergView", "BlockPickerShouldShow")
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
                        Log.i("GutenbergView", "Using local provider URI directly: $uri")
                        uri
                    } else {
                        val cachedUri = FileCache.copyToCache(context, uri)
                        if (cachedUri != null) {
                            Log.i("GutenbergView", "Copied content URI to cache: $uri -> $cachedUri")
                            cachedUri
                        } else {
                            Log.w("GutenbergView", "Failed to copy content URI to cache, using original: $uri")
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
        this.stopLoading()
        (requestInterceptor as? CachedAssetRequestInterceptor)?.shutdown()
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
        handler.removeCallbacksAndMessages(null)
        this.destroy()
    }

    companion object {
        private const val ASSET_LOADING_TIMEOUT_MS = 5000L

        // Warmup state management
        private var warmupHandler: Handler? = null
        private var warmupRunnable: Runnable? = null
        private var warmupWebView: GutenbergView? = null

        /**
         * Warmup the editor by preloading assets in a temporary WebView.
         * This pre-caches assets to improve editor launch speed.
         */
        @JvmStatic
        fun warmup(context: Context, configuration: EditorConfiguration) {
            // Cancel any existing warmup
            cancelWarmup()

            // Create dedicated warmup WebView
            val webView = GutenbergView(context)
            webView.initializeWebView()
            webView.start(configuration)
            warmupWebView = webView

            // Schedule cleanup after assets are loaded
            warmupHandler = Handler(Looper.getMainLooper())
            warmupRunnable = Runnable {
                cleanupWarmup()
            }
            warmupHandler?.postDelayed(warmupRunnable!!, ASSET_LOADING_TIMEOUT_MS)
        }

        /**
         * Cancel any pending warmup and clean up resources.
         */
        @JvmStatic
        fun cancelWarmup() {
            warmupRunnable?.let { runnable ->
                warmupHandler?.removeCallbacks(runnable)
            }
            cleanupWarmup()
        }

        /**
         * Clean up warmup resources.
         */
        private fun cleanupWarmup() {
            warmupWebView?.let { webView ->
                webView.stopLoading()
                webView.clearConfig()
                webView.destroy()
            }
            warmupWebView = null
            warmupHandler = null
            warmupRunnable = null
        }

        /**
         * Create a new GutenbergView for the editor.
         * Cancels any pending warmup to free resources.
         */
        @JvmStatic
        fun createForEditor(context: Context): GutenbergView {
            // Cancel any pending warmup to free resources
            cancelWarmup()

            // Create fresh WebView for editor
            val webView = GutenbergView(context)
            webView.initializeWebView()
            return webView
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
