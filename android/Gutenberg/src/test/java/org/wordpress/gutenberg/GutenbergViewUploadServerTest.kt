package org.wordpress.gutenberg

import android.os.Looper
import android.view.View
import kotlinx.coroutines.test.TestScope
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.wordpress.gutenberg.model.EditorConfiguration
import org.wordpress.gutenberg.model.EditorDependencies

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class GutenbergViewUploadServerTest {

    private val testScope = TestScope()

    private fun makeView(authHeader: String = "Bearer test", siteApiRoot: String = "https://example.com/wp-json/"): GutenbergView {
        val config = EditorConfiguration
            .builder("https://example.com", siteApiRoot)
            .setAuthHeader(authHeader)
            .build()
        return GutenbergView(
            config,
            EditorDependencies.empty,
            testScope,
            RuntimeEnvironment.getApplication()
        )
    }

    private fun uploadServerOf(view: GutenbergView): Any? {
        val field = GutenbergView::class.java.getDeclaredField("uploadServer")
        field.isAccessible = true
        return field.get(view)
    }

    /**
     * Invokes the private `onEditorPageStarted` hook (fired from the WebViewClient's
     * `onPageStarted`) to simulate the editor page beginning to load — the point at
     * which the delegate is captured and the upload server starts.
     */
    private fun startLoading(view: GutenbergView) {
        val method = GutenbergView::class.java.getDeclaredMethod("onEditorPageStarted")
        method.isAccessible = true
        method.invoke(view)
    }

    /** Invokes the protected `onDetachedFromWindow` lifecycle callback. */
    private fun detach(view: GutenbergView) {
        val method = View::class.java.getDeclaredMethod("onDetachedFromWindow")
        method.isAccessible = true
        method.invoke(view)
    }

    private fun idle() = shadowOf(Looper.getMainLooper()).idle()

    @Test
    fun `the upload server starts when the page begins loading, capturing the delegate`() {
        val view = makeView()
        try {
            // A delegate provided before load is captured when the page starts.
            view.mediaProcessor = mock(MediaProcessor::class.java)
            startLoading(view)
            idle()
            assertNotNull(
                "a delegate provided before load should bring up the upload server",
                uploadServerOf(view)
            )
        } finally {
            detach(view) // stops the server, releasing the bound socket
        }
    }

    @Test
    fun `no delegate means no upload server`() {
        val view = makeView()
        try {
            // No delegate provided — uploads should use the default WebView path.
            startLoading(view)
            idle()
            assertNull(
                "with no delegate, no upload server should be started",
                uploadServerOf(view)
            )
        } finally {
            detach(view)
        }
    }

    @Test
    fun `an uploader without credentials is a configuration error`() {
        // Falling back would silently drop the uploader, and its media deletes still
        // need the internal media client to reach the configured site. (Matches iOS's
        // precondition.)
        val view = makeView(authHeader = "")
        try {
            view.mediaUploader = mock(MediaUploader::class.java)
            val error = assertThrows(java.lang.reflect.InvocationTargetException::class.java) {
                startLoading(view)
            }
            assertTrue(error.cause is IllegalStateException)
            assertNull("no server should be left behind by the failed start", uploadServerOf(view))
        } finally {
            detach(view)
        }
    }

    @Test
    fun `an uploader without a site root is a configuration error too`() {
        val view = makeView(siteApiRoot = "")
        try {
            view.mediaUploader = mock(MediaUploader::class.java)
            val error = assertThrows(java.lang.reflect.InvocationTargetException::class.java) {
                startLoading(view)
            }
            assertTrue(error.cause is IllegalStateException)
        } finally {
            detach(view)
        }
    }

    @Test
    fun `a processor without credentials just leaves the server down`() {
        // Nothing to deliver through, so nothing to process — uploads fall to the
        // default WebView path rather than trapping.
        val view = makeView(authHeader = "")
        try {
            view.mediaProcessor = mock(MediaProcessor::class.java)
            startLoading(view)
            idle()
            assertNull(
                "a processor with no credentials should not bring up the server",
                uploadServerOf(view)
            )
        } finally {
            detach(view)
        }
    }

    @Test
    fun `setting the delegate after the page has started loading throws`() {
        val view = makeView()
        try {
            startLoading(view)
            idle()
            // The delegate is captured at load; a later assignment is a programmer
            // error and must surface loudly rather than silently do nothing.
            assertThrows(IllegalStateException::class.java) {
                view.mediaProcessor = mock(MediaProcessor::class.java)
            }
        } finally {
            detach(view)
        }
    }

    @Test
    fun `detaching the view stops and clears the upload server`() {
        val view = makeView()
        view.mediaProcessor = mock(MediaProcessor::class.java)
        startLoading(view)
        idle()
        assertNotNull(uploadServerOf(view))

        detach(view)

        assertNull(
            "detaching the view should stop and clear the upload server",
            uploadServerOf(view)
        )
    }
}
