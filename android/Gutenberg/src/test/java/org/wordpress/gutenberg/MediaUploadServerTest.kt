package org.wordpress.gutenberg

import com.google.gson.JsonParser
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
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

        assertTrue("Expected 200 but got: ${response.statusLine}", response.statusLine.contains("200"))
        assertTrue(delegate.processFileCalled)
        assertTrue(delegate.uploadFileCalled)
        assertEquals("image/jpeg", delegate.lastMimeType)
        assertEquals("photo.jpg", delegate.lastFilename)

        val json = JsonParser.parseString(response.body).asJsonObject
        assertEquals(42, json.get("id").asInt)
        assertEquals("https://example.com/photo.jpg", json.get("url").asString)
        assertEquals("image", json.get("type").asString)
    }

    // MARK: - Fallback to default uploader

    @Test
    fun `falls back to default uploader when delegate returns nil for uploadFile`() {
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

        assertTrue("Expected 200 but got: ${response.statusLine}", response.statusLine.contains("200"))
        assertTrue(delegate.processFileCalled)
        assertTrue(mockUploader.uploadCalled)

        val json = JsonParser.parseString(response.body).asJsonObject
        assertEquals(99, json.get("id").asInt)
    }

    // MARK: - DefaultMediaUploader

    @Test
    fun `DefaultMediaUploader sends correct request to WP REST API`() {
        val mockWpServer = MockWebServer()
        // DefaultMediaUploader uses org.json.JSONObject internally which is
        // stubbed in JVM unit tests — so we only verify the outgoing request
        // format, not the response parsing.
        mockWpServer.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/json")
                .setBody(
                    """{"id":1,"source_url":"u","alt_text":"",""" +
                        """"caption":{"rendered":""},"title":{"rendered":"t"},""" +
                        """"mime_type":"image/jpeg","media_type":"image"}"""
                )
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

        // The upload call will fail at org.json parsing in JVM tests, but we
        // can still verify the request was sent correctly.
        try {
            runBlocking { uploader.upload(file, "image/jpeg", "image.jpg") }
        } catch (_: Exception) {
            // Expected — org.json stubs return defaults in JVM tests
        }

        val request = mockWpServer.takeRequest()
        assertEquals("POST", request.method)
        assertTrue(request.path!!.contains("wp/v2/media"))
        assertEquals("Bearer test-token", request.getHeader("Authorization"))
        assertTrue(request.getHeader("Content-Type")!!.contains("multipart/form-data"))

        mockWpServer.shutdown()
    }

    @Test
    fun `DefaultMediaUploader throws on server error`() {
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

        try {
            runBlocking { uploader.upload(file, "image/jpeg", "fail.jpg") }
            throw AssertionError("Expected exception")
        } catch (e: MediaUploadException) {
            assertTrue(e.message!!.contains("500"))
        }

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

        override suspend fun uploadFile(file: File, mimeType: String, filename: String): MediaUploadResult? {
            uploadFileCalled = true
            lastFilename = filename
            return MediaUploadResult(
                id = 42,
                url = "https://example.com/photo.jpg",
                title = "photo",
                mime = "image/jpeg",
                type = "image"
            )
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

        override suspend fun upload(file: File, mimeType: String, filename: String): MediaUploadResult {
            uploadCalled = true
            return MediaUploadResult(
                id = 99,
                url = "https://example.com/doc.pdf",
                title = "doc",
                mime = "application/pdf",
                type = "file"
            )
        }
    }

}
