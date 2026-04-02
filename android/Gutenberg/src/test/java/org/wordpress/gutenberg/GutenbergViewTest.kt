package org.wordpress.gutenberg

import android.content.Intent
import android.net.Uri
import android.os.Looper
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import kotlinx.coroutines.test.TestScope
import org.junit.Before
import org.junit.Test
import org.junit.Rule
import org.junit.runner.RunWith
import org.mockito.Mock
import org.mockito.Mockito.mock
import org.mockito.Mockito.`when`
import org.mockito.MockitoAnnotations
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.wordpress.gutenberg.model.EditorConfiguration
import org.wordpress.gutenberg.model.EditorDependencies

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

    val testScope = TestScope() // Creates a StandardTestDispatcher

    @Before
    fun setup() {
        MockitoAnnotations.openMocks(this)

        gutenbergView = GutenbergView(
            EditorConfiguration.bundled(),
            EditorDependencies.empty,
            testScope,
            RuntimeEnvironment.getApplication()
        )
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
        assertTrue("Intent action should be ACTION_OPEN_DOCUMENT",
            capturedIntent?.action == Intent.ACTION_OPEN_DOCUMENT)
        assertTrue("Intent should have CATEGORY_OPENABLE",
            capturedIntent?.hasCategory(Intent.CATEGORY_OPENABLE) == true)
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
        assertTrue("Intent action should be ACTION_OPEN_DOCUMENT",
            capturedIntent?.action == Intent.ACTION_OPEN_DOCUMENT)
        assertTrue("Intent should allow multiple selection",
            capturedIntent?.getBooleanExtra(Intent.EXTRA_ALLOW_MULTIPLE, false) == true)
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
    fun `GutenbergView sets custom user agent with GutenbergKit identifier`() {
        // The user agent is set during construction, so we can verify it on the gutenbergView
        // that was already set up in the @Before method

        // Then
        val userAgent = gutenbergView.settings.userAgentString
        assertTrue("User agent should contain GutenbergKit identifier",
            userAgent.contains("GutenbergKit/"))
        assertTrue("User agent should contain version number",
            userAgent.contains("GutenbergKit/${GutenbergKitVersion.VERSION}"))
    }

    @Test
    fun `shouldOverrideUrlLoading allows asset path URLs on site domain`() {
        val siteView = GutenbergView(
            EditorConfiguration.builder("https://example.com", "https://example.com/wp-json/")
                .build(),
            EditorDependencies.empty,
            testScope,
            RuntimeEnvironment.getApplication()
        )

        val request = mock(WebResourceRequest::class.java)
        `when`(request.url).thenReturn(Uri.parse("https://example.com/assets/index.html"))

        val result = siteView.webViewClient.shouldOverrideUrlLoading(siteView, request)
        assertFalse("Asset path URLs on the site domain should load in the WebView", result)
    }

    @Test
    fun `shouldOverrideUrlLoading blocks non-asset URLs on site domain`() {
        val siteView = GutenbergView(
            EditorConfiguration.builder("https://example.com", "https://example.com/wp-json/")
                .build(),
            EditorDependencies.empty,
            testScope,
            RuntimeEnvironment.getApplication()
        )

        val request = mock(WebResourceRequest::class.java)
        `when`(request.url).thenReturn(Uri.parse("https://example.com/some-page"))

        val result = siteView.webViewClient.shouldOverrideUrlLoading(siteView, request)
        assertTrue("Non-asset URLs on the site domain should open externally", result)
    }
}
