package org.wordpress.gutenberg

import android.os.Looper
import android.view.View
import android.webkit.RenderProcessGoneDetail
import kotlinx.coroutines.test.TestScope
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.mockito.Mockito.`when`
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.wordpress.gutenberg.model.EditorConfiguration
import org.wordpress.gutenberg.model.EditorDependencies

/** How the editor survives its web view's renderer process dying. */
@RunWith(RobolectricTestRunner::class)
class GutenbergViewRenderProcessGoneTest {

    private val testScope = TestScope()

    private fun siteView() = GutenbergView(
        EditorConfiguration.builder("https://example.com", "https://example.com/wp-json/").build(),
        EditorDependencies.empty,
        testScope,
        RuntimeEnvironment.getApplication()
    ).also { shadowOf(Looper.getMainLooper()).idle() }

    /** The editor document, mirroring the fallback in `loadEditor`. */
    private val editorUrl = BuildConfig.GUTENBERG_EDITOR_URL
        .ifEmpty { "https://example.com/assets/index.html" }

    private fun loadedSiteView() = siteView().also { view ->
        view.onEditorLoaded()
        shadowOf(Looper.getMainLooper()).idle()
    }

    private fun killRenderer(view: GutenbergView): Boolean {
        val detail = mock(RenderProcessGoneDetail::class.java)
        `when`(detail.didCrash()).thenReturn(true)
        val webView = view.editorWebView
        val handled = webView.webViewClient.onRenderProcessGone(webView, detail)
        shadowOf(Looper.getMainLooper()).idle()
        return handled
    }

    @Test
    fun `a renderer death is handled so the app survives it`() {
        val view = loadedSiteView()

        assertTrue("an unhandled renderer death kills the app", killRenderer(view))
    }

    @Test
    fun `a renderer death replaces the web view`() {
        val view = loadedSiteView()
        val deadWebView = view.editorWebView

        killRenderer(view)

        assertNotSame("a web view can't be used once its renderer dies", deadWebView, view.editorWebView)
        assertNull("the dead web view leaves the hierarchy", deadWebView.parent)
        assertSame(view, view.editorWebView.parent)
        assertEquals("the new web view stays behind the overlays", 0, view.indexOfChild(view.editorWebView))
    }

    @Test
    fun `a renderer death fails reads waiting on the dead renderer`() {
        val view = loadedSiteView()
        val callback = RecordingTitleAndContentCallback()
        // Robolectric's shadow WebView never invokes the ValueCallback, like a
        // renderer that dies before it answers.
        view.getTitleAndContent("original content", callback)
        shadowOf(Looper.getMainLooper()).idle()

        killRenderer(view)

        assertTrue("the host is told the editor is not ready", callback.errors.single() is EditorNotReadyException)
    }

    @Test
    fun `a renderer death tells the host the editor is unavailable`() {
        val view = loadedSiteView()
        var unavailable = false
        view.setEditorDidBecomeUnavailable { unavailable = true }

        killRenderer(view)

        assertTrue(unavailable)
    }

    @Test
    fun `a renderer death after the editor loaded loads it again`() {
        val view = loadedSiteView()

        killRenderer(view)

        assertEquals(editorUrl, shadowOf(view.editorWebView).lastLoadedUrl)
        assertEquals(View.VISIBLE, view.editorWebView.visibility)
    }

    @Test
    fun `a renderer death before the editor loaded offers a reload instead of looping`() {
        val view = siteView()

        killRenderer(view)

        assertNull("loading again may kill the renderer again", shadowOf(view.editorWebView).lastLoadedUrl)
        assertEquals("the crash notice covers the editor", View.INVISIBLE, view.editorWebView.visibility)

        view.reloadEditor()
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals("the blank web view has no page to reload", editorUrl, shadowOf(view.editorWebView).lastLoadedUrl)
    }

    private class RecordingTitleAndContentCallback : GutenbergView.TitleAndContentCallback {
        val errors = mutableListOf<Throwable>()

        override fun onResult(title: CharSequence, content: CharSequence) = Unit

        override fun onError(error: Throwable) {
            errors += error
        }
    }
}
