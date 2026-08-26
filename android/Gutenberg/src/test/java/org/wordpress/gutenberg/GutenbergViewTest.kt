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
        gutenbergView.editorWebView.webChromeClient?.onShowFileChooser(
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
        gutenbergView.editorWebView.webChromeClient?.onShowFileChooser(
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
        gutenbergView.editorWebView.webChromeClient?.onShowFileChooser(
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
        gutenbergView.editorWebView.webChromeClient?.onShowFileChooser(
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
        val userAgent = gutenbergView.editorWebView.settings.userAgentString
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

        val result = siteView.editorWebView.webViewClient.shouldOverrideUrlLoading(siteView.editorWebView, request)
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

        val result = siteView.editorWebView.webViewClient.shouldOverrideUrlLoading(siteView.editorWebView, request)
        assertTrue("Non-asset URLs on the site domain should open externally", result)
    }

    @Test
    fun `shouldOverrideUrlLoading allows asset path URLs when the site URL has a port`() {
        val siteView = GutenbergView(
            EditorConfiguration.builder("http://10.0.2.2:8888", "http://10.0.2.2:8888/wp-json/")
                .build(),
            EditorDependencies.empty,
            testScope,
            RuntimeEnvironment.getApplication()
        )

        val request = mock(WebResourceRequest::class.java)
        `when`(request.url).thenReturn(Uri.parse("http://10.0.2.2:8888/assets/index.html"))

        val result = siteView.editorWebView.webViewClient.shouldOverrideUrlLoading(siteView.editorWebView, request)
        assertFalse(
            "Asset URLs on the site's authority should load in the WebView so the editor stays same-origin",
            result
        )
    }

    @Test
    fun `shouldOverrideUrlLoading blocks asset path URLs that drop the site's port`() {
        val siteView = GutenbergView(
            EditorConfiguration.builder("http://10.0.2.2:8888", "http://10.0.2.2:8888/wp-json/")
                .build(),
            EditorDependencies.empty,
            testScope,
            RuntimeEnvironment.getApplication()
        )

        val request = mock(WebResourceRequest::class.java)
        `when`(request.url).thenReturn(Uri.parse("http://10.0.2.2/assets/index.html"))

        val result = siteView.editorWebView.webViewClient.shouldOverrideUrlLoading(siteView.editorWebView, request)
        assertTrue(
            "A portless URL is a different origin than the site and must not be treated as an asset URL",
            result
        )
    }

    // ===== originAuthority =====

    @Test
    fun `originAuthority keeps a non-default port`() {
        assertEquals("10.0.2.2:8888", GutenbergView.originAuthority("http://10.0.2.2:8888"))
        assertEquals("example.com:8443", GutenbergView.originAuthority("https://example.com:8443"))
    }

    @Test
    fun `originAuthority drops an explicit default port`() {
        // Chromium canonicalizes these away before the URL reaches the WebViewClient,
        // so keeping them would leave the asset loader unable to match its own document.
        assertEquals("example.com", GutenbergView.originAuthority("https://example.com:443"))
        assertEquals("example.com", GutenbergView.originAuthority("http://example.com:80"))
    }

    @Test
    fun `originAuthority omits a port that is absent`() {
        assertEquals("example.com", GutenbergView.originAuthority("https://example.com"))
    }

    @Test
    fun `originAuthority strips userinfo`() {
        // Credentials are also removed during canonicalization.
        assertEquals("example.com", GutenbergView.originAuthority("https://user:pass@example.com"))
        assertEquals(
            "example.com:8443",
            GutenbergView.originAuthority("https://user:pass@example.com:8443")
        )
    }

    @Test
    fun `originAuthority preserves an IPv6 authority verbatim`() {
        // `Uri` does not split a bracketed IPv6 literal into host/port, so the
        // authority is used as written rather than being rebuilt.
        assertEquals("[::1]:8888", GutenbergView.originAuthority("http://[::1]:8888"))
        assertEquals("[::1]", GutenbergView.originAuthority("http://[::1]"))
        assertEquals(
            "[2001:db8::1]:8443",
            GutenbergView.originAuthority("https://[2001:db8::1]:8443")
        )
    }

    @Test
    fun `originAuthority returns null when the URL has no host`() {
        assertEquals(null, GutenbergView.originAuthority(""))
        assertEquals(null, GutenbergView.originAuthority("not a url"))
    }

    // ===== REST API navigation =====

    @Test
    fun `shouldOverrideUrlLoading allows REST API URLs on the site's API root`() {
        // Callers pass a full API root with a path, e.g. WordPress-Android's
        // `site.wpApiRestUrl ?: "${site.url}/wp-json/"`.
        val siteView = GutenbergView(
            EditorConfiguration.builder("https://example.com", "https://example.com/wp-json/")
                .build(),
            EditorDependencies.empty,
            testScope,
            RuntimeEnvironment.getApplication()
        )

        val request = mock(WebResourceRequest::class.java)
        `when`(request.url).thenReturn(Uri.parse("https://example.com/wp-json/wp/v2/posts"))

        val result = siteView.editorWebView.webViewClient.shouldOverrideUrlLoading(siteView.editorWebView, request)
        assertFalse("REST API URLs on the site's API root should load in the WebView", result)
    }

    @Test
    fun `shouldOverrideUrlLoading allows REST API URLs for a rest_route API root`() {
        val siteView = GutenbergView(
            EditorConfiguration.builder(
                "https://example.com",
                "https://example.com/index.php?rest_route=/"
            ).build(),
            EditorDependencies.empty,
            testScope,
            RuntimeEnvironment.getApplication()
        )

        val request = mock(WebResourceRequest::class.java)
        `when`(request.url).thenReturn(
            Uri.parse("https://example.com/index.php?rest_route=/wp/v2/posts")
        )

        val result = siteView.editorWebView.webViewClient.shouldOverrideUrlLoading(siteView.editorWebView, request)
        assertFalse("rest_route REST API URLs should load in the WebView", result)
    }

    @Test
    fun `shouldOverrideUrlLoading blocks REST API URLs on a different host`() {
        val siteView = GutenbergView(
            EditorConfiguration.builder("https://example.com", "https://example.com/wp-json/")
                .build(),
            EditorDependencies.empty,
            testScope,
            RuntimeEnvironment.getApplication()
        )

        val request = mock(WebResourceRequest::class.java)
        `when`(request.url).thenReturn(Uri.parse("https://other.example.net/wp-json/wp/v2/posts"))

        val result = siteView.editorWebView.webViewClient.shouldOverrideUrlLoading(siteView.editorWebView, request)
        assertTrue("REST API URLs on another host should open externally", result)
    }

    @Test
    fun `shouldOverrideUrlLoading allows REST API URLs when the API root has a port`() {
        val siteView = GutenbergView(
            EditorConfiguration.builder("http://10.0.2.2:8888", "http://10.0.2.2:8888/wp-json/")
                .build(),
            EditorDependencies.empty,
            testScope,
            RuntimeEnvironment.getApplication()
        )

        val request = mock(WebResourceRequest::class.java)
        `when`(request.url).thenReturn(Uri.parse("http://10.0.2.2:8888/wp-json/wp/v2/posts"))

        val result = siteView.editorWebView.webViewClient.shouldOverrideUrlLoading(siteView.editorWebView, request)
        assertFalse("REST API URLs on a port-bearing API root should load in the WebView", result)
    }

    @Test
    fun `shouldOverrideUrlLoading allows asset URLs when the site URL has an explicit default port`() {
        val siteView = GutenbergView(
            EditorConfiguration.builder("https://example.com:443", "https://example.com:443/wp-json/")
                .build(),
            EditorDependencies.empty,
            testScope,
            RuntimeEnvironment.getApplication()
        )

        val request = mock(WebResourceRequest::class.java)
        // Chromium canonicalizes `:443` away, so this is the URL the client actually sees.
        `when`(request.url).thenReturn(Uri.parse("https://example.com/assets/index.html"))

        val result = siteView.editorWebView.webViewClient.shouldOverrideUrlLoading(siteView.editorWebView, request)
        assertFalse(
            "An explicit default port in the site URL must still match the canonicalized request",
            result
        )
    }
}
