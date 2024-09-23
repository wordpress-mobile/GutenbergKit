package org.wordpress.gutenberg

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.AttributeSet
import android.util.Log
import android.view.View
import android.webkit.ConsoleMessage
import android.webkit.JavascriptInterface
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebViewAssetLoader
import androidx.webkit.WebViewAssetLoader.AssetsPathHandler
import org.json.JSONObject
import java.lang.ref.WeakReference

const val ASSET_URL = "https://appassets.androidplatform.net/assets/index.html"

class GutenbergView : WebView {

    private var isEditorLoaded = false
    private var didFireEditorLoaded = false
    private var hasSetEditorConfig = false
    private var assetLoader = WebViewAssetLoader.Builder()
        .addPathHandler("/assets/", AssetsPathHandler(this.context))
        .build()
    private var initialTitle: String = ""
    private var type: String = ""
    private var id: Int? = null
    private var themeStyles: Boolean? = null
    private var initialContent: String = ""
    private var siteApiRoot: String = ""
    private var siteApiNamespace: String = ""
    private var authHeader: String = ""

    private val handler = Handler(Looper.getMainLooper())
    var editorDidBecomeAvailable: ((GutenbergView) -> Unit)? = null
    var filePathCallback: ValueCallback<Array<Uri?>?>? = null
    val pickImageRequestCode = 1
    private var onFileChooserRequested: WeakReference<((Intent, Int) -> Unit)?>? = null
    private var contentChangeListener: WeakReference<ContentChangeListener>? = null
    private var editorDidBecomeAvailableListener: WeakReference<EditorAvailableListener>? = null

    fun setContentChangeListener(listener: ContentChangeListener) {
        contentChangeListener = WeakReference(listener)
    }

    fun setOnFileChooserRequestedListener(listener: (Intent, Int) -> Unit) {
        onFileChooserRequested = WeakReference(listener)
    }

    fun setEditorDidBecomeAvailable(listener: EditorAvailableListener?) {
        editorDidBecomeAvailableListener = WeakReference(listener)
    }

    constructor(context: Context) : super(context)
    constructor(context: Context, attrs: AttributeSet) : super(context, attrs)
    constructor(context: Context, attrs: AttributeSet, defStyle: Int) : super(
        context,
        attrs,
        defStyle
    )

    @SuppressLint("SetJavaScriptEnabled") // Without JavaScript we have no Gutenberg
    fun start(
        siteApiRoot: String = "",
        siteApiNamespace: String = "",
        authHeader: String = "",
        themeStyles: Boolean = false,
        postId: Int? = null,
        postType: String = "",
        postTitle: String = "",
        postContent: String = ""
    ) {
        id = postId
        type = postType
        initialTitle = postTitle
        initialContent = postContent
        this.themeStyles = themeStyles
        this.siteApiRoot = siteApiRoot
        this.siteApiNamespace = siteApiNamespace
        this.authHeader = authHeader
        this.settings.javaScriptCanOpenWindowsAutomatically = true
        this.settings.javaScriptEnabled = true
        this.settings.domStorageEnabled = true;
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

            override fun shouldInterceptRequest(
                view: WebView?,
                request: WebResourceRequest?
            ): WebResourceResponse? {
                if (!hasSetEditorConfig) {
                    handler.post {
                        var editorInitialConfig = getEditorConfiguration()
                        view?.evaluateJavascript(editorInitialConfig, null)

                    }
                    hasSetEditorConfig = true
                }

                return if (request?.url != null) {
                    assetLoader.shouldInterceptRequest(request.url)
                } else {
                    super.shouldInterceptRequest(view, request)
                }
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
                val mimeTypes = fileChooserParams?.acceptTypes

                val intent = Intent(Intent.ACTION_PICK).apply {
                    type = "*/*"  // Default to all types
                }

                if (!mimeTypes.isNullOrEmpty()) {
                    intent.type = mimeTypes.joinToString("|")
                }

                if (allowMultiple) {
                    intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                }

                onFileChooserRequested?.get()?.let { callback ->
                    handler.post {
                        callback(Intent.createChooser(intent, "Select Files"), pickImageRequestCode)
                    }
                }
                return true
            }
        }

        // Production mode – load the assets from the app bundle – you'll need to copy
        // this value out of the `dist` directory after building GutenbergKit
        //
        // This URL maps to the `assets` directory in this module
        this.loadUrl(ASSET_URL)

        // Dev mode – you can connect the app to a local dev server and have it refresh as
        // changes are made. To start the server, run `make dev-server` in the project root
        // directory.
        //
        // This only works in the emulator – if you want to run on a real device, you'll need to
        // set this to the IP address of your dev machine.
        // this.loadUrl("http://10.0.2.2:5173/")

        Log.i("GutenbergView", "Startup Complete")
    }

    private fun getEditorConfiguration(): String {
        val escapedTitle = java.net.URLEncoder.encode(initialTitle, "UTF-8").replace("+", "%20")
        val escapedContent = java.net.URLEncoder.encode(initialContent, "UTF-8").replace("+", "%20")

        val jsCode = """
            window.GBKit = {
                siteApiRoot: '$siteApiRoot',
                siteApiNamespace: '$siteApiNamespace',
                authHeader: '$authHeader',
                themeStyles: $themeStyles,
                ${if (id != null) """
                post: {
                    id: $id,
                    title: '$escapedTitle',
                    content: '$escapedContent'
                },
                """ else ""}
            };
            localStorage.setItem('GBKit', JSON.stringify(window.GBKit));
        """.trimIndent()
        return jsCode
    }

    fun setContent(newContent: String) {
        if(!isEditorLoaded) {
            Log.e("GutenbergView", "You can't change the editor content until it has loaded")
            return
        }
        this.evaluateJavascript("editor.setContent('$newContent');", null)
    }

    fun setTitle(newTitle: String) {
        if(!isEditorLoaded) {
            Log.e("GutenbergView", "You can't change the editor content until it has loaded")
            return
        }
        this.evaluateJavascript("editor.setTitle('$newTitle');", null)
    }

    interface TitleAndContentCallback {
        fun onResult(title: String, content: String)
    }

    interface ContentChangeListener {
        fun onContentChanged(title: String, content: String)
    }

    interface EditorAvailableListener {
        fun onEditorAvailable(view: GutenbergView?)
    }

    fun getTitleAndContent(callback: TitleAndContentCallback, clearFocus: Boolean = true) {
        if (!isEditorLoaded) {
            Log.e("GutenbergView", "You can't change the editor content until it has loaded")
            return
        }
        handler.post {
            // Clearing the focus is necessary to resolve any pending text composition,
            // ensuring the editor provides the latest content.
            if (clearFocus) {
                this.clearFocus()
            }
            this.evaluateJavascript("editor.getTitleAndContent();") { result ->
                val jsonObject = JSONObject(result)
                val title = jsonObject.optString("title", "")
                val content = jsonObject.optString("content", "")
                callback.onResult(title, content)
            }
        }
    }

    @JavascriptInterface
    fun onEditorLoaded() {
        Log.i("GutenbergView", "EditorLoaded received in native code")
        isEditorLoaded = true
        handler.post {
            if(!didFireEditorLoaded) {
                editorDidBecomeAvailableListener?.get()?.onEditorAvailable(this)
                this.editorDidBecomeAvailable?.let { it(this) }
                this.didFireEditorLoaded = true
                this.visibility = View.VISIBLE
                this.alpha = 0f
                this.animate()
                    .alpha(1f)
                    .setDuration(200)
                    .start()
            }
        }
    }

    @JavascriptInterface
    fun onEditorContentChanged() {
        getTitleAndContent(object : TitleAndContentCallback {
            override fun onResult(title: String, content: String) {
                contentChangeListener?.get()?.onContentChanged(title, content)
            }
        }, false)
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
    fun showBlockPicker() {
        Log.i("GutenbergView", "BlockPickerShouldShow")
    }

    fun resetFilePathCallback() {
        filePathCallback = null
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        contentChangeListener = null
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
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.loadUrl(ASSET_URL)
        return webView
    }

    @JvmStatic
    fun recycleWebView(webView: GutenbergView) {
        webView.stopLoading()
        webView.removeAllViews()
        webView.loadUrl("about:blank")
        preloadedWebView = null
    }
}