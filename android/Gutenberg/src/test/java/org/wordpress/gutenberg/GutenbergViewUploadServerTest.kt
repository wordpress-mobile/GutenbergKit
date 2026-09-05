package org.wordpress.gutenberg

import android.os.Looper
import android.view.View
import kotlinx.coroutines.test.TestScope
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
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
     * which the processor is captured and the upload server starts.
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
    fun `the upload server starts when the page begins loading, capturing the processor`() {
        val view = makeView()
        try {
            // A processor provided before load is captured when the page starts.
            view.mediaProcessor = mock(MediaProcessor::class.java)
            startLoading(view)
            idle()
            assertNotNull(
                "a processor provided before load should bring up the upload server",
                uploadServerOf(view)
            )
        } finally {
            detach(view) // stops the server, releasing the bound socket
        }
    }

    @Test
    fun `no processor means no upload server`() {
        val view = makeView()
        try {
            // No processor provided — uploads should use the default WebView path.
            startLoading(view)
            idle()
            assertNull(
                "with no processor, no upload server should be started",
                uploadServerOf(view)
            )
        } finally {
            detach(view)
        }
    }

    @Test
    fun `the upload server starts for an uploader with no processor`() {
        val view = makeView()
        try {
            // An uploader alone must bring the server up: it is the only route the
            // editor has to the host's upload stack. Without this, `startUploadServer`
            // could drop the `mediaUploader` clause from its gate and stay green.
            view.mediaUploader = mock(MediaUploader::class.java)
            startLoading(view)
            idle()
            assertNotNull(
                "an uploader provided before load should bring up the upload server",
                uploadServerOf(view)
            )
        } finally {
            detach(view) // stops the server, releasing the bound socket
        }
    }

    @Test
    fun `setting the uploader after the page has started loading throws`() {
        val view = makeView()
        try {
            startLoading(view)
            idle()
            assertThrows(IllegalStateException::class.java) {
                view.mediaUploader = mock(MediaUploader::class.java)
            }
        } finally {
            detach(view)
        }
    }

    @Test
    fun `an uploader without credentials fails at assignment`() {
        // Falling back would silently drop the uploader, and its media deletes still
        // need the internal media client to reach the configured site. It fails in the
        // setter rather than at page load so the stack trace names the host's own line.
        val view = makeView(authHeader = "")
        try {
            assertThrows(IllegalStateException::class.java) {
                view.mediaUploader = mock(MediaUploader::class.java)
            }
            // The failed assignment left nothing behind, so loading still works —
            // it just falls to the default WebView path.
            startLoading(view)
            idle()
            assertNull("no server should be left behind by the rejected uploader", uploadServerOf(view))
        } finally {
            detach(view)
        }
    }

    @Test
    fun `an uploader without a site root fails at assignment too`() {
        val view = makeView(siteApiRoot = "")
        try {
            assertThrows(IllegalStateException::class.java) {
                view.mediaUploader = mock(MediaUploader::class.java)
            }
        } finally {
            detach(view)
        }
    }

    @Test
    fun `an uploader with a scheme-less site root fails at assignment`() {
        // What a user types when asked for their site address. This used to pass the
        // isEmpty() check and start a server whose every relayed delete threw
        // IllegalArgumentException out of OkHttp — while the same config trapped on
        // iOS, whose check has always required an absolute root.
        val view = makeView(siteApiRoot = "example.com/wp-json/")
        try {
            assertThrows(IllegalStateException::class.java) {
                view.mediaUploader = mock(MediaUploader::class.java)
            }
        } finally {
            detach(view)
        }
    }

    @Test
    fun `a processor with a scheme-less site root leaves the server down`() {
        // Same root, no uploader: not an error, but the server must still stay down
        // rather than come up and fail every request. (Matches iOS.)
        val view = makeView(siteApiRoot = "example.com/wp-json/")
        try {
            view.mediaProcessor = mock(MediaProcessor::class.java)
            startLoading(view)
            idle()
            assertNull(
                "a scheme-less site root should not bring up the server",
                uploadServerOf(view)
            )
        } finally {
            detach(view)
        }
    }

    @Test
    fun `an uploader with credentials assigns cleanly`() {
        val view = makeView()
        try {
            val uploader = mock(MediaUploader::class.java)
            view.mediaUploader = uploader
            assertEquals(uploader, view.mediaUploader)
        } finally {
            detach(view)
        }
    }

    @Test
    fun `a processor without credentials assigns cleanly`() {
        // Only an uploader requires credentials — a processor has nothing to deliver
        // through, so assigning one with no credentials is not an error.
        val view = makeView(authHeader = "")
        try {
            val processor = mock(MediaProcessor::class.java)
            view.mediaProcessor = processor
            assertEquals(processor, view.mediaProcessor)
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
    fun `setting the processor after the page has started loading throws`() {
        val view = makeView()
        try {
            startLoading(view)
            idle()
            // The processor is captured at load; a later assignment is a programmer
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
