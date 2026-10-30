package org.wordpress.gutenberg

import android.content.ContextWrapper
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.webkit.WebResourceRequest
import android.webkit.WebView
import kotlinx.coroutines.test.TestScope
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
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

/**
 * What the editor's main frame admits, and which document the editor globals reach.
 *
 * On Android the editor loads from the site's own origin, so the site's ordinary
 * pages are one navigation away from the frame holding the site credential.
 */
@RunWith(RobolectricTestRunner::class)
class GutenbergViewNavigationTest {

    private val testScope = TestScope()

    /** A view whose configuration carries a recognizable credential. */
    private fun configuredSiteView() = GutenbergView(
        EditorConfiguration.builder("https://example.com", "https://example.com/wp-json/")
            .setAuthHeader("Bearer secret-credential")
            .build(),
        EditorDependencies.empty,
        testScope,
        RuntimeEnvironment.getApplication()
    )

    /**
     * The editor document for [siteUrl], mirroring the fallback in `loadEditor` so
     * this holds whether or not a local `GUTENBERG_EDITOR_URL` dev server is set.
     */
    private fun editorUrlFor(siteUrl: String) = BuildConfig.GUTENBERG_EDITOR_URL
        .ifEmpty { "$siteUrl/assets/index.html" }

    private fun request(url: String, isForMainFrame: Boolean = true): WebResourceRequest {
        val request = mock(WebResourceRequest::class.java)
        `when`(request.url).thenReturn(Uri.parse(url))
        `when`(request.isForMainFrame).thenReturn(isForMainFrame)
        return request
    }

    private fun opensExternally(view: GutenbergView, url: String): Boolean =
        overridesLoading(view, url, isForMainFrame = true)

    /** Whether the editor's frame is kept from loading [url]. */
    private fun overridesLoading(view: GutenbergView, url: String, isForMainFrame: Boolean): Boolean =
        view.editorWebView.webViewClient.shouldOverrideUrlLoading(
            view.editorWebView,
            request(url, isForMainFrame)
        )

    private fun nextStartedActivity(): Intent? =
        shadowOf(RuntimeEnvironment.getApplication()).nextStartedActivity

    private fun idle() = shadowOf(Looper.getMainLooper()).idle()

    /** Opens a new window from the editor, returning the web view it loads into. */
    private fun openWindow(view: GutenbergView): WebView {
        val webView = view.editorWebView
        val transport = webView.WebViewTransport()
        val message = Message.obtain(Handler(Looper.getMainLooper())).apply { obj = transport }

        val created = shadowOf(webView).webChromeClient
            .onCreateWindow(webView, false, true, message)

        assertTrue("the editor should accept the new window", created)
        return requireNotNull(transport.webView) { "the new window should have a web view" }
    }

    @Test
    fun `shouldOverrideUrlLoading keeps local documents out of the main frame`() {
        val siteView = configuredSiteView()
        listOf(
            "blob:https://example.com/0b8f1e2a",
            "data:text/html,<h1>Not the editor</h1>",
            "about:blank",
            "file:///android_asset/index.html"
        ).forEach { url ->
            assertTrue("$url should not replace the editor", overridesLoading(siteView, url, isForMainFrame = true))
        }
        assertNull("no app is asked to open a local document", nextStartedActivity())
    }

    @Test
    fun `shouldOverrideUrlLoading allows local documents in subframes`() {
        // Gutenberg's `Iframe` component loads its document from a `blob` URL.
        val siteView = configuredSiteView()
        listOf(
            "blob:https://example.com/0b8f1e2a",
            "data:text/html,<p>Preview</p>",
            "about:blank",
            "file:///android_asset/index.html"
        ).forEach { url ->
            assertFalse("$url should load in a subframe", overridesLoading(siteView, url, isForMainFrame = false))
        }
    }

    @Test
    fun `shouldOverrideUrlLoading opens web pages in the browser`() {
        val result = opensExternally(configuredSiteView(), "https://example.org/a-page")

        assertTrue("a web page should not replace the editor", result)
        assertEquals(
            "the browser should open the page",
            Uri.parse("https://example.org/a-page"),
            nextStartedActivity()?.data
        )
    }

    @Test
    fun `shouldOverrideUrlLoading tolerates URLs no app can open`() {
        shadowOf(RuntimeEnvironment.getApplication()).checkActivities(true)

        val result = opensExternally(configuredSiteView(), "unknown-scheme://example")

        assertTrue("the URL should still be kept from the editor", result)
    }

    @Test
    fun `shouldOverrideUrlLoading tolerates an app refusing the URL`() {
        val refusingContext = object : ContextWrapper(RuntimeEnvironment.getApplication()) {
            override fun startActivity(intent: Intent) {
                throw SecurityException("Permission denial")
            }
        }
        val siteView = GutenbergView(
            EditorConfiguration.builder("https://example.com", "https://example.com/wp-json/").build(),
            EditorDependencies.empty,
            testScope,
            refusingContext
        )

        val result = opensExternally(siteView, "https://example.org/a-page")

        assertTrue("the URL should still be kept from the editor", result)
    }

    @Test
    fun `a new window closed by its script is discarded without opening anything`() {
        val popup = openWindow(configuredSiteView())

        shadowOf(popup).webChromeClient.onCloseWindow(popup)
        popup.webViewClient.shouldOverrideUrlLoading(popup, request("https://example.org/preview"))

        assertNull("a closed window should not open the browser", nextStartedActivity())
    }

    @Test
    fun `a new window opens web pages in the browser`() {
        val popup = openWindow(configuredSiteView())

        val result = popup.webViewClient.shouldOverrideUrlLoading(popup, request("https://example.org/preview"))

        assertTrue("the hidden window should not load the page", result)
        assertEquals(
            "the browser should open the page",
            Uri.parse("https://example.org/preview"),
            nextStartedActivity()?.data
        )
    }

    @Test
    fun `a new window drops local documents`() {
        val popup = openWindow(configuredSiteView())

        popup.webViewClient.onPageStarted(popup, "blob:https://example.com/0b8f1e2a", null)

        assertNull("no app is asked to open a local document", nextStartedActivity())
    }

    @Test
    fun `a new window opens its page once when both callbacks see the navigation`() {
        val popup = openWindow(configuredSiteView())

        popup.webViewClient.shouldOverrideUrlLoading(popup, request("https://example.org/preview"))
        popup.webViewClient.onPageStarted(popup, "https://example.org/preview", null)

        assertNotNull("the browser should open the page", nextStartedActivity())
        assertNull("the browser should open it only once", nextStartedActivity())
    }

    @Test
    fun `a new window waits past its initial blank document`() {
        val popup = openWindow(configuredSiteView())

        popup.webViewClient.onPageStarted(popup, "about:blank", null)
        popup.webViewClient.shouldOverrideUrlLoading(popup, request("https://example.org/preview"))

        assertEquals(
            "the browser should open the page the window navigates to",
            Uri.parse("https://example.org/preview"),
            nextStartedActivity()?.data
        )
    }

    @Test
    fun `onPageStarted loads the editor again over a page that replaced it`() {
        val siteView = configuredSiteView()
        val webView = siteView.editorWebView
        var unavailable = false
        siteView.setEditorDidBecomeUnavailable { unavailable = true }
        siteView.onEditorLoaded()
        idle()

        // A host's `loadUrl` never passes `shouldOverrideUrlLoading`.
        webView.loadUrl("https://example.com/a-page/")
        webView.webViewClient.onPageStarted(webView, "https://example.com/a-page/", null)
        idle()

        assertEquals(
            "the editor document should replace the page",
            editorUrlFor("https://example.com"),
            shadowOf(webView).lastLoadedUrl
        )
        assertTrue("the host should be told the editor is unavailable", unavailable)
    }

    @Test
    fun `onPageStarted stops loading the editor again over a page that keeps replacing it`() {
        val siteView = configuredSiteView()
        val webView = siteView.editorWebView
        val pageUrl = "https://example.com/a-page/"
        val replaceEditor = {
            webView.loadUrl(pageUrl)
            webView.webViewClient.onPageStarted(webView, pageUrl, null)
            idle()
            shadowOf(webView).lastLoadedUrl
        }
        val editorUrl = editorUrlFor("https://example.com")

        repeat(3) { assertEquals("the editor should recover", editorUrl, replaceEditor()) }

        assertEquals("the editor should stop reloading", pageUrl, replaceEditor())
    }

    @Test
    fun `reloadEditor loads the editor rather than the page that replaced it`() {
        val siteView = configuredSiteView()
        val webView = siteView.editorWebView
        webView.loadUrl("https://example.com/a-page/")

        siteView.reloadEditor()
        idle()

        assertEquals(
            "the editor document should load",
            editorUrlFor("https://example.com"),
            shadowOf(webView).lastLoadedUrl
        )
    }

    @Test
    fun `shouldOverrideUrlLoading opens REST API URLs externally`() {
        // The editor reaches the API by fetch, which never navigates the frame.
        val siteView = configuredSiteView()
        listOf(
            "https://example.com/wp-json/wp/v2/posts",
            "https://example.com/?rest_route=/wp/v2/posts",
            "https://public-api.wordpress.com/wp/v2/sites/123/posts"
        ).forEach { url ->
            assertTrue("$url should open externally", opensExternally(siteView, url))
        }
    }

    @Test
    fun `shouldOverrideUrlLoading opens site pages that resemble the REST API externally`() {
        // WordPress serves each of these with the site's theme and plugins.
        val siteView = configuredSiteView()
        listOf(
            "https://example.com/blog/wp-json/a-post",
            "https://example.com/a-page/?utm_campaign=rest_route=x",
            "https://example.com/wp-json/?rest_route=",
            "https://example.com/a-page/?rest_route=/wp/v2/posts&rest_route=",
            "http://example.com/wp-json/wp/v2/posts"
        ).forEach { url ->
            assertTrue("$url should open externally", opensExternally(siteView, url))
        }
    }

    @Test
    fun `shouldOverrideUrlLoading blocks asset paths over a scheme the asset loader does not serve`() {
        // An https site's assets are served over https alone, so the same path over
        // http goes to the site over the network.
        val result = opensExternally(configuredSiteView(), "http://example.com/assets/index.html")

        assertTrue("an asset path over the other scheme should open externally", result)
    }

    @Test
    fun `onPageStarted injects the configuration into the editor document`() {
        val siteView = configuredSiteView()
        val webView = siteView.editorWebView

        webView.webViewClient.onPageStarted(webView, editorUrlFor("https://example.com"), null)

        assertTrue(
            "the editor document should receive the globals it boots from",
            shadowOf(webView).lastEvaluatedJavascript.orEmpty().contains("window.GBKit")
        )
    }

    @Test
    fun `onPageStarted injects the configuration again when the editor reloads`() {
        val siteView = configuredSiteView()
        val webView = siteView.editorWebView
        webView.webViewClient.onPageStarted(webView, editorUrlFor("https://example.com"), null)
        webView.evaluateJavascript("editor.undo()", null)

        siteView.reloadEditor()
        shadowOf(Looper.getMainLooper()).idle()
        webView.webViewClient.onPageStarted(webView, editorUrlFor("https://example.com"), null)

        assertTrue(
            "the reloaded editor document should receive the globals again",
            shadowOf(webView).lastEvaluatedJavascript.orEmpty().contains("window.GBKit")
        )
    }

    @Test
    fun `onPageStarted injects the configuration into a local http site's editor document`() {
        // A local site serves the editor over http, which the asset scheme must follow.
        val siteView = GutenbergView(
            EditorConfiguration.builder("http://10.0.2.2:8888", "http://10.0.2.2:8888/wp-json/")
                .setAuthHeader("Bearer secret-credential")
                .build(),
            EditorDependencies.empty,
            testScope,
            RuntimeEnvironment.getApplication()
        )
        val webView = siteView.editorWebView

        webView.webViewClient.onPageStarted(webView, editorUrlFor("http://10.0.2.2:8888"), null)

        assertTrue(
            "a local http site's editor document should receive the globals",
            shadowOf(webView).lastEvaluatedJavascript.orEmpty().contains("window.GBKit")
        )
    }

    @Test
    fun `onPageStarted withholds the configuration from a non-editor page`() {
        // Some loads never pass `shouldOverrideUrlLoading` (POST forms, history, a
        // host's `loadUrl`), so a site page can still reach this frame. It must not
        // receive the credential.
        val siteView = configuredSiteView()
        val webView = siteView.editorWebView

        webView.webViewClient.onPageStarted(webView, "https://example.com/wp-json/wp/v2/posts", null)

        // Nothing evaluated at all, so an injection followed by another script still fails.
        assertNull(
            "a non-editor page must not receive the site credential",
            shadowOf(webView).lastEvaluatedJavascript
        )
    }

    @Test
    fun `onPageStarted withholds the configuration from another bundled asset page`() {
        // The asset loader serves every page the host app bundles, not only the editor.
        val siteView = configuredSiteView()
        val webView = siteView.editorWebView

        webView.webViewClient.onPageStarted(webView, "https://example.com/assets/support.html", null)

        assertNull(
            "a bundled page other than the editor must not receive the site credential",
            shadowOf(webView).lastEvaluatedJavascript
        )
    }

    @Test
    fun `onPageStarted withholds the configuration from an asset path the network served`() {
        val siteView = configuredSiteView()
        val webView = siteView.editorWebView

        webView.webViewClient.onPageStarted(webView, "http://example.com/assets/index.html", null)

        assertNull(
            "a network-served page must not receive the site credential",
            shadowOf(webView).lastEvaluatedJavascript
        )
    }
}
