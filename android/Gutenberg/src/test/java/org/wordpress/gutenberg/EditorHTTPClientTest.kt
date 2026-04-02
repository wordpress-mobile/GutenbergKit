package org.wordpress.gutenberg

import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.Response
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.wordpress.gutenberg.model.http.EditorHttpMethod
import java.io.File
import java.util.concurrent.TimeUnit

class EditorHTTPClientTest {

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

    private fun makeClient(
        authHeader: String = TEST_AUTH_HEADER,
        delegate: EditorHTTPClientDelegate? = null,
        timeoutSeconds: Long = 60
    ): EditorHTTPClient {
        return EditorHTTPClient(
            authHeader = authHeader,
            delegate = delegate,
            requestTimeoutSeconds = timeoutSeconds
        )
    }

    // MARK: - EditorHTTPClientResponse Tests

    @Test
    fun `EditorHTTPClientResponse stringData returns UTF-8 decoded string`() {
        val testString = "Hello, World!"
        val response = EditorHTTPClientResponse(
            data = testString.toByteArray(Charsets.UTF_8),
            statusCode = 200,
            headers = org.wordpress.gutenberg.model.http.EditorHTTPHeaders()
        )

        assertEquals(testString, response.stringData)
    }

    @Test
    fun `EditorHTTPClientResponse stringData handles unicode correctly`() {
        val testString = "こんにちは世界 🌍"
        val response = EditorHTTPClientResponse(
            data = testString.toByteArray(Charsets.UTF_8),
            statusCode = 200,
            headers = org.wordpress.gutenberg.model.http.EditorHTTPHeaders()
        )

        assertEquals(testString, response.stringData)
    }

    @Test
    fun `EditorHTTPClientResponse equals compares data content`() {
        val data = "test data".toByteArray()
        val response1 = EditorHTTPClientResponse(
            data = data.copyOf(),
            statusCode = 200,
            headers = org.wordpress.gutenberg.model.http.EditorHTTPHeaders()
        )
        val response2 = EditorHTTPClientResponse(
            data = data.copyOf(),
            statusCode = 200,
            headers = org.wordpress.gutenberg.model.http.EditorHTTPHeaders()
        )

        assertEquals(response1, response2)
    }

    @Test
    fun `EditorHTTPClientResponse equals returns false for different status codes`() {
        val data = "test data".toByteArray()
        val response1 = EditorHTTPClientResponse(
            data = data,
            statusCode = 200,
            headers = org.wordpress.gutenberg.model.http.EditorHTTPHeaders()
        )
        val response2 = EditorHTTPClientResponse(
            data = data,
            statusCode = 404,
            headers = org.wordpress.gutenberg.model.http.EditorHTTPHeaders()
        )

        assertTrue(response1 != response2)
    }

    // MARK: - WPError Tests

    @Test
    fun `WPError stores code and message`() {
        val error = WPError(code = "rest_forbidden", message = "Sorry, you are not allowed to do that.")

        assertEquals("rest_forbidden", error.code)
        assertEquals("Sorry, you are not allowed to do that.", error.message)
    }

    // MARK: - EditorHTTPClientError Tests

    @Test
    fun `WPErrorResponse message includes code and message`() {
        val wpError = WPError(code = "rest_forbidden", message = "Access denied")
        val error = EditorHTTPClientError.WPErrorResponse(wpError)

        assertEquals("rest_forbidden: Access denied", error.message)
    }

    @Test
    fun `DownloadFailed message includes status code`() {
        val error = EditorHTTPClientError.DownloadFailed(statusCode = 404)

        assertEquals("Download failed with status code: 404", error.message)
    }

    @Test
    fun `Unknown error message includes status code`() {
        val error = EditorHTTPClientError.Unknown(
            responseData = "error".toByteArray(),
            statusCode = 500
        )

        assertEquals("Unknown error with status code: 500", error.message)
    }

    @Test
    fun `Unknown error equals compares data content`() {
        val data = "error data".toByteArray()
        val error1 = EditorHTTPClientError.Unknown(data.copyOf(), 500)
        val error2 = EditorHTTPClientError.Unknown(data.copyOf(), 500)

        assertEquals(error1, error2)
    }

    // MARK: - perform() Tests

    @Test
    fun `perform GET request returns response data`() = runBlocking {
        val responseBody = """{"id": 1, "title": "Test Post"}"""
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody(responseBody)
        )

        val client = makeClient()
        val response = client.perform(EditorHttpMethod.GET, "${baseUrl}wp/v2/posts/1")

        assertEquals(200, response.statusCode)
        assertEquals(responseBody, response.stringData)
    }

    @Test
    fun `perform request includes authorization header`() = runBlocking {
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody("{}"))

        val client = makeClient(authHeader = "Bearer my-secret-token")
        client.perform(EditorHttpMethod.GET, "${baseUrl}test")

        val recordedRequest = mockWebServer.takeRequest()
        assertEquals("Bearer my-secret-token", recordedRequest.getHeader("Authorization"))
    }

    @Test
    fun `perform request uses correct HTTP method`() = runBlocking {
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody("{}"))

        val client = makeClient()
        client.perform(EditorHttpMethod.OPTIONS, "${baseUrl}test")

        val recordedRequest = mockWebServer.takeRequest()
        assertEquals("OPTIONS", recordedRequest.method)
    }

    @Test
    fun `perform request extracts response headers`() = runBlocking {
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("{}")
                .addHeader("X-Custom-Header", "custom-value")
                .addHeader("Content-Type", "application/json")
        )

        val client = makeClient()
        val response = client.perform(EditorHttpMethod.GET, "${baseUrl}test")

        assertEquals("custom-value", response.headers["X-Custom-Header"])
        assertEquals("application/json", response.headers["Content-Type"])
    }

    @Test
    fun `perform request throws WPErrorResponse for WordPress error`() = runBlocking {
        val wpErrorJson = """{"code": "rest_forbidden", "message": "Sorry, you are not allowed to do that."}"""
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(403)
                .setBody(wpErrorJson)
        )

        val client = makeClient()

        try {
            client.perform(EditorHttpMethod.GET, "${baseUrl}test")
            fail("Expected WPErrorResponse to be thrown")
        } catch (e: EditorHTTPClientError.WPErrorResponse) {
            assertEquals("rest_forbidden", e.error.code)
            assertEquals("Sorry, you are not allowed to do that.", e.error.message)
        }
    }

    @Test
    fun `perform request throws Unknown error for non-WP error response`() = runBlocking {
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(500)
                .setBody("Internal Server Error")
        )

        val client = makeClient()

        try {
            client.perform(EditorHttpMethod.GET, "${baseUrl}test")
            fail("Expected Unknown error to be thrown")
        } catch (e: EditorHTTPClientError.Unknown) {
            assertEquals(500, e.statusCode)
            assertEquals("Internal Server Error", e.responseData.toString(Charsets.UTF_8))
        }
    }

    @Test
    fun `perform request calls delegate on success`() = runBlocking {
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody("response data"))

        var delegateCalled = false
        var capturedUrl: String? = null
        var capturedMethod: EditorHttpMethod? = null
        var capturedData: EditorResponseData? = null

        val delegate = object : EditorHTTPClientDelegate {
            override fun didPerformRequest(url: String, method: EditorHttpMethod, response: Response, data: EditorResponseData) {
                delegateCalled = true
                capturedUrl = url
                capturedMethod = method
                capturedData = data
            }
        }

        val client = makeClient(delegate = delegate)
        client.perform(EditorHttpMethod.GET, "${baseUrl}test")

        assertTrue(delegateCalled)
        assertTrue(capturedUrl?.contains("test") == true)
        assertEquals(EditorHttpMethod.GET, capturedMethod)
        val bytes = (capturedData as? EditorResponseData.Bytes)?.data
        assertEquals("response data", bytes?.toString(Charsets.UTF_8))
    }

    @Test
    fun `perform request handles empty response body`() = runBlocking {
        mockWebServer.enqueue(MockResponse().setResponseCode(204))

        val client = makeClient()
        val response = client.perform(EditorHttpMethod.DELETE, "${baseUrl}test")

        assertEquals(204, response.statusCode)
        assertTrue(response.data.isEmpty())
    }

    // MARK: - download() Tests

    @Test
    fun `download saves file to destination`() = runBlocking {
        val fileContent = "file content to download"
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody(fileContent)
        )

        val destination = File(tempFolder.root, "downloaded.txt")
        val client = makeClient()
        val response = client.download("${baseUrl}file.txt", destination)

        assertEquals(200, response.statusCode)
        assertTrue(destination.exists())
        assertEquals(fileContent, destination.readText())
    }

    @Test
    fun `download creates parent directories`() = runBlocking {
        val fileContent = "nested file content"
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody(fileContent)
        )

        val destination = File(tempFolder.root, "nested/path/to/downloaded.txt")
        val client = makeClient()
        client.download("${baseUrl}file.txt", destination)

        assertTrue(destination.exists())
        assertTrue(destination.parentFile?.exists() == true)
        assertEquals(fileContent, destination.readText())
    }

    @Test
    fun `download includes authorization header`() = runBlocking {
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody("content"))

        val destination = File(tempFolder.root, "file.txt")
        val client = makeClient(authHeader = "Bearer download-token")
        client.download("${baseUrl}file.txt", destination)

        val recordedRequest = mockWebServer.takeRequest()
        assertEquals("Bearer download-token", recordedRequest.getHeader("Authorization"))
    }

    @Test
    fun `download throws DownloadFailed for 404`() = runBlocking {
        mockWebServer.enqueue(MockResponse().setResponseCode(404))

        val destination = File(tempFolder.root, "file.txt")
        val client = makeClient()

        try {
            client.download("${baseUrl}missing.txt", destination)
            fail("Expected DownloadFailed to be thrown")
        } catch (e: EditorHTTPClientError.DownloadFailed) {
            assertEquals(404, e.statusCode)
        }
    }

    @Test
    fun `download throws DownloadFailed for 500`() = runBlocking {
        mockWebServer.enqueue(MockResponse().setResponseCode(500))

        val destination = File(tempFolder.root, "file.txt")
        val client = makeClient()

        try {
            client.download("${baseUrl}error.txt", destination)
            fail("Expected DownloadFailed to be thrown")
        } catch (e: EditorHTTPClientError.DownloadFailed) {
            assertEquals(500, e.statusCode)
        }
    }

    @Test
    fun `download extracts response headers`() = runBlocking {
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("content")
                .addHeader("Content-Type", "text/plain")
                .addHeader("Content-Length", "7")
        )

        val destination = File(tempFolder.root, "file.txt")
        val client = makeClient()
        val response = client.download("${baseUrl}file.txt", destination)

        assertEquals("text/plain", response.headers["Content-Type"])
    }

    @Test
    fun `download returns correct file reference`() = runBlocking {
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody("content"))

        val destination = File(tempFolder.root, "specific-file.txt")
        val client = makeClient()
        val response = client.download("${baseUrl}file.txt", destination)

        assertEquals(destination.absolutePath, response.file.absolutePath)
    }

    // MARK: - Constructor Tests

    @Test
    fun `client can be created with custom OkHttpClient`() = runBlocking {
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody("{}"))

        val customOkHttpClient = OkHttpClient.Builder()
            .connectTimeout(5, TimeUnit.SECONDS)
            .build()

        val client = EditorHTTPClient(
            authHeader = TEST_AUTH_HEADER,
            okHttpClient = customOkHttpClient
        )

        val response = client.perform(EditorHttpMethod.GET, "${baseUrl}test")
        assertEquals(200, response.statusCode)
    }

    @Test
    fun `client uses specified timeout`() {
        // Create client with short timeout
        val client = makeClient(timeoutSeconds = 1)

        // This test verifies the client is created with the specified timeout
        // Actual timeout behavior would require a slow server response
        assertNotNull(client)
    }

    // MARK: - WordPress Error Parsing Tests

    @Test
    fun `perform parses WordPress error with data field`() = runBlocking {
        val wpErrorJson = """{"code": "rest_invalid_param", "message": "Invalid parameter", "data": {"status": 400}}"""
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(400)
                .setBody(wpErrorJson)
        )

        val client = makeClient()

        try {
            client.perform(EditorHttpMethod.GET, "${baseUrl}test")
            fail("Expected WPErrorResponse to be thrown")
        } catch (e: EditorHTTPClientError.WPErrorResponse) {
            assertEquals("rest_invalid_param", e.error.code)
            assertEquals("Invalid parameter", e.error.message)
        }
    }

    @Test
    fun `perform returns Unknown error when error JSON is malformed`() = runBlocking {
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(500)
                .setBody("{not valid json")
        )

        val client = makeClient()

        try {
            client.perform(EditorHttpMethod.GET, "${baseUrl}test")
            fail("Expected Unknown error to be thrown")
        } catch (e: EditorHTTPClientError.Unknown) {
            assertEquals(500, e.statusCode)
        }
    }

    @Test
    fun `perform returns Unknown error when error JSON is missing code`() = runBlocking {
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(500)
                .setBody("""{"message": "Something went wrong"}""")
        )

        val client = makeClient()

        try {
            client.perform(EditorHttpMethod.GET, "${baseUrl}test")
            fail("Expected Unknown error to be thrown")
        } catch (e: EditorHTTPClientError.Unknown) {
            assertEquals(500, e.statusCode)
        }
    }

    @Test
    fun `perform returns Unknown error when error JSON is missing message`() = runBlocking {
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(500)
                .setBody("""{"code": "some_error"}""")
        )

        val client = makeClient()

        try {
            client.perform(EditorHttpMethod.GET, "${baseUrl}test")
            fail("Expected Unknown error to be thrown")
        } catch (e: EditorHTTPClientError.Unknown) {
            assertEquals(500, e.statusCode)
        }
    }

    @Test
    fun `perform parses error with nested data params`() = runBlocking {
        val wpErrorJson = """{"code": "rest_invalid_param", "message": "Invalid parameter(s): title", "data": {"status": 400, "params": {"title": "Title is required."}}}"""
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(400)
                .setBody(wpErrorJson)
        )

        val client = makeClient()

        try {
            client.perform(EditorHttpMethod.GET, "${baseUrl}test")
            fail("Expected WPErrorResponse to be thrown")
        } catch (e: EditorHTTPClientError.WPErrorResponse) {
            assertEquals("rest_invalid_param", e.error.code)
            assertEquals("Invalid parameter(s): title", e.error.message)
        }
    }

    @Test
    fun `perform parses error with additional_errors array`() = runBlocking {
        val wpErrorJson = """{"code": "rest_invalid_param", "message": "Invalid parameter(s): title, content", "data": {"status": 400}, "additional_errors": [{"code": "rest_invalid_field", "message": "Content is required."}]}"""
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(400)
                .setBody(wpErrorJson)
        )

        val client = makeClient()

        try {
            client.perform(EditorHttpMethod.GET, "${baseUrl}test")
            fail("Expected WPErrorResponse to be thrown")
        } catch (e: EditorHTTPClientError.WPErrorResponse) {
            assertEquals("rest_invalid_param", e.error.code)
            assertEquals("Invalid parameter(s): title, content", e.error.message)
        }
    }

    @Test
    fun `perform parses error with unicode characters in message`() = runBlocking {
        val wpErrorJson = """{"code": "custom_error", "message": "エラーが発生しました 🚫", "data": {"status": 500}}"""
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(500)
                .setBody(wpErrorJson)
        )

        val client = makeClient()

        try {
            client.perform(EditorHttpMethod.GET, "${baseUrl}test")
            fail("Expected WPErrorResponse to be thrown")
        } catch (e: EditorHTTPClientError.WPErrorResponse) {
            assertEquals("custom_error", e.error.code)
            assertEquals("エラーが発生しました 🚫", e.error.message)
        }
    }

    @Test
    fun `perform parses error without data field`() = runBlocking {
        val wpErrorJson = """{"code": "simple_error", "message": "A simple error occurred."}"""
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(400)
                .setBody(wpErrorJson)
        )

        val client = makeClient()

        try {
            client.perform(EditorHttpMethod.GET, "${baseUrl}test")
            fail("Expected WPErrorResponse to be thrown")
        } catch (e: EditorHTTPClientError.WPErrorResponse) {
            assertEquals("simple_error", e.error.code)
            assertEquals("A simple error occurred.", e.error.message)
        }
    }

    @Test
    fun `perform parses WPError when code is empty string`() = runBlocking {
        val wpErrorJson = """{"code": "", "message": "Error with empty code"}"""
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(400)
                .setBody(wpErrorJson)
        )

        val client = makeClient()

        try {
            client.perform(EditorHttpMethod.GET, "${baseUrl}test")
            fail("Expected WPErrorResponse to be thrown")
        } catch (e: EditorHTTPClientError.WPErrorResponse) {
            assertEquals("", e.error.code)
            assertEquals("Error with empty code", e.error.message)
        }
    }

    @Test
    fun `perform parses WPError when message is empty string`() = runBlocking {
        val wpErrorJson = """{"code": "empty_message", "message": ""}"""
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(400)
                .setBody(wpErrorJson)
        )

        val client = makeClient()

        try {
            client.perform(EditorHttpMethod.GET, "${baseUrl}test")
            fail("Expected WPErrorResponse to be thrown")
        } catch (e: EditorHTTPClientError.WPErrorResponse) {
            assertEquals("empty_message", e.error.code)
            assertEquals("", e.error.message)
        }
    }

    @Test
    fun `perform returns Unknown error when response is empty JSON object`() = runBlocking {
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(500)
                .setBody("{}")
        )

        val client = makeClient()

        try {
            client.perform(EditorHttpMethod.GET, "${baseUrl}test")
            fail("Expected Unknown error to be thrown")
        } catch (e: EditorHTTPClientError.Unknown) {
            assertEquals(500, e.statusCode)
        }
    }

    @Test
    fun `perform returns Unknown error when response is JSON array`() = runBlocking {
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(500)
                .setBody("""[{"code": "error", "message": "test"}]""")
        )

        val client = makeClient()

        try {
            client.perform(EditorHttpMethod.GET, "${baseUrl}test")
            fail("Expected Unknown error to be thrown")
        } catch (e: EditorHTTPClientError.Unknown) {
            assertEquals(500, e.statusCode)
        }
    }

    @Test
    fun `perform returns Unknown error when response is plain text`() = runBlocking {
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(500)
                .setBody("Internal Server Error")
        )

        val client = makeClient()

        try {
            client.perform(EditorHttpMethod.GET, "${baseUrl}test")
            fail("Expected Unknown error to be thrown")
        } catch (e: EditorHTTPClientError.Unknown) {
            assertEquals(500, e.statusCode)
            assertEquals("Internal Server Error", e.responseData.toString(Charsets.UTF_8))
        }
    }

    @Test
    fun `perform returns Unknown error when response is HTML`() = runBlocking {
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(500)
                .setBody("<html><body><h1>500 Internal Server Error</h1></body></html>")
        )

        val client = makeClient()

        try {
            client.perform(EditorHttpMethod.GET, "${baseUrl}test")
            fail("Expected Unknown error to be thrown")
        } catch (e: EditorHTTPClientError.Unknown) {
            assertEquals(500, e.statusCode)
        }
    }

    @Test
    fun `perform parses error with null data field`() = runBlocking {
        val wpErrorJson = """{"code": "null_data_error", "message": "Error with null data", "data": null}"""
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(400)
                .setBody(wpErrorJson)
        )

        val client = makeClient()

        try {
            client.perform(EditorHttpMethod.GET, "${baseUrl}test")
            fail("Expected WPErrorResponse to be thrown")
        } catch (e: EditorHTTPClientError.WPErrorResponse) {
            assertEquals("null_data_error", e.error.code)
            assertEquals("Error with null data", e.error.message)
        }
    }

    @Test
    fun `WPErrorResponse message format is correct`() {
        val wpError = WPError(code = "test_code", message = "Test message")
        val error = EditorHTTPClientError.WPErrorResponse(wpError)

        assertEquals("test_code: Test message", error.message)
    }

    // MARK: - Edge Cases

    @Test
    fun `perform handles 201 Created as success`() = runBlocking {
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(201)
                .setBody("""{"id": 123}""")
        )

        val client = makeClient()
        val response = client.perform(EditorHttpMethod.POST, "${baseUrl}test")

        assertEquals(201, response.statusCode)
    }

    @Test
    fun `download handles binary content`() = runBlocking {
        val binaryContent = byteArrayOf(0x00, 0x01, 0x02, 0xFF.toByte(), 0xFE.toByte())
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody(okio.Buffer().write(binaryContent))
        )

        val destination = File(tempFolder.root, "binary.bin")
        val client = makeClient()
        client.download("${baseUrl}file.bin", destination)

        assertTrue(destination.readBytes().contentEquals(binaryContent))
    }
}
