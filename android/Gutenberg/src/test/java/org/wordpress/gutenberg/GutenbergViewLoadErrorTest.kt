package org.wordpress.gutenberg

import android.net.Uri
import android.os.Looper
import android.view.View
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import kotlinx.coroutines.test.TestScope
import org.junit.Assert.assertEquals
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

/** How a failure to load the editor document reaches the user instead of an endless spinner. */
@RunWith(RobolectricTestRunner::class)
class GutenbergViewLoadErrorTest {

    private val testScope = TestScope()

    private val devServer = Uri.parse("http://10.0.2.2:5173/")

    private fun siteView() = GutenbergView(
        EditorConfiguration.builder("https://example.com", "https://example.com/wp-json/").build(),
        EditorDependencies.empty,
        testScope,
        RuntimeEnvironment.getApplication()
    )

    /** The editor document, mirroring the fallback in `loadEditor`. */
    private val editorUrl = BuildConfig.GUTENBERG_EDITOR_URL
        .ifEmpty { "https://example.com/assets/index.html" }

    private fun failMainFrameLoad(view: GutenbergView, url: String) {
        val request = mock(WebResourceRequest::class.java)
        `when`(request.url).thenReturn(Uri.parse(url))
        `when`(request.isForMainFrame).thenReturn(true)
        val error = mock(WebResourceError::class.java)
        `when`(error.description).thenReturn("net::ERR_CONNECTION_REFUSED")
        view.editorWebView.webViewClient.onReceivedError(view.editorWebView, request, error)
        shadowOf(Looper.getMainLooper()).idle()
    }

    @Test
    fun `a failed editor document load replaces the spinner with the error view`() {
        val view = siteView()
        shadowOf(Looper.getMainLooper()).idle()

        failMainFrameLoad(view, editorUrl)

        assertEquals(
            "the failed editor must give way to the error view",
            View.INVISIBLE,
            view.editorWebView.visibility
        )
    }

    @Test
    fun `a failed load of another page leaves the editor as it is`() {
        val view = siteView()
        shadowOf(Looper.getMainLooper()).idle()

        failMainFrameLoad(view, "https://example.com/wp-json/wp/v2/posts")

        assertEquals(View.VISIBLE, view.editorWebView.visibility)
    }

    @Test
    fun `editorLoadErrorMessage suggests starting a refused dev server`() {
        val message = GutenbergView.editorLoadErrorMessage(devServer, "net::ERR_CONNECTION_REFUSED", true)

        assertTrue(message.orEmpty().contains("make serve-dev"))
    }

    @Test
    fun `editorLoadErrorMessage suggests allowing cleartext to the dev server's host`() {
        val message = GutenbergView.editorLoadErrorMessage(devServer, "net::ERR_CLEARTEXT_NOT_PERMITTED", true)

        assertTrue(message.orEmpty().contains("cleartext traffic to 10.0.2.2"))
    }

    @Test
    fun `editorLoadErrorMessage suggests checking reachability of an unreachable host`() {
        val message = GutenbergView.editorLoadErrorMessage(devServer, "net::ERR_CONNECTION_TIMED_OUT", true)

        assertTrue(message.orEmpty().contains("can reach 10.0.2.2"))
    }

    @Test
    fun `editorLoadErrorMessage suggests checking reachability of a disconnected device`() {
        val message = GutenbergView.editorLoadErrorMessage(devServer, "net::ERR_INTERNET_DISCONNECTED", true)

        assertTrue(message.orEmpty().contains("can reach 10.0.2.2"))
    }

    @Test
    fun `editorLoadErrorMessage leaves the bundled editor to the localized message`() {
        assertNull(
            GutenbergView.editorLoadErrorMessage(
                Uri.parse("https://example.com/assets/index.html"),
                "net::ERR_FAILED",
                false
            )
        )
    }
}
