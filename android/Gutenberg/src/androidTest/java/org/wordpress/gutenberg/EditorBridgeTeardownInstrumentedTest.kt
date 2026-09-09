package org.wordpress.gutenberg

import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Pins what a real [WebView] hands back once the editor's bridge is gone.
 *
 * When the editor's `ErrorBoundary` catches, React unmounts the editor and
 * `useHostBridge`'s cleanup deletes every `window.editor.*` method, while
 * `window.editor` survives as an empty object because it is assigned at module
 * scope. `GutenbergView.isEditorLoaded` is never reset, so `getTitleAndContent`
 * still reaches the web view in that state.
 *
 * The exact string returned here is what [parseTitleAndContent] has to reject.
 * A unit test asserting `"null"` in isolation would keep passing even if the
 * platform started returning something else, which is why this runs on a device.
 *
 *   ./gradlew :Gutenberg:connectedDebugAndroidTest \
 *     -Pandroid.testInstrumentationRunnerArguments.class=\
 *     org.wordpress.gutenberg.EditorBridgeTeardownInstrumentedTest
 */
@RunWith(AndroidJUnit4::class)
class EditorBridgeTeardownInstrumentedTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    private fun evaluateAgainstTornDownBridge(script: String): String {
        lateinit var webView: WebView
        val loaded = CountDownLatch(1)

        instrumentation.runOnMainSync {
            webView = WebView(instrumentation.targetContext)
            webView.settings.javaScriptEnabled = true
            webView.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView, url: String) {
                    loaded.countDown()
                }
            }
            webView.loadDataWithBaseURL(
                null, "<html><body></body></html>", "text/html", "utf-8", null
            )
        }
        assertTrue("page loaded", loaded.await(TIMEOUT_SECONDS, TimeUnit.SECONDS))

        val result = arrayOfNulls<String>(1)
        val evaluated = CountDownLatch(1)
        instrumentation.runOnMainSync {
            // The post-crash bridge: the object remains, the methods are gone.
            webView.evaluateJavascript("window.editor = {};", null)
            webView.evaluateJavascript(script) { value ->
                result[0] = value
                evaluated.countDown()
            }
        }
        assertTrue("script evaluated", evaluated.await(TIMEOUT_SECONDS, TimeUnit.SECONDS))

        return result[0]!!
    }

    @Test
    fun evaluateJavaScriptYieldsNullWhenTheBridgeMethodIsGone() {
        assertEquals("null", evaluateAgainstTornDownBridge(GET_TITLE_AND_CONTENT))
    }

    @Test
    fun theTornDownBridgeResultIsRejectedRatherThanReadAsAnEmptyTitle() {
        val result = evaluateAgainstTornDownBridge(GET_TITLE_AND_CONTENT)

        assertNull(
            "a failed read must not resolve to a title the host would persist",
            parseTitleAndContent(result, ORIGINAL_CONTENT)
        )
    }

    private companion object {
        const val TIMEOUT_SECONDS = 10L
        const val GET_TITLE_AND_CONTENT = "editor.getTitleAndContent(true);"
        const val ORIGINAL_CONTENT = "<!-- wp:paragraph --><p>Body</p><!-- /wp:paragraph -->"
    }
}
