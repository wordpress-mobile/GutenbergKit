package org.wordpress.gutenberg

import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.wordpress.gutenberg.model.EditorAuthorizationScope
import org.wordpress.gutenberg.model.http.EditorHttpMethod
import java.io.File

/** The site's credentials go to the site, and to no other host a request names. */
class EditorHTTPClientAuthorizationTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

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

    /** A client for a site the mock web server serves. */
    private fun makeClientForSite() = EditorHTTPClient(
        authHeader = TEST_AUTH_HEADER,
        authorizationScope = EditorAuthorizationScope(siteURL = baseUrl, siteApiRoot = baseUrl)
    )

    /** A client for a site somewhere else, to which the mock web server is another party's host. */
    private fun makeClientForAnotherSite() = EditorHTTPClient(
        authHeader = TEST_AUTH_HEADER,
        authorizationScope = EditorAuthorizationScope(
            siteURL = "https://example.com",
            siteApiRoot = "https://example.com/wp-json/"
        )
    )

    @Test
    fun `perform sends the Authorization header to the site`() = runBlocking {
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody("{}"))

        makeClientForSite().perform(EditorHttpMethod.GET, "${baseUrl}wp/v2/posts")

        assertEquals(TEST_AUTH_HEADER, mockWebServer.takeRequest().getHeader("Authorization"))
    }

    @Test
    fun `perform sends no Authorization header to another party's host`() = runBlocking {
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody("{}"))

        makeClientForAnotherSite().perform(EditorHttpMethod.GET, "${baseUrl}v1/things")

        assertNull(mockWebServer.takeRequest().getHeader("Authorization"))
    }

    @Test
    fun `download sends the Authorization header to the site`() = runBlocking {
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody("content"))

        makeClientForSite().download("${baseUrl}wp-content/script.js", File(tempFolder.root, "script.js"))

        assertEquals(TEST_AUTH_HEADER, mockWebServer.takeRequest().getHeader("Authorization"))
    }

    @Test
    fun `download sends no Authorization header to another party's host`() = runBlocking {
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody("content"))

        makeClientForAnotherSite().download("${baseUrl}integration.js", File(tempFolder.root, "integration.js"))

        assertNull(mockWebServer.takeRequest().getHeader("Authorization"))
    }
}
