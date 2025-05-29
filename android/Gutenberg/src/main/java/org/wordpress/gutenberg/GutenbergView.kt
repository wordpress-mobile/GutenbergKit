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
import org.json.JSONException
import org.json.JSONObject
import java.util.Locale

const val ASSET_URL = "https://appassets.androidplatform.net/assets/index.html"
const val ASSET_URL_REMOTE = "https://appassets.androidplatform.net/assets/remote.html"

class GutenbergView : WebView {
    private var isEditorLoaded = false
    private var didFireEditorLoaded = false
    private var assetLoader = WebViewAssetLoader.Builder()
        .addPathHandler("/assets/", AssetsPathHandler(this.context))
        .build()
    private var configuration: EditorConfiguration = EditorConfiguration.builder().build()

    private val handler = Handler(Looper.getMainLooper())
    private var editorDidBecomeAvailable: ((GutenbergView) -> Unit)? = null
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
                } else if (request.url.host?.contains("appassets.androidplatform.net") == true) {
                    return assetLoader.shouldInterceptRequest(request.url)
                } else if (requestInterceptor.canIntercept(request)) {
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

                // Allow asset URLs
                if (url.host == Uri.parse(ASSET_URL).host || url.host == Uri.parse(ASSET_URL_REMOTE).host) {
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

                // Allow remote editor server if configured
                if (BuildConfig.GUTENBERG_EDITOR_REMOTE_URL.isNotEmpty()) {
                    val remoteEditorUrl = Uri.parse(BuildConfig.GUTENBERG_EDITOR_REMOTE_URL)
                    if (url.host == remoteEditorUrl.host) {
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

        initializeWebView()

        val editorUrl = if (configuration.plugins && BuildConfig.GUTENBERG_EDITOR_REMOTE_URL.isNotEmpty()) {
            BuildConfig.GUTENBERG_EDITOR_REMOTE_URL
        } else if (BuildConfig.GUTENBERG_EDITOR_URL.isNotEmpty()) {
            BuildConfig.GUTENBERG_EDITOR_URL
        } else if (configuration.plugins) {
            ASSET_URL_REMOTE
        } else {
            ASSET_URL
        }

        WebStorage.getInstance().deleteAllData()
        this.clearCache(true)
        // All cookies are third-party cookies because the root of this document
        // lives under `https://appassets.androidplatform.net`
        CookieManager.getInstance().setAcceptThirdPartyCookies(this, true);

        // Erase all local cookies before loading the URL – we don't want to persist
        // anything between uses – otherwise we might send the wrong cookies
        CookieManager.getInstance().removeAllCookies {
            CookieManager.getInstance().flush()
            for(cookie in configuration.cookies) {
                CookieManager.getInstance().setCookie(cookie.key, cookie.value)
            }
            this.loadUrl(editorUrl)

            Log.i("GutenbergView", "Startup Complete")
        }
    }

    private fun setGlobalJavaScriptVariables() {
        // Generate JavaScript globals
        val globalsJS = configuration.webViewGlobals.map { global ->
            "window[\"${global.name}\"] = ${global.value.toJavaScript()};"
        }.joinToString("\n")

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
                "hideTitle": ${configuration.hideTitle},
                "editorSettings": $editorSettings,
                "locale": "${configuration.locale}",
                ${if (configuration.postId != null) """
                "post": {
                    "id": ${configuration.postId},
                    "title": "$escapedTitle",
                    "content": "$escapedContent"
                }
                """ else ""}
            };
            localStorage.setItem('GBKit', JSON.stringify(window.GBKit));
        """.trimIndent()

        val combinedJS = if (globalsJS.isNotEmpty()) {
            "$globalsJS\n$gbKitConfig"
        } else {
            gbKitConfig
        }

        this.evaluateJavascript(combinedJS, null)
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
        val value: Value?
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

    @JavascriptInterface
    fun onEditorLoaded() {
        Log.i("GutenbergView", "EditorLoaded received in native code")
        isEditorLoaded = true
        handler.post {
            if(!didFireEditorLoaded) {
                editorDidBecomeAvailableListener?.onEditorAvailable(this)
                this.editorDidBecomeAvailable?.let { it(this) }
                this.didFireEditorLoaded = true
                this.visibility = View.VISIBLE
                this.alpha = 0f
                this.animate()
                    .alpha(1f)
                    .setDuration(300)
                    .start()
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

            val config = OpenMediaLibraryConfig(allowedTypes = allowedTypes, multiple = multiple, value = value)

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
        this.evaluateJavascript("editor.setMediaUploadAttachment($media);", null)
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

    fun resetFilePathCallback() {
        filePathCallback = null
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        clearConfig()
        this.stopLoading()
        contentChangeListener = null
        historyChangeListener = null
        featuredImageChangeListener = null
        editorDidBecomeAvailable = null
        filePathCallback = null
        onFileChooserRequested = null
        handler.removeCallbacksAndMessages(null)
    }
}

object GutenbergWebViewPool {
    private var preloadedWebView: GutenbergView? = null

    @JvmStatic
    fun getPreloadedWebView(context: Context): GutenbergView {
        if (preloadedWebView == null) {
            preloadedWebView = createAndPreloadWebView(context)
        }
        return preloadedWebView!!
    }

    private fun createAndPreloadWebView(context: Context): GutenbergView {
        val webView = GutenbergView(context)
        webView.initializeWebView()
        webView.loadUrl(ASSET_URL)
        return webView
    }

    @JvmStatic
    fun recycleWebView(webView: GutenbergView) {
        webView.stopLoading()
        webView.clearConfig()
        webView.removeAllViews()
        webView.destroy()
        preloadedWebView = null
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
