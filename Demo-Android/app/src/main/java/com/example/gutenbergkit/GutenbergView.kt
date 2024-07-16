package com.example.gutenbergkit

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.AttributeSet
import android.util.Log
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient


class GutenbergView : WebView {

    private var isEditorLoaded = false
    private var didFireEditorLoaded = false

    var editorDidBecomeAvailable: ((GutenbergView) -> Unit)? = null

    constructor(context: Context) : super(context)
    constructor(context: Context, attrs: AttributeSet) : super(context, attrs)
    constructor(context: Context, attrs: AttributeSet, defStyle: Int) : super(
        context,
        attrs,
        defStyle
    )

    fun startWithDevServer() {
        this.settings.allowFileAccess = true
        this.settings.allowUniversalAccessFromFileURLs = true
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
        }

        this.webChromeClient = object : WebChromeClient() {
            override fun onConsoleMessage(message: String?, lineNumber: Int, sourceID: String?) {
                if (message != null) {
                    Log.i("GutenbergView", message)
                } else {
                    Log.i("GutenbergView", "null message")
                }
            }
        }

        // Production mode – load the assets from the app bundle – you'll need to copy
        // this value out of the `dist` directory after building GutenbergKit
        this.loadUrl("file:///android_asset/index.html")

        // Dev mode – you can connect the app to a local dev server and have it refresh as
        // changes are made. To start the server, run `npm run dev` in the GutenbergKit/ReactApp
        // directory.
        //
        // You'll need to set this to the IP address of your local machine
        //
        // this.loadUrl("http://192.168.5.248:5173/")

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