package org.wordpress.gutenberg

import android.os.Looper
import android.view.View
import kotlinx.coroutines.test.TestScope
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

    private fun makeView(): GutenbergView {
        val config = EditorConfiguration
            .builder("https://example.com", "https://example.com/wp-json/")
            .setAuthHeader("Bearer test")
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
    fun `no processor or uploader means no upload server`() {
        val view = makeView()
        try {
            // Nothing provided — uploads should use the default WebView path.
            startLoading(view)
            idle()
            assertNull(
                "with no processor or uploader, no upload server should be started",
                uploadServerOf(view)
            )
        } finally {
            detach(view)
        }
    }

    @Test
    fun `setting a media handler after the page has started loading throws`() {
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
