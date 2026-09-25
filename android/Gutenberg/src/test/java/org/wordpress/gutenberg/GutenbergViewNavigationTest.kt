package org.wordpress.gutenberg

import android.net.Uri
import android.webkit.WebResourceRequest
import kotlinx.coroutines.test.TestScope
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

    private fun opensExternally(view: GutenbergView, url: String): Boolean {
        val request = mock(WebResourceRequest::class.java)
        `when`(request.url).thenReturn(Uri.parse(url))
        return view.editorWebView.webViewClient.shouldOverrideUrlLoading(view.editorWebView, request)
    }

    @Test
    fun `shouldOverrideUrlLoading opens REST API URLs externally`() {
        // The editor reaches the API by fetch, which never navigates the frame.
        listOf(
            "https://example.com/wp-json/wp/v2/posts",
            "https://example.com/?rest_route=/wp/v2/posts",
            "https://public-api.wordpress.com/wp/v2/sites/123/posts"
        ).forEach { url ->
            assertTrue("$url should open externally", opensExternally(configuredSiteView(), url))
        }
    }

    @Test
    fun `shouldOverrideUrlLoading opens site pages that resemble the REST API externally`() {
        // WordPress serves each of these with the site's theme and plugins.
        listOf(
            "https://example.com/blog/wp-json/a-post",
            "https://example.com/a-page/?utm_campaign=rest_route=x",
            "https://example.com/wp-json/?rest_route=",
            "https://example.com/a-page/?rest_route=/wp/v2/posts&rest_route=",
            "http://example.com/wp-json/wp/v2/posts"
        ).forEach { url ->
            assertTrue("$url should open externally", opensExternally(configuredSiteView(), url))
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
    fun `onPageStarted withholds the configuration from a non-editor page`() {
        // `shouldOverrideUrlLoading` admits some site URLs into this frame, and on
        // Android the editor shares an origin with the site, so a page served by the
        // site's theme and plugins can load here. It must not receive the credential.
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
