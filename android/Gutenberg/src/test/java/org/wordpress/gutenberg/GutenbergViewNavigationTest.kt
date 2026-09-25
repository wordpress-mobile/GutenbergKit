package org.wordpress.gutenberg

import android.net.Uri
import android.webkit.WebResourceRequest
import kotlinx.coroutines.test.TestScope
import org.junit.Assert.assertFalse
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
    fun `shouldOverrideUrlLoading blocks a site page whose path merely contains the API root path`() {
        // This site's API root is `/wp-json/`, so `/blog/` here is a page path and
        // WordPress serves it with the site's theme and plugins.
        val result = opensExternally(configuredSiteView(), "https://example.com/blog/wp-json/a-post")

        assertTrue("a page whose path merely contains /wp-json/ should open externally", result)
    }

    @Test
    fun `shouldOverrideUrlLoading allows REST API URLs for a subdirectory install`() {
        // The same path the previous test blocks is the API when the site lives in a
        // subdirectory, so the root the host configured decides, not the characters.
        val siteView = GutenbergView(
            EditorConfiguration.builder("https://example.com/blog", "https://example.com/blog/wp-json/")
                .build(),
            EditorDependencies.empty,
            testScope,
            RuntimeEnvironment.getApplication()
        )

        val result = opensExternally(siteView, "https://example.com/blog/wp-json/a-post")

        assertFalse("a subdirectory install's API URLs should load in the WebView", result)
    }

    @Test
    fun `shouldOverrideUrlLoading blocks a site page whose query merely contains rest_route`() {
        // `rest_route=` appears inside another parameter's value, not as a parameter.
        val result = opensExternally(
            configuredSiteView(),
            "https://example.com/a-page/?utm_campaign=rest_route=x"
        )

        assertTrue("a page whose query merely contains rest_route= should open externally", result)
    }

    @Test
    fun `shouldOverrideUrlLoading blocks a site page with an empty rest_route`() {
        // WordPress ignores an empty route and serves the page with the site's theme.
        listOf(
            "https://example.com/a-page/?rest_route",
            "https://example.com/a-page/?rest_route=",
            "https://example.com/a-page/?rest_route=0",
            // The parameter overrides the route the API root's path would set.
            "https://example.com/wp-json/?rest_route=",
            "https://example.com/wp-json/wp/v2/posts?rest_route=0"
        ).forEach { url ->
            assertTrue("$url should open externally", opensExternally(configuredSiteView(), url))
        }
    }

    @Test
    fun `shouldOverrideUrlLoading blocks site pages when the API root has no path`() {
        // A root of `/` prefixes every path on the site, so it is no evidence that a
        // URL is the API. Such a root is matched by its `rest_route` form alone.
        val siteView = GutenbergView(
            EditorConfiguration.builder("https://example.com", "https://example.com/")
                .build(),
            EditorDependencies.empty,
            testScope,
            RuntimeEnvironment.getApplication()
        )

        val result = opensExternally(siteView, "https://example.com/any-page")

        assertTrue("a pathless API root must not admit the whole site", result)
    }

    @Test
    fun `shouldOverrideUrlLoading blocks site pages under a rest_route API root's path`() {
        // Without pretty permalinks the root is `/index.php?rest_route=/`, and
        // `/index.php` also serves the site's ordinary pages.
        val siteView = GutenbergView(
            EditorConfiguration.builder("https://example.com", "https://example.com/index.php?rest_route=/")
                .build(),
            EditorDependencies.empty,
            testScope,
            RuntimeEnvironment.getApplication()
        )

        val result = opensExternally(siteView, "https://example.com/index.php?p=1")

        assertTrue("a page under a rest_route root's path should open externally", result)
    }

    @Test
    fun `shouldOverrideUrlLoading matches an API root without a trailing slash by whole path segments`() {
        val siteView = GutenbergView(
            EditorConfiguration.builder("https://example.com", "https://example.com/wp-json")
                .build(),
            EditorDependencies.empty,
            testScope,
            RuntimeEnvironment.getApplication()
        )

        assertFalse(
            "the API should load in the WebView",
            opensExternally(siteView, "https://example.com/wp-json/wp/v2/posts")
        )
        assertTrue(
            "a page whose slug merely starts with the root should open externally",
            opensExternally(siteView, "https://example.com/wp-json-tutorial/")
        )
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
