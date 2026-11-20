package org.wordpress.gutenberg

import android.app.Application
import android.webkit.WebView
import androidx.webkit.WebViewCompat
import java.util.concurrent.Executor

/**
 * The application Robolectric creates for each test. Robolectric has no WebView
 * provider, so each test starts with a bridge registrar that supports the listener.
 * Messages are parsed in place, leaving only the main looper to run.
 */
class GutenbergTestApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        GutenbergView.bridgeRegistrar = FakeEditorBridgeRegistrar()
        GutenbergView.bridgeParsingExecutor = Executor { it.run() }
    }
}

/** Records each registration in place of the WebView provider. */
internal class FakeEditorBridgeRegistrar(private val isSupported: Boolean = true) : EditorBridgeRegistrar {
    val registrations = mutableListOf<Pair<WebView, String>>()

    override fun isSupported(): Boolean = isSupported

    override fun register(webView: WebView, allowedOrigin: String, listener: WebViewCompat.WebMessageListener) {
        registrations += webView to allowedOrigin
    }
}
