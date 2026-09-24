package org.wordpress.gutenberg

import kotlinx.coroutines.test.TestScope
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
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

        assertFalse(
            "a non-editor page must not receive the site credential",
            shadowOf(webView).lastEvaluatedJavascript.orEmpty().contains("secret-credential")
        )
    }
}
