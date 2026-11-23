package org.wordpress.gutenberg

import android.webkit.WebView
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature

/**
 * Exposes the editor bridge to a web view's pages. Tests replace the default,
 * as Robolectric has no WebView provider.
 */
internal interface EditorBridgeRegistrar {
    /** Whether this device's WebView can tell the bridge which frame and origin sent each message. */
    fun isSupported(): Boolean

    /**
     * Exposes `window.editorDelegate` to frames of [allowedOrigin] in [webView],
     * delivering the messages they post to [listener].
     */
    fun register(webView: WebView, allowedOrigin: String, listener: WebViewCompat.WebMessageListener)
}

internal object WebViewEditorBridgeRegistrar : EditorBridgeRegistrar {
    override fun isSupported(): Boolean =
        WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)

    override fun register(webView: WebView, allowedOrigin: String, listener: WebViewCompat.WebMessageListener) {
        WebViewCompat.addWebMessageListener(webView, "editorDelegate", setOf(allowedOrigin), listener)
    }
}
