package org.wordpress.gutenberg

import android.content.Intent
import android.net.Uri
import android.os.Looper
import android.view.View
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
import org.robolectric.shadows.ShadowDialog
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.wordpress.gutenberg.model.EditorConfiguration
import org.wordpress.gutenberg.model.EditorDependencies

@RunWith(RobolectricTestRunner::class)
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

    // ===== isDevServerUrl =====

    @Test
    fun `isDevServerUrl matches the dev server's host and port`() {
        assertTrue(
            GutenbergView.isDevServerUrl(
                Uri.parse("http://10.0.2.2:5173/src/index.html"),
                "http://10.0.2.2:5173/"
            )
        )
    }

    @Test
    fun `isDevServerUrl rejects another port on the dev server's host`() {
        assertFalse(
            GutenbergView.isDevServerUrl(Uri.parse("http://10.0.2.2:8888/"), "http://10.0.2.2:5173/")
        )
        assertFalse(
            GutenbergView.isDevServerUrl(Uri.parse("http://10.0.2.2/"), "http://10.0.2.2:5173/")
        )
    }

    @Test
    fun `isDevServerUrl matches a dev server URL written with its default port`() {
        // Chromium drops a default port before the URL reaches the WebViewClient.
        assertTrue(
            GutenbergView.isDevServerUrl(Uri.parse("http://localhost/"), "http://localhost:80/")
        )
    }

    @Test
    fun `isDevServerUrl rejects every URL when no dev server is configured`() {
        assertFalse(GutenbergView.isDevServerUrl(Uri.parse("http://localhost:5173/"), ""))
    }

    @Test
    fun `isDevServerUrl rejects host-less URLs when the dev server URL has no host`() {
        // Without a scheme, the dev server URL has no authority, and neither do these.
        assertFalse(GutenbergView.isDevServerUrl(Uri.parse("mailto:a@example.com"), "10.0.2.2:5173"))
        assertFalse(GutenbergView.isDevServerUrl(Uri.parse("tel:5551234"), "10.0.2.2:5173"))
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

    @Test
    fun `getTitleAndContent reports an error when the editor has not loaded`() {
        // The fixture has never received onEditorLoaded, so the read cannot proceed.
        val callback = RecordingTitleAndContentCallback()

        gutenbergView.getTitleAndContent("original content", callback)
        assertTrue("the error is posted to the main thread, not reported inline", callback.errors.isEmpty())
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals("the host is told the read failed", 1, callback.errors.size)
        assertTrue("because the editor is not ready", callback.errors.first() is EditorNotReadyException)
        assertEquals("no content is reported", 0, callback.results)
    }

    @Test
    fun `getTitleAndContent reports its queued error when the view detaches first`() {
        val callback = RecordingTitleAndContentCallback()

        gutenbergView.getTitleAndContent("original content", callback)
        // Detaching clears the main thread queue holding the error.
        shadowOf(gutenbergView).callOnDetachedFromWindow()
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals("the host is told the read failed, once", 1, callback.errors.size)
        assertTrue("because the editor is not ready", callback.errors.first() is EditorNotReadyException)
        assertEquals("no content is reported", 0, callback.results)
    }

    @Test
    fun `getTitleAndContent reports an error when the view detaches before the web view answers`() {
        gutenbergView.onEditorLoaded()
        shadowOf(Looper.getMainLooper()).idle()
        val callback = RecordingTitleAndContentCallback()

        gutenbergView.getTitleAndContent("original content", callback)
        // Robolectric's shadow WebView never invokes the ValueCallback, like a web
        // view destroyed mid-read.
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue("the read is still waiting", callback.errors.isEmpty())

        shadowOf(gutenbergView).callOnDetachedFromWindow()

        assertEquals("the host is told the read failed", 1, callback.errors.size)
        assertTrue("because the editor is not ready", callback.errors.first() is EditorNotReadyException)
        assertEquals("no content is reported", 0, callback.results)
    }

    @Test
    fun `getTitleAndContent reports an error when called after the view detaches`() {
        gutenbergView.onEditorLoaded()
        shadowOf(Looper.getMainLooper()).idle()
        shadowOf(gutenbergView).callOnDetachedFromWindow()
        val callback = RecordingTitleAndContentCallback()

        gutenbergView.getTitleAndContent("original content", callback)
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals("the host is told the read failed", 1, callback.errors.size)
        assertTrue("because the editor is not ready", callback.errors.first() is EditorNotReadyException)
    }

    @Test
    fun `onEditorUnavailable notifies the listener`() {
        var notified: GutenbergView? = null
        gutenbergView.setEditorDidBecomeUnavailable { view -> notified = view }

        gutenbergView.onEditorUnavailable()
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals(gutenbergView, notified)
    }

    @Test
    fun `onEditorUnavailable stops content reads from reaching the web view`() {
        gutenbergView.onEditorLoaded()
        shadowOf(Looper.getMainLooper()).idle()

        gutenbergView.onEditorUnavailable()
        shadowOf(Looper.getMainLooper()).idle()

        val shadowWebView = shadowOf(gutenbergView.editorWebView)
        val lastEvaluated = shadowWebView.lastEvaluatedJavascript
        val callback = RecordingTitleAndContentCallback()

        gutenbergView.getTitleAndContent("original content", callback)
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals(
            "a crashed editor must not be asked for content",
            lastEvaluated,
            shadowWebView.lastEvaluatedJavascript
        )
        assertTrue("the host is told the editor is not ready", callback.errors.single() is EditorNotReadyException)
    }

    private class RecordingTitleAndContentCallback : GutenbergView.TitleAndContentCallback {
        val errors = mutableListOf<Throwable>()
        var results = 0

        override fun onResult(title: CharSequence, content: CharSequence) {
            results++
        }

        override fun onError(error: Throwable) {
            errors += error
        }
    }

    @Test
    fun `onEditorUnavailable stops history commands from reaching the web view`() {
        gutenbergView.onEditorLoaded()
        shadowOf(Looper.getMainLooper()).idle()

        gutenbergView.onEditorUnavailable()
        shadowOf(Looper.getMainLooper()).idle()

        val shadowWebView = shadowOf(gutenbergView.editorWebView)
        val lastEvaluated = shadowWebView.lastEvaluatedJavascript

        gutenbergView.undo()
        gutenbergView.redo()
        gutenbergView.dismissTopModal()
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals(
            "a crashed editor must not be sent commands its bridge can no longer answer",
            lastEvaluated,
            shadowWebView.lastEvaluatedJavascript
        )
    }

    @Test
    fun `onEditorUnavailable stops content changes from reaching the web view`() {
        gutenbergView.onEditorLoaded()
        shadowOf(Looper.getMainLooper()).idle()

        gutenbergView.onEditorUnavailable()
        shadowOf(Looper.getMainLooper()).idle()

        val shadowWebView = shadowOf(gutenbergView.editorWebView)
        val lastEvaluated = shadowWebView.lastEvaluatedJavascript

        gutenbergView.setTitle("Title")
        gutenbergView.setContent("<p>Content</p>")
        gutenbergView.appendTextAtCursor("Text")
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals(
            "a crashed editor must not be sent content its bridge can no longer apply",
            lastEvaluated,
            shadowWebView.lastEvaluatedJavascript
        )
    }

    @Test
    fun `setTitle reaches a loaded editor`() {
        gutenbergView.onEditorLoaded()
        shadowOf(Looper.getMainLooper()).idle()

        gutenbergView.setTitle("Title")
        shadowOf(Looper.getMainLooper()).idle()

        assertTrue(
            "a loaded editor must receive the title",
            shadowOf(gutenbergView.editorWebView).lastEvaluatedJavascript?.startsWith("editor.setTitle(") == true
        )
    }

    @Test
    fun `onEditorUnavailable dismisses the block inserter`() {
        gutenbergView.onEditorLoaded()
        gutenbergView.showBlockInserter("{}")
        shadowOf(Looper.getMainLooper()).idle()
        val inserter = ShadowDialog.getLatestDialog()
        assertTrue("the inserter is open before the crash", inserter.isShowing)

        gutenbergView.onEditorUnavailable()
        shadowOf(Looper.getMainLooper()).idle()

        assertFalse("picks from the inserter can no longer reach the editor", inserter.isShowing)
    }

    @Test
    fun `onEditorUnavailable hides the web view until the editor reloads`() {
        gutenbergView.onEditorLoaded()
        shadowOf(Looper.getMainLooper()).idle()

        gutenbergView.onEditorUnavailable()
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals(
            "the crashed editor must not receive touches or TalkBack focus",
            View.INVISIBLE,
            gutenbergView.editorWebView.visibility
        )

        gutenbergView.reloadEditor()
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals(
            "the reloading editor must be visible so it can render and signal readiness",
            View.VISIBLE,
            gutenbergView.editorWebView.visibility
        )
    }

    @Test
    fun `reloadEditor stops history commands until the editor loads again`() {
        gutenbergView.onEditorLoaded()
        shadowOf(Looper.getMainLooper()).idle()

        gutenbergView.reloadEditor()
        shadowOf(Looper.getMainLooper()).idle()

        val shadowWebView = shadowOf(gutenbergView.editorWebView)
        val lastEvaluated = shadowWebView.lastEvaluatedJavascript

        gutenbergView.undo()
        gutenbergView.redo()
        gutenbergView.dismissTopModal()
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals(
            "a reloading editor must not be sent commands before it loads again",
            lastEvaluated,
            shadowWebView.lastEvaluatedJavascript
        )
    }

    @Test
    fun `a reloaded page is not ready until it loads even if the replaced page loads late`() {
        var available = false
        gutenbergView.setEditorDidBecomeAvailable { available = true }
        gutenbergView.onEditorLoaded()
        shadowOf(Looper.getMainLooper()).idle()

        // The page a reload replaces can still report itself loaded.
        gutenbergView.reloadEditor()
        gutenbergView.onEditorLoaded()
        shadowOf(Looper.getMainLooper()).idle()
        available = false

        val webView = gutenbergView.editorWebView
        webView.webViewClient.onPageStarted(webView, null, null)
        val shadowWebView = shadowOf(webView)
        val lastEvaluated = shadowWebView.lastEvaluatedJavascript
        gutenbergView.undo()
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals(
            "the new page must not be sent commands before it loads",
            lastEvaluated,
            shadowWebView.lastEvaluatedJavascript
        )

        gutenbergView.onEditorLoaded()
        shadowOf(Looper.getMainLooper()).idle()

        assertTrue("the new page must report itself available once it loads", available)
    }

    @Test
    fun `reloadEditor fails reads still waiting on the page it replaces`() {
        gutenbergView.onEditorLoaded()
        shadowOf(Looper.getMainLooper()).idle()
        val callback = RecordingTitleAndContentCallback()
        gutenbergView.getTitleAndContent("original content", callback)
        // Robolectric's shadow WebView never invokes the ValueCallback, like a page
        // replaced before it answers.
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue("the read is still waiting", callback.errors.isEmpty())

        gutenbergView.reloadEditor()

        assertEquals("the host is told the read failed", 1, callback.errors.size)
        assertTrue("because the editor is not ready", callback.errors.first() is EditorNotReadyException)
    }

    @Test
    fun `textEditorEnabled waits for the editor to load`() {
        val shadowWebView = shadowOf(gutenbergView.editorWebView)
        val lastEvaluated = shadowWebView.lastEvaluatedJavascript

        gutenbergView.textEditorEnabled = true
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals(
            "an editor that has not loaded must not be asked to switch modes",
            lastEvaluated,
            shadowWebView.lastEvaluatedJavascript
        )
    }

    @Test
    fun `onEditorLoaded restores the code editor`() {
        // Content keeps `onEditorLoaded` from focusing the editor, which would
        // otherwise be the last script evaluated.
        val view = GutenbergView(
            EditorConfiguration.builder("https://example.com", "https://example.com/wp-json/")
                .setContent("<!-- wp:paragraph --><p>Hello</p><!-- /wp:paragraph -->")
                .setEnableOfflineMode(true)
                .build(),
            EditorDependencies.empty,
            testScope,
            RuntimeEnvironment.getApplication()
        )
        view.textEditorEnabled = true

        view.onEditorLoaded()
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals(
            "the web editor starts in visual mode, so code editor mode must be restored",
            "editor.switchEditorMode('text');",
            shadowOf(view.editorWebView).lastEvaluatedJavascript
        )
    }
}
