package org.wordpress.gutenberg

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.AttributeSet
import android.util.Log
import android.webkit.ConsoleMessage
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebViewAssetLoader
import androidx.webkit.WebViewAssetLoader.AssetsPathHandler

class GutenbergView : WebView {

    private var isEditorLoaded = false
    private var didFireEditorLoaded = false
    private var assetLoader = WebViewAssetLoader.Builder()
        .addPathHandler("/assets/", AssetsPathHandler(this.context))
        .build()

    var editorDidBecomeAvailable: ((GutenbergView) -> Unit)? = null

    constructor(context: Context) : super(context)
    constructor(context: Context, attrs: AttributeSet) : super(context, attrs)
    constructor(context: Context, attrs: AttributeSet, defStyle: Int) : super(
        context,
        attrs,
        defStyle
    )

    @SuppressLint("SetJavaScriptEnabled") // Without JavaScript we have no Gutenberg
    fun start() {
        this.settings.javaScriptCanOpenWindowsAutomatically = true
        this.settings.javaScriptEnabled = true
        this.addJavascriptInterface(this, "editorDelegate")

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
        }

        // Production mode – load the assets from the app bundle – you'll need to copy
        // this value out of the `dist` directory after building GutenbergKit
        //
        // This URL maps to the `assets` directory in this module
        this.loadUrl("https://appassets.androidplatform.net/assets/index.html")

        // Dev mode – you can connect the app to a local dev server and have it refresh as
        // changes are made. To start the server, run `make dev-server` in the project root
        // directory.
        //
        // This only works in the emulator – if you want to run on a real device, you'll need to
        // set this to the IP address of your dev machine.
        // this.loadUrl("http://10.0.2.2:5173/")

        Log.i("GutenbergView", "Startup Complete")
    }

    fun setContent(newContent: String) {
        Log.i("GutenbergView", "Setting content to $newContent")

        if(!isEditorLoaded) {
            Log.e("GutenbergView", "You can't change the editor content until it has loaded")
            return
        }

        this.evaluateJavascript("editor.setContent('$newContent');", null)
    }

    @JavascriptInterface
    fun onEditorLoaded() {
        Log.i("GutenbergView", "EditorLoaded received in native code")
        isEditorLoaded = true
        Handler(Looper.getMainLooper()).post {
            if(!didFireEditorLoaded) {
                this.editorDidBecomeAvailable?.let { it(this) }
                this.didFireEditorLoaded = true
            }
        }
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
}