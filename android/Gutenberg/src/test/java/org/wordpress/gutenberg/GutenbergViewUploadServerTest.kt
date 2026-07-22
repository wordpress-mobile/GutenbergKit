package org.wordpress.gutenberg

import android.os.Looper
import android.view.View
import kotlinx.coroutines.test.TestScope
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
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

    /** Invokes the protected `onDetachedFromWindow` lifecycle callback. */
    private fun detach(view: GutenbergView) {
        val method = View::class.java.getDeclaredMethod("onDetachedFromWindow")
        method.isAccessible = true
        method.invoke(view)
    }

    private fun idle() = shadowOf(Looper.getMainLooper()).idle()

    @Test
    fun `setting the delegate on a live view starts the upload server (baseline)`() {
        val view = makeView()
        try {
            view.mediaUploadDelegate = mock(MediaUploadDelegate::class.java)
            idle()
            assertNotNull(
                "a live view with a valid config should start the upload server",
                uploadServerOf(view)
            )
        } finally {
            // Release the bound socket.
            view.mediaUploadDelegate = null
        }
    }

    @Test
    fun `setting the delegate after detach does not start a leaked server`() {
        val view = makeView()

        // onDetachedFromWindow stops any server and won't fire again.
        detach(view)

        // A delegate assigned after detach must not resurrect a server that nothing
        // would ever stop (bound socket + accept-loop coroutine).
        view.mediaUploadDelegate = mock(MediaUploadDelegate::class.java)
        idle()

        assertNull(
            "no upload server should be started once the view is detached",
            uploadServerOf(view)
        )
    }
}
