package org.wordpress.gutenberg

import android.content.Intent
import android.net.Uri
import android.os.Looper
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebView
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mock
import org.mockito.Mockito.`when`
import org.mockito.MockitoAnnotations
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class GutenbergViewTest {
    @Mock
    private lateinit var mockWebView: WebView

    @Mock
    private lateinit var mockFilePathCallback: ValueCallback<Array<Uri?>?>

    @Mock
    private lateinit var mockFileChooserParams: WebChromeClient.FileChooserParams

    private lateinit var gutenbergView: GutenbergView

    @Before
    fun setup() {
        MockitoAnnotations.openMocks(this)
        gutenbergView = GutenbergView(RuntimeEnvironment.getApplication())
        gutenbergView.initializeWebView()
    }

    @Test
    fun `onShowFileChooser sets up file chooser with single file selection`() {
        // Given
        val latch = CountDownLatch(1)
        var capturedIntent: Intent? = null

        gutenbergView.setOnFileChooserRequestedListener { intent, _ ->
            capturedIntent = intent
            latch.countDown()
        }

        // When
        gutenbergView.webChromeClient?.onShowFileChooser(
            mockWebView,
            mockFilePathCallback,
            mockFileChooserParams
        )

        // Process any pending runnables
        shadowOf(Looper.getMainLooper()).runToEndOfTasks()

        // Wait for the callback to be executed
        latch.await(1, TimeUnit.SECONDS)

        // Then
        assertTrue("Intent should not be null", capturedIntent != null)
        assertTrue("Intent should be a chooser", capturedIntent?.action == Intent.ACTION_CHOOSER)

        // Get the original intent from the chooser
        val originalIntent = capturedIntent?.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
        assertTrue("Original intent should not be null", originalIntent != null)
        assertTrue("Original intent action should be ACTION_GET_CONTENT",
            originalIntent?.action == Intent.ACTION_GET_CONTENT)
        assertTrue("Original intent should have CATEGORY_OPENABLE",
            originalIntent?.hasCategory(Intent.CATEGORY_OPENABLE) == true)
        assertEquals("Pick image request code should be 1",
            1, gutenbergView.pickImageRequestCode)
    }

    @Test
    fun `onShowFileChooser sets up file chooser with multiple file selection`() {
        // Given
        val latch = CountDownLatch(1)
        var capturedIntent: Intent? = null

        gutenbergView.setOnFileChooserRequestedListener { intent, _ ->
            capturedIntent = intent
            latch.countDown()
        }

        // When
        `when`(mockFileChooserParams.mode).thenReturn(WebChromeClient.FileChooserParams.MODE_OPEN_MULTIPLE)
        gutenbergView.webChromeClient?.onShowFileChooser(
            mockWebView,
            mockFilePathCallback,
            mockFileChooserParams
        )

        // Process any pending runnables
        shadowOf(Looper.getMainLooper()).runToEndOfTasks()

        // Wait for the callback to be executed
        latch.await(1, TimeUnit.SECONDS)

        // Then
        assertTrue("Intent should not be null", capturedIntent != null)
        assertTrue("Intent should be a chooser", capturedIntent?.action == Intent.ACTION_CHOOSER)

        // Get the original intent from the chooser
        val originalIntent = capturedIntent?.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
        assertTrue("Original intent should not be null", originalIntent != null)
        assertTrue("Original intent should allow multiple selection",
            originalIntent?.getBooleanExtra(Intent.EXTRA_ALLOW_MULTIPLE, false) == true)
    }

    @Test
    fun `onShowFileChooser stores file path callback`() {
        // When
        gutenbergView.webChromeClient?.onShowFileChooser(
            mockWebView,
            mockFilePathCallback,
            mockFileChooserParams
        )

        // Then
        assertEquals("File path callback should be stored",
            mockFilePathCallback, gutenbergView.filePathCallback)
    }

    @Test
    fun `resetFilePathCallback clears the callback`() {
        // Given
        gutenbergView.webChromeClient?.onShowFileChooser(
            mockWebView,
            mockFilePathCallback,
            mockFileChooserParams
        )

        // When
        gutenbergView.resetFilePathCallback()

        // Then
        assertEquals("File path callback should be null after reset",
            null, gutenbergView.filePathCallback)
    }

    @Test
    fun `initializeWebView sets custom user agent with GutenbergKit identifier`() {
        // Given
        val gutenbergView = GutenbergView(RuntimeEnvironment.getApplication())

        // When
        gutenbergView.initializeWebView()

        // Then
        val userAgent = gutenbergView.settings.userAgentString
        assertTrue("User agent should contain GutenbergKit identifier",
            userAgent.contains("GutenbergKit/"))
        assertTrue("User agent should contain version number",
            userAgent.contains("GutenbergKit/${GutenbergKit.VERSION}"))
    }
}
