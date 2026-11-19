package org.wordpress.gutenberg

import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.webkit.RenderProcessGoneDetail
import android.widget.TextView
import kotlinx.coroutines.test.TestScope
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.wordpress.gutenberg.model.EditorConfiguration
import org.wordpress.gutenberg.model.EditorDependencies
import org.wordpress.gutenberg.views.EditorErrorView
import java.util.concurrent.Executor

/** Which pages the bridge hears, and how it answers them. */
@RunWith(RobolectricTestRunner::class)
class GutenbergViewBridgeGateTest {

    private fun siteView(siteUrl: String = "https://example.com") = GutenbergView(
        EditorConfiguration.builder(siteUrl, "$siteUrl/wp-json/").build(),
        EditorDependencies.empty,
        TestScope(),
        RuntimeEnvironment.getApplication()
    ).also { idle() }

    /** The editor document for [siteUrl], mirroring the fallback in `loadEditor`. */
    private fun editorUrl(siteUrl: String = "https://example.com") = BuildConfig.GUTENBERG_EDITOR_URL
        .ifEmpty { "$siteUrl/assets/index.html" }

    private val registrar get() = GutenbergView.bridgeRegistrar as FakeEditorBridgeRegistrar

    private fun idle() = shadowOf(Looper.getMainLooper()).idle()

    private fun GutenbergView.trackAvailability(): MutableList<String> {
        val events = mutableListOf<String>()
        setEditorDidBecomeAvailable { events += "available" }
        return events
    }

    private fun GutenbergView.isReady(): Boolean {
        val callback = RecordingTitleAndContentCallback()
        getTitleAndContent("", callback)
        idle()
        return callback.errors.none { it is EditorNotReadyException }
    }

    private fun latestContentRequest(id: Int = 1) =
        """{"message":"requestLatestContent","body":{"id":$id}}"""

    @Test
    fun `exposes the bridge to the editor's origin`() {
        val view = siteView()

        assertEquals(listOf(view.editorWebView to webOrigin(editorUrl())), registrar.registrations)
    }

    @Test
    fun `exposes the bridge to the editor's origin on a site's non-default port`() {
        siteView("http://localhost:8888")

        assertEquals(webOrigin(editorUrl("http://localhost:8888")), registrar.registrations.single().second)
    }

    @Test
    fun `exposes the bridge again in the web view that replaces one whose renderer died`() {
        val view = siteView()
        view.postBridgeMessage("onEditorLoaded")
        idle()
        val deadWebView = view.editorWebView

        deadWebView.webViewClient.onRenderProcessGone(deadWebView, mock(RenderProcessGoneDetail::class.java))
        idle()

        assertNotSame(deadWebView, view.editorWebView)
        assertEquals(listOf(deadWebView, view.editorWebView), registrar.registrations.map { it.first })
    }

    @Test
    fun `hears the editor page in the main frame`() {
        val view = siteView()
        val events = view.trackAvailability()

        view.postBridgeMessage("onEditorLoaded")
        idle()

        assertEquals(listOf("available"), events)
        assertTrue(view.isReady())
    }

    @Test
    fun `drops messages from a subframe`() {
        val view = siteView()
        val events = view.trackAvailability()

        view.postBridgeMessageJson("""{"message":"onEditorLoaded","body":{}}""", isMainFrame = false)
        val replies = view.postBridgeMessageJson(latestContentRequest(), isMainFrame = false)
        idle()

        assertTrue(events.isEmpty())
        assertTrue(replies.isEmpty())
        assertFalse(view.isReady())
    }

    @Test
    fun `accepts messages only from the editor's origin`() {
        val view = siteView()
        val events = view.trackAvailability()

        for (origin in listOf("https://other.example", "null")) {
            view.postBridgeMessageJson("""{"message":"onEditorLoaded","body":{}}""", sourceOrigin = origin)
            val replies = view.postBridgeMessageJson(latestContentRequest(), sourceOrigin = origin)
            idle()

            assertTrue(replies.isEmpty())
        }

        assertTrue(events.isEmpty())
        assertFalse(view.isReady())
    }

    @Test
    fun `answers a request for the latest content with the host's content`() {
        val view = siteView()
        view.setLatestContentProvider(object : GutenbergView.LatestContentProvider {
            override fun getLatestContent() = GutenbergView.LatestContent("Title", "<p>Content</p>")
        })

        val reply = JSONObject(view.postBridgeMessageJson(latestContentRequest(id = 7)).single())

        assertEquals("requestLatestContent", reply.getString("message"))
        assertEquals(7, reply.getJSONObject("body").getInt("id"))
        val result = reply.getJSONObject("body").getJSONObject("result")
        assertEquals("Title", result.getString("title"))
        assertEquals("<p>Content</p>", result.getString("content"))
    }

    @Test
    fun `answers a request for the latest content when the host has none`() {
        val view = siteView()

        val reply = JSONObject(view.postBridgeMessageJson(latestContentRequest()).single())

        assertTrue(reply.getJSONObject("body").isNull("result"))
    }

    @Test
    fun `shows the load error rather than the editor when the WebView can't restrict the bridge`() {
        GutenbergView.bridgeRegistrar = FakeEditorBridgeRegistrar(isSupported = false)

        val view = siteView()

        assertTrue("nothing is exposed", registrar.registrations.isEmpty())
        assertEquals(View.INVISIBLE, view.editorWebView.visibility)
        val errorView = view.children().filterIsInstance<EditorErrorView>().single()
        assertEquals(View.VISIBLE, errorView.visibility)
        val message = RuntimeEnvironment.getApplication().getString(R.string.gbk_editor_webview_unsupported)
        assertTrue(errorView.texts().contains(message))
        assertNull("the editor never loads", view.editorWebView.url)
    }

    /** Holds parsing work until [runAll], as a busy parsing thread would. */
    private class QueuedExecutor : Executor {
        private val queue = ArrayDeque<Runnable>()

        override fun execute(command: Runnable) {
            queue.addLast(command)
        }

        fun runAll() {
            while (queue.isNotEmpty()) queue.removeFirst().run()
        }
    }

    private fun queueParsing() = QueuedExecutor().also { GutenbergView.bridgeParsingExecutor = it }

    private fun GutenbergView.receive(json: String) =
        receiveBridgeMessage(json, checkNotNull(editorOrigin), isMainFrame = true) {}

    @Test
    fun `handles messages only once they're parsed, in the order they arrived`() {
        val view = siteView()
        val events = mutableListOf<String>()
        view.setContentChangeListener(object : GutenbergView.ContentChangeListener {
            override fun onContentChanged() {
                events += "contentChanged"
            }
        })
        view.setHistoryChangeListener(object : GutenbergView.HistoryChangeListener {
            override fun onHistoryChanged(hasUndo: Boolean, hasRedo: Boolean) {
                events += "history"
            }
        })
        val parsing = queueParsing()

        view.receive("""{"message":"onEditorHistoryChanged","body":{"hasUndo":true,"hasRedo":false}}""")
        view.receive("""{"message":"onEditorContentChanged","body":{}}""")
        idle()
        assertTrue("nothing is handled before it's parsed", events.isEmpty())

        parsing.runAll()
        idle()

        assertEquals(listOf("history", "contentChanged"), events)
    }

    @Test
    fun `drops a message whose page was replaced before it was handled`() {
        val view = siteView()
        val events = view.trackAvailability()
        val parsing = queueParsing()

        view.receive("""{"message":"onEditorLoaded","body":{}}""")
        view.editorWebView.webViewClient.onPageStarted(view.editorWebView, editorUrl(), null)
        parsing.runAll()
        idle()

        assertTrue("the old page can't mark the new one ready", events.isEmpty())
        assertFalse(view.isReady())
    }

    @Test
    fun `drops a message whose web view was replaced before it was handled`() {
        val view = siteView()
        view.postBridgeMessage("onEditorLoaded")
        val parsing = queueParsing()
        var unavailable = 0
        view.setEditorDidBecomeUnavailable { unavailable++ }

        view.receive("""{"message":"onEditorUnavailable","body":{}}""")
        view.editorWebView.webViewClient.onRenderProcessGone(view.editorWebView, mock(RenderProcessGoneDetail::class.java))
        idle()
        val unavailableFromRendererDeath = unavailable
        parsing.runAll()
        idle()

        assertEquals("only the renderer death is reported", unavailableFromRendererDeath, unavailable)
    }

    @Test
    fun `drops a message that is handled after the view detached`() {
        val view = siteView()
        val parsing = queueParsing()

        view.receive("""{"message":"onEditorLoaded","body":{}}""")
        View::class.java.getDeclaredMethod("onDetachedFromWindow").apply { isAccessible = true }.invoke(view)
        parsing.runAll()
        idle()

        assertFalse("a detached editor stays unready", view.isReady())
    }

    @Test
    fun `checks the finished editor page for the bridge`() {
        val view = siteView()

        view.editorWebView.webViewClient.onPageFinished(view.editorWebView, editorUrl())

        assertEquals(
            GutenbergView.MISSING_BRIDGE_CHECK_SCRIPT,
            shadowOf(view.editorWebView).lastEvaluatedJavascript
        )
    }

    @Test
    fun `leaves other finished pages unchecked`() {
        val view = siteView()

        view.editorWebView.webViewClient.onPageFinished(view.editorWebView, "https://other.example/")

        assertNotEquals(
            GutenbergView.MISSING_BRIDGE_CHECK_SCRIPT,
            shadowOf(view.editorWebView).lastEvaluatedJavascript
        )
    }

    @Test
    fun `webOrigin writes a URL's origin as WebView does`() {
        assertEquals("https://example.com", webOrigin("https://Example.com:443/assets/index.html"))
        assertEquals("http://10.0.2.2:5173", webOrigin("http://10.0.2.2:5173/"))
        assertEquals("http://localhost:8888", webOrigin("HTTP://localhost:8888"))
        assertNull(webOrigin("null"))
        assertNull(webOrigin("about:blank"))
    }

    private fun webOrigin(url: String) = GutenbergView.webOrigin(url)

    private fun ViewGroup.children(): List<View> = (0 until childCount).map { getChildAt(it) }

    private fun View.texts(): List<String> = when (this) {
        is TextView -> listOf(text.toString())
        is ViewGroup -> children().flatMap { it.texts() }
        else -> emptyList()
    }

    private class RecordingTitleAndContentCallback : GutenbergView.TitleAndContentCallback {
        val errors = mutableListOf<Throwable>()

        override fun onResult(title: CharSequence, content: CharSequence) = Unit

        override fun onError(error: Throwable) {
            errors += error
        }
    }
}
