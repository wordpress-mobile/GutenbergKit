package org.wordpress.gutenberg

import com.google.gson.JsonParser
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.net.Socket

class MediaUploadServerTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private lateinit var server: MediaUploadServer

    @Before
    fun setUp() {
        server = MediaUploadServer(uploadDelegate = null, defaultUploader = null, cacheDir = tempFolder.root)
    }

    @After
    fun tearDown() {
        server.stop()
    }

    // MARK: - Server lifecycle

    @Test
    fun `starts and provides a port and token`() {
        assertTrue(server.port > 0)
        assertTrue(server.token.isNotEmpty())
    }

    // MARK: - Auth validation

    @Test
    fun `rejects requests without auth token`() {
        val response = sendRawRequest(
            method = "POST",
            path = "/upload",
            headers = mapOf("Content-Type" to "text/plain"),
            body = "hello".toByteArray()
        )

        assertTrue(response.statusLine.contains("407"))
    }

    @Test
    fun `rejects requests with wrong token`() {
        val response = sendRawRequest(
            method = "POST",
            path = "/upload",
            headers = mapOf(
                "Relay-Authorization" to "Bearer wrong-token",
                "Content-Type" to "text/plain"
            ),
            body = "hello".toByteArray()
        )

        assertTrue(response.statusLine.contains("407"))
    }

    // MARK: - CORS preflight

    @Test
    fun `responds to OPTIONS preflight with CORS headers`() {
        val response = sendRawRequest(
            method = "OPTIONS",
            path = "/upload",
            headers = emptyMap(),
            body = null
        )

        assertTrue(response.statusLine.contains("204"))
        assertEquals("*", response.headers["access-control-allow-origin"])
        assertTrue(response.headers["access-control-allow-methods"]?.contains("POST") == true)
        assertTrue(response.headers["access-control-allow-headers"]?.contains("Relay-Authorization") == true)
    }

    // MARK: - Routing

    @Test
    fun `returns 404 for unknown paths`() {
        val response = sendRawRequest(
            method = "GET",
            path = "/unknown",
            headers = mapOf("Relay-Authorization" to "Bearer ${server.token}"),
            body = null
        )

        assertTrue(response.statusLine.contains("404"))
    }

    // MARK: - Upload with delegate

    @Test
    fun `calls delegate processFile and uploadFile`() {
        val delegate = MockUploadDelegate()
        server.stop()
        server = MediaUploadServer(uploadDelegate = delegate, defaultUploader = null, cacheDir = tempFolder.root)

        val boundary = "test-boundary-123"
        val body = buildMultipartBody(boundary, "photo.jpg", "image/jpeg", "fake image data".toByteArray())

        val response = sendRawRequest(
            method = "POST",
            path = "/upload",
            headers = mapOf(
                "Relay-Authorization" to "Bearer ${server.token}",
                "Content-Type" to "multipart/form-data; boundary=$boundary"
            ),
            body = body
        )

        assertTrue("Expected 201 but got: ${response.statusLine}", response.statusLine.contains("201"))
        assertTrue(delegate.processFileCalled)
        assertTrue(delegate.uploadFileCalled)
        assertEquals("image/jpeg", delegate.lastMimeType)
        assertEquals("photo.jpg", delegate.lastFilename)

        // The server relays WordPress's raw response body verbatim.
        val json = JsonParser.parseString(response.body).asJsonObject
        assertEquals(42, json.get("id").asInt)
        assertEquals("https://example.com/photo.jpg", json.get("source_url").asString)
        assertEquals("image", json.get("media_type").asString)
    }

    // MARK: - Fallback to default uploader

    @Test
    fun `uses passthrough when delegate does not modify file`() {
        val delegate = ProcessOnlyDelegate()
        val mockUploader = MockDefaultUploader()

        server.stop()
        server = MediaUploadServer(uploadDelegate = delegate, defaultUploader = mockUploader, cacheDir = tempFolder.root)

        val boundary = "test-boundary-456"
        val body = buildMultipartBody(boundary, "doc.pdf", "application/pdf", "fake pdf data".toByteArray())

        val response = sendRawRequest(
            method = "POST",
            path = "/upload",
            headers = mapOf(
                "Relay-Authorization" to "Bearer ${server.token}",
                "Content-Type" to "multipart/form-data; boundary=$boundary"
            ),
            body = body
        )

        assertTrue("Expected 201 but got: ${response.statusLine}", response.statusLine.contains("201"))
        assertTrue(delegate.processFileCalled)
        // Passthrough: original body forwarded directly, not re-encoded.
        assertTrue(mockUploader.passthroughUploadCalled)
        assertFalse(mockUploader.uploadCalled)

        val json = JsonParser.parseString(response.body).asJsonObject
        assertEquals(99, json.get("id").asInt)
    }

    // MARK: - DefaultMediaUploader

    @Test
    fun `DefaultMediaUploader relays the WordPress response`() {
        val mockWpServer = MockWebServer()
        val wpBody =
            """{"id":1,"source_url":"https://example.com/u.jpg","media_type":"image"}"""
        mockWpServer.enqueue(
            MockResponse()
                .setResponseCode(201)
                .setHeader("Content-Type", "application/json")
                .setBody(wpBody)
        )
        mockWpServer.start()

        val wpBaseUrl = mockWpServer.url("/wp-json/").toString()
        val uploader = DefaultMediaUploader(
            httpClient = okhttp3.OkHttpClient(),
            siteApiRoot = wpBaseUrl,
            authHeader = "Bearer test-token"
        )

        val file = tempFolder.newFile("image.jpg")
        file.writeBytes("fake image".toByteArray())

        val response = runBlocking { uploader.upload(file, "image/jpeg", "image.jpg", emptyList(), "") }

        // The uploader relays WordPress's exact status and body — no parsing.
        assertEquals(201, response.statusCode)
        assertEquals(wpBody, String(response.body))

        val request = mockWpServer.takeRequest()
        assertEquals("POST", request.method)
        assertTrue(request.path!!.contains("wp/v2/media"))
        assertEquals("Bearer test-token", request.getHeader("Authorization"))
        assertTrue(request.getHeader("Content-Type")!!.contains("multipart/form-data"))

        mockWpServer.shutdown()
    }

    @Test
    fun `DefaultMediaUploader relays a WordPress error response instead of throwing`() {
        val mockWpServer = MockWebServer()
        mockWpServer.enqueue(MockResponse().setResponseCode(500).setBody("Internal error"))
        mockWpServer.start()

        val wpBaseUrl = mockWpServer.url("/wp-json/").toString()
        val uploader = DefaultMediaUploader(
            httpClient = okhttp3.OkHttpClient(),
            siteApiRoot = wpBaseUrl,
            authHeader = "Bearer test-token"
        )

        val file = tempFolder.newFile("fail.jpg")
        file.writeBytes("data".toByteArray())

        // WordPress's error status + body flow through to the editor, which
        // surfaces the real message — the uploader does not throw.
        val response = runBlocking { uploader.upload(file, "image/jpeg", "fail.jpg", emptyList(), "") }
        assertEquals(500, response.statusCode)
        assertEquals("Internal error", String(response.body))

        mockWpServer.shutdown()
    }

    @Test
    fun `DefaultMediaUploader re-encode preserves extra parts and query`() {
        val mockWpServer = MockWebServer()
        mockWpServer.enqueue(MockResponse().setResponseCode(201).setBody("{}"))
        mockWpServer.start()

        val uploader = DefaultMediaUploader(
            httpClient = okhttp3.OkHttpClient(),
            siteApiRoot = mockWpServer.url("/wp-json/").toString(),
            authHeader = "Bearer test-token"
        )
        val file = tempFolder.newFile("image.jpg")
        file.writeBytes("fake image".toByteArray())

        val postPart = org.wordpress.gutenberg.http.MultipartPart(
            name = "post",
            filename = null,
            contentType = "text/plain",
            body = org.wordpress.gutenberg.http.RequestBody.InMemory("123".toByteArray())
        )

        runBlocking {
            uploader.upload(file, "image/jpeg", "image.jpg", listOf(postPart), "?_embed=wp:featuredmedia")
        }

        val request = mockWpServer.takeRequest()
        // The query and the non-file part must both reach WordPress.
        assertTrue(request.path!!.contains("_embed"))
        val bodyText = request.body.readUtf8()
        assertTrue("Expected post field in multipart body", bodyText.contains("name=\"post\""))
        assertTrue(bodyText.contains("123"))

        mockWpServer.shutdown()
    }

    // MARK: - Bad request handling

    @Test
    fun `rejects upload without content type`() {
        val response = sendRawRequest(
            method = "POST",
            path = "/upload",
            headers = mapOf("Relay-Authorization" to "Bearer ${server.token}"),
            body = "not multipart".toByteArray()
        )

        assertTrue(response.statusLine.contains("400"))
    }

    @Test
    fun `rejects upload with non-multipart content type`() {
        val response = sendRawRequest(
            method = "POST",
            path = "/upload",
            headers = mapOf(
                "Relay-Authorization" to "Bearer ${server.token}",
                "Content-Type" to "application/json"
            ),
            body = """{"key": "value"}""".toByteArray()
        )

        assertTrue(response.statusLine.contains("400"))
    }

    // MARK: - Helpers

    private data class RawHttpResponse(
        val statusLine: String,
        val headers: Map<String, String>,
        val body: String
    )

    private fun sendRawRequest(
        method: String,
        path: String,
        headers: Map<String, String>,
        body: ByteArray?
    ): RawHttpResponse {
        val socket = Socket("127.0.0.1", server.port)
        socket.soTimeout = 5000

        val output = socket.getOutputStream()
        val request = buildString {
            append("$method $path HTTP/1.1\r\n")
            append("Host: 127.0.0.1:${server.port}\r\n")
            for ((key, value) in headers) {
                append("$key: $value\r\n")
            }
            if (body != null) {
                append("Content-Length: ${body.size}\r\n")
            }
            append("Connection: close\r\n")
            append("\r\n")
        }

        output.write(request.toByteArray())
        if (body != null) {
            output.write(body)
        }
        output.flush()

        val responseBytes = socket.getInputStream().readBytes()
        socket.close()

        val responseString = String(responseBytes, Charsets.UTF_8)
        val headerEnd = responseString.indexOf("\r\n\r\n")
        if (headerEnd < 0) {
            return RawHttpResponse(responseString, emptyMap(), "")
        }

        val headerSection = responseString.substring(0, headerEnd)
        val responseBody = responseString.substring(headerEnd + 4)
        val lines = headerSection.split("\r\n")
        val statusLine = lines.first()

        val responseHeaders = mutableMapOf<String, String>()
        for (line in lines.drop(1)) {
            val colonIndex = line.indexOf(':')
            if (colonIndex > 0) {
                val key = line.substring(0, colonIndex).trim().lowercase()
                val value = line.substring(colonIndex + 1).trim()
                responseHeaders[key] = value
            }
        }

        return RawHttpResponse(statusLine, responseHeaders, responseBody)
    }

    private fun buildMultipartBody(
        boundary: String,
        filename: String,
        mimeType: String,
        data: ByteArray
    ): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        out.write("--$boundary\r\n".toByteArray())
        out.write("Content-Disposition: form-data; name=\"file\"; filename=\"$filename\"\r\n".toByteArray())
        out.write("Content-Type: $mimeType\r\n\r\n".toByteArray())
        out.write(data)
        out.write("\r\n--$boundary--\r\n".toByteArray())
        return out.toByteArray()
    }

    // MARK: - Mocks

    private class MockUploadDelegate : MediaUploadDelegate {
        @Volatile var processFileCalled = false
        @Volatile var uploadFileCalled = false
        @Volatile var lastMimeType: String? = null
        @Volatile var lastFilename: String? = null

        override suspend fun processFile(file: File, mimeType: String): File {
            processFileCalled = true
            lastMimeType = mimeType
            return file
        }

        override suspend fun uploadFile(file: File, mimeType: String, filename: String): MediaUploadResponse? {
            uploadFileCalled = true
            lastFilename = filename
            val json = """{"id":42,"source_url":"https://example.com/photo.jpg","media_type":"image"}"""
            return MediaUploadResponse(201, json.toByteArray())
        }
    }

    private class ProcessOnlyDelegate : MediaUploadDelegate {
        @Volatile var processFileCalled = false

        override suspend fun processFile(file: File, mimeType: String): File {
            processFileCalled = true
            return file
        }
    }

    private class MockDefaultUploader : DefaultMediaUploader(
        httpClient = okhttp3.OkHttpClient(),
        siteApiRoot = "https://example.com/wp-json/",
        authHeader = "Bearer mock"
    ) {
        @Volatile var uploadCalled = false
        @Volatile var passthroughUploadCalled = false

        override suspend fun upload(
            file: File, mimeType: String, filename: String,
            extraParts: List<org.wordpress.gutenberg.http.MultipartPart>, query: String
        ): MediaUploadResponse {
            uploadCalled = true
            return mockResponse()
        }

        override suspend fun passthroughUpload(
            body: org.wordpress.gutenberg.http.RequestBody,
            contentType: String,
            query: String
        ): MediaUploadResponse {
            passthroughUploadCalled = true
            return mockResponse()
        }

        private fun mockResponse() = MediaUploadResponse(
            201,
            """{"id":99,"source_url":"https://example.com/doc.pdf","media_type":"file"}""".toByteArray()
        )
    }

}
