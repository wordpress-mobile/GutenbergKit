package org.wordpress.gutenberg

import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.wordpress.gutenberg.model.EditorConfiguration

/**
 * The manifest request of [org.wordpress.gutenberg.EditorAssetsLibrary] — the one in this
 * package, which makes its own connection rather than going through [EditorHTTPClient] — sends
 * the site's credentials to the site, and not to a custom endpoint on another party's host.
 */
@RunWith(RobolectricTestRunner::class)
class EditorAssetsManifestAuthorizationTest {

    private lateinit var mockWebServer: MockWebServer
    private lateinit var baseUrl: String

    companion object {
        private const val TEST_AUTH_HEADER = "Bearer test-token-12345"
    }

    @Before
    fun setUp() {
        mockWebServer = MockWebServer()
        mockWebServer.start()
        baseUrl = mockWebServer.url("/").toString()
    }

    @After
    fun tearDown() {
        mockWebServer.shutdown()
    }

    private fun makeLibrary(configuration: EditorConfiguration.Builder) = EditorAssetsLibrary(
        RuntimeEnvironment.getApplication(),
        configuration.setAuthHeader(TEST_AUTH_HEADER).build()
    )

    @Test
    fun `the manifest request sends the Authorization header to the site's API`() = runBlocking {
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody("{}"))

        makeLibrary(EditorConfiguration.builder(baseUrl, baseUrl)).loadManifestContent()

        assertEquals(TEST_AUTH_HEADER, mockWebServer.takeRequest().getHeader("Authorization"))
    }

    @Test
    fun `the manifest request sends no Authorization header to an endpoint on another party's host`() = runBlocking {
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody("{}"))

        makeLibrary(
            EditorConfiguration.builder("https://example.com", "https://example.com/wp-json/")
                .setEditorAssetsEndpoint("${baseUrl}editor-assets")
        ).loadManifestContent()

        assertNull(mockWebServer.takeRequest().getHeader("Authorization"))
    }
}
