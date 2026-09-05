package org.wordpress.gutenberg

import com.google.gson.JsonParser
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.isActive
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.IOException
import java.net.Socket

class MediaUploadServerTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private lateinit var server: MediaUploadServer

    @Before
    fun setUp() {
        server = MediaUploadServer(
            processor = null,
            uploader = null,
            internalClient = MockInternalMediaClient(),
            cacheDir = tempFolder.root
        )
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

    @Test
    fun `stop cancels an internally-created scope but leaves a caller-supplied one alone`() {
        // No scope supplied → the server owns one, which stop() must cancel.
        val owningServer =
            MediaUploadServer(
                processor = null,
                uploader = null,
                internalClient = MockInternalMediaClient(),
                cacheDir = tempFolder.root
            )
        val ownedScope = ownedScopeOf(owningServer)
        assertNotNull("server should own a scope when none is supplied", ownedScope)
        assertTrue(ownedScope!!.isActive)
        owningServer.stop()
        assertFalse("stop() must cancel the scope it created", ownedScope.isActive)

        // A caller-supplied scope belongs to the caller — stop() must not cancel it.
        val callerScope = CoroutineScope(Dispatchers.IO)
        val borrowingServer = MediaUploadServer(
            processor = null,
            uploader = null,
            internalClient = MockInternalMediaClient(),
            cacheDir = tempFolder.root,
            scope = callerScope
        )
        assertNull("server must not own a caller-supplied scope", ownedScopeOf(borrowingServer))
        borrowingServer.stop()
        assertTrue("stop() must not cancel a caller-supplied scope", callerScope.isActive)
        callerScope.cancel()
    }

    private fun ownedScopeOf(uploadServer: MediaUploadServer): CoroutineScope? {
        val field = MediaUploadServer::class.java.getDeclaredField("ownedScope")
        field.isAccessible = true
        return field.get(uploadServer) as CoroutineScope?
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

    @Test
    fun `relays a deletion to the internal media client even when an uploader owns uploads`() {
        // An attachment lives on the configured site even when a host uploader
        // delivered it, so its deletion goes to the internal media client — the host
        // uploader owns uploads, not deletes.
        val uploader = MockUploader()
        val internalClient = MockInternalMediaClient()
        server.stop()
        server = MediaUploadServer(
            processor = null,
            uploader = uploader,
            internalClient = internalClient,
            cacheDir = tempFolder.root
        )

        val response = sendRawRequest(
            method = "DELETE",
            path = "/media/42?force=true",
            headers = mapOf("Relay-Authorization" to "Bearer ${server.token}"),
            body = ByteArray(0)
        )

        assertTrue("Expected 200 but got: ${response.statusLine}", response.statusLine.contains("200"))
        assertTrue(internalClient.deleteMediaCalled)
        assertEquals("42", internalClient.deletedAttachmentId)
    }

    // MARK: - Media deletion

    @Test
    fun `relays a deletion to the internal media client (configured site)`() {
        // With no uploader set, GutenbergKit owns deletes: core's orphan cleanup
        // DELETE is relayed to the internal media client (the configured site).
        val mockUploader = MockInternalMediaClient()
        server.stop()
        server = MediaUploadServer(
            processor = null,
            uploader = null,
            internalClient = mockUploader,
            cacheDir = tempFolder.root
        )

        val response = sendRawRequest(
            method = "DELETE",
            path = "/media/512?force=true",
            headers = mapOf("Relay-Authorization" to "Bearer ${server.token}"),
            body = ByteArray(0)
        )

        assertTrue("Expected 200 but got: ${response.statusLine}", response.statusLine.contains("200"))
        assertTrue(mockUploader.deleteMediaCalled)
        assertEquals("512", mockUploader.deletedAttachmentId)
    }

    @Test
    fun `routes upload with a query string and relays the query`() {
        val processor = PassthroughProcessor()
        val mockUploader = MockInternalMediaClient()
        server.stop()
        server = MediaUploadServer(processor = processor, uploader = null, internalClient = mockUploader, cacheDir = tempFolder.root)

        // `@wordpress/media-utils` uploads to `/wp/v2/media?_embed=wp:featuredmedia`,
        // so the middleware forwards that query on to the native server. Routing must
        // match on the path alone, and the query must reach WordPress unchanged.
        val boundary = "test-boundary-query"
        val body = buildMultipartBody(boundary, "photo.jpg", "image/jpeg", "fake image data".toByteArray())

        val response = sendRawRequest(
            method = "POST",
            path = "/upload?_embed=wp:featuredmedia",
            headers = mapOf(
                "Relay-Authorization" to "Bearer ${server.token}",
                "Content-Type" to "multipart/form-data; boundary=$boundary"
            ),
            body = body
        )

        assertTrue("Expected 201 but got: ${response.statusLine}", response.statusLine.contains("201"))
        // The processor returns Original, so this is the passthrough branch.
        // Pin which branch ran — `lastQuery` is recorded by both, so without this
        // the query assertion would pass even if routing collapsed onto one path.
        assertTrue(mockUploader.passthroughUploadCalled)
        assertFalse(mockUploader.uploadCalled)
        assertEquals("?_embed=wp:featuredmedia", mockUploader.lastQuery)
    }

    // MARK: - Upload with a processor or uploader

    @Test
    fun `routes an upload to the uploader and relays its attachment`() {
        // With an uploader set, GutenbergKit hands it the file and relays the finished
        // attachment it returns — the internal media client (configured site) is never used.
        val uploader = MockUploader()
        val internalClient = MockInternalMediaClient()
        server.stop()
        server = MediaUploadServer(
            processor = null,
            uploader = uploader,
            internalClient = internalClient,
            cacheDir = tempFolder.root
        )

        val boundary = "test-boundary-123"
        val body = buildMultipartBody(
            boundary, "photo.jpg", "image/jpeg", "fake image data".toByteArray(),
            fields = listOf(MediaUploadField("post", "123"))
        )

        val response = sendRawRequest(
            method = "POST",
            path = "/upload?_embed=wp:featuredmedia",
            headers = mapOf(
                "Relay-Authorization" to "Bearer ${server.token}",
                "Content-Type" to "multipart/form-data; boundary=$boundary"
            ),
            body = body
        )

        assertTrue("Expected 201 but got: ${response.statusLine}", response.statusLine.contains("201"))
        assertTrue(uploader.uploadCalled)
        assertEquals("image/jpeg", uploader.lastMimeType)
        assertEquals("photo.jpg", uploader.lastFilename)
        // The editor's post association and query must reach the host uploader, so it
        // can reproduce a native upload (attach to the post, honor ?_embed).
        assertEquals("123", uploader.lastFields.first { it.name == "post" }.value)
        assertEquals("?_embed=wp:featuredmedia", uploader.lastQuery)
        // …and the actual file bytes the editor sent — the host uploads them itself.
        assertEquals("fake image data", uploader.lastFileBytes?.decodeToString())
        // The host owns delivery — GutenbergKit must not upload to the configured site.
        assertFalse(internalClient.uploadCalled)
        assertFalse(internalClient.passthroughUploadCalled)

        // The server relays the exact attachment JSON the uploader returned.
        val json = JsonParser.parseString(response.body).asJsonObject
        assertEquals(42, json.get("id").asInt)
        assertEquals("https://example.com/photo.jpg", json.get("source_url").asString)
        assertEquals("image", json.get("media_type").asString)
    }

    @Test
    fun `hands a host uploader repeated form field names in order, not collapsed`() {
        // A `field[]`-style repeated name (e.g. a custom attachment taxonomy): WordPress
        // builds an array from these, so both values must reach the host uploader in
        // order. A map would drop the first — the ordered-list contract must not.
        val uploader = MockUploader()
        val internalClient = MockInternalMediaClient()
        server.stop()
        server = MediaUploadServer(
            processor = null,
            uploader = uploader,
            internalClient = internalClient,
            cacheDir = tempFolder.root
        )

        val boundary = "test-boundary-123"
        val body = buildMultipartBody(
            boundary, "photo.jpg", "image/jpeg", "fake image data".toByteArray(),
            fields = listOf(
                MediaUploadField("post", "123"),
                MediaUploadField("media_folder[]", "12"),
                MediaUploadField("media_folder[]", "45")
            )
        )

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
        assertTrue(uploader.uploadCalled)
        // Both repeated values survive, in order — not collapsed to the last.
        assertEquals(
            listOf("12", "45"),
            uploader.lastFields.filter { it.name == "media_folder[]" }.map { it.value }
        )
        assertEquals("123", uploader.lastFields.first { it.name == "post" }.value)
    }

    @Test
    fun `keeps a filename-bearing part out of the fields handed to an uploader`() {
        // Pins the invariant that makes the UTF-8 decode of `fields` lossless. A browser
        // FormData can only carry arbitrary bytes as a Blob, and a Blob always gets a
        // filename, so the partition on `filename == null` is what keeps binary out of
        // `fields`. Change it and the decode silently substitutes U+FFFD — and does so
        // differently from iOS.
        //
        // Deliberately not asserted: what becomes of the second filename-bearing part.
        // It is currently dropped rather than relayed, which is a separate open question.
        val uploader = MockUploader()
        val internalClient = MockInternalMediaClient()
        server.stop()
        server = MediaUploadServer(
            processor = null,
            uploader = uploader,
            internalClient = internalClient,
            cacheDir = tempFolder.root
        )

        val boundary = "test-boundary-123"
        val out = java.io.ByteArrayOutputStream()
        // A plain field — no filename, so it belongs in `fields`.
        out.write("--$boundary\r\n".toByteArray())
        out.write("Content-Disposition: form-data; name=\"post\"\r\n\r\n".toByteArray())
        out.write("123".toByteArray())
        out.write("\r\n".toByteArray())
        // The file.
        out.write("--$boundary\r\n".toByteArray())
        out.write("Content-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\r\n".toByteArray())
        out.write("Content-Type: image/jpeg\r\n\r\n".toByteArray())
        out.write("fake image data".toByteArray())
        out.write("\r\n".toByteArray())
        // A Blob-shaped sidecar: filename present, bytes not valid UTF-8. If the
        // partition admitted this to `fields`, the lone 0xFF would become U+FFFD.
        out.write("--$boundary\r\n".toByteArray())
        out.write("Content-Disposition: form-data; name=\"sidecar\"; filename=\"blob\"\r\n".toByteArray())
        out.write("Content-Type: application/octet-stream\r\n\r\n".toByteArray())
        out.write(byteArrayOf(0x61, 0xFF.toByte(), 0x62))
        out.write("\r\n--$boundary--\r\n".toByteArray())

        sendRawRequest(
            method = "POST",
            path = "/upload",
            headers = mapOf(
                "Relay-Authorization" to "Bearer ${server.token}",
                "Content-Type" to "multipart/form-data; boundary=$boundary"
            ),
            body = out.toByteArray()
        )

        assertTrue(uploader.uploadCalled)
        assertEquals(
            "only filename-less parts belong in fields",
            listOf("post"),
            uploader.lastFields.map { it.name }
        )
        assertTrue(
            "no field value should have been lossily decoded",
            uploader.lastFields.none { it.value.contains('�') }
        )
    }

    @Test
    fun `hands the processed file and its new metadata to the uploader`() {
        // A processor transcodes the file; the host uploader must receive the processed
        // bytes and the new metadata, not the original clip.mov.
        val processor = TranscodingProcessor()
        val uploader = MockUploader()
        server.stop()
        server = MediaUploadServer(
            processor = processor,
            uploader = uploader,
            internalClient = MockInternalMediaClient(),
            cacheDir = tempFolder.root
        )

        val boundary = "test-boundary-proc"
        val body = buildMultipartBody(boundary, "clip.mov", "video/quicktime", "movie".toByteArray())

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
        assertTrue(uploader.uploadCalled)
        assertEquals("processed", uploader.lastFileBytes?.decodeToString())
        assertEquals("video/mp4", uploader.lastMimeType)
        assertEquals("clip.mp4", uploader.lastFilename)
    }

    @Test
    fun `relays a 500 when the host uploader throws`() {
        val uploader = MockUploader(error = RuntimeException("upload failed"))
        server.stop()
        server = MediaUploadServer(
            processor = null,
            uploader = uploader,
            internalClient = MockInternalMediaClient(),
            cacheDir = tempFolder.root
        )

        val boundary = "test-boundary-err"
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

        assertTrue("Expected 500 but got: ${response.statusLine}", response.statusLine.contains("500"))
        assertTrue(uploader.uploadCalled)
    }

    @Test
    fun `forwards the processor's processed metadata to the uploader`() {
        val processor = TranscodingProcessor()
        val mockUploader = MockInternalMediaClient()
        server.stop()
        server = MediaUploadServer(processor = processor, uploader = null, internalClient = mockUploader, cacheDir = tempFolder.root)

        val boundary = "test-boundary-meta"
        val body = buildMultipartBody(boundary, "clip.mov", "video/quicktime", "movie".toByteArray())

        sendRawRequest(
            method = "POST",
            path = "/upload",
            headers = mapOf(
                "Relay-Authorization" to "Bearer ${server.token}",
                "Content-Type" to "multipart/form-data; boundary=$boundary"
            ),
            body = body
        )

        // The processor changed the format, so the uploader must receive the new
        // metadata — not the original video/quicktime + clip.mov.
        assertTrue(mockUploader.uploadCalled)
        assertEquals("video/mp4", mockUploader.lastUploadMimeType)
        assertEquals("clip.mp4", mockUploader.lastUploadFilename)
    }

    @Test
    fun `deletes the processor's processed file after upload`() {
        val processor = TranscodingProcessor()
        val mockUploader = MockInternalMediaClient()
        server.stop()
        server = MediaUploadServer(processor = processor, uploader = null, internalClient = mockUploader, cacheDir = tempFolder.root)

        val boundary = "test-boundary-cleanup"
        val body = buildMultipartBody(boundary, "clip.mov", "video/quicktime", "movie".toByteArray())

        sendRawRequest(
            method = "POST",
            path = "/upload",
            headers = mapOf(
                "Relay-Authorization" to "Bearer ${server.token}",
                "Content-Type" to "multipart/form-data; boundary=$boundary"
            ),
            body = body
        )

        // The server owns the file the processor produced and must delete it once the
        // upload finishes — the finally in processAndUpload covers success and throw
        // paths alike. A leaked processed file is a full-size temp per upload.
        val processed = requireNotNull(processor.producedFile) { "processFile was not called" }
        assertFalse("Processed temp file should be deleted after upload", processed.exists())
    }

    @Test
    fun `startup sweep deletes stale upload temps but preserves fresh ones`() {
        val uploadsDir = File(tempFolder.root, "gutenbergkit-uploads").apply { mkdirs() }
        val stale = File(uploadsDir, "stale.tmp").apply { writeText("x") }
        val fresh = File(uploadsDir, "fresh.tmp").apply { writeText("y") }
        // Backdate the stale file well past the 1-hour cutoff.
        assertTrue(
            "Could not backdate the stale file",
            stale.setLastModified(System.currentTimeMillis() - 2 * 60 * 60 * 1000L)
        )

        // The sweep runs via the injected dispatcher; Unconfined runs it synchronously
        // so we can assert immediately. It must delete the aged file and keep the fresh
        // one — a flipped comparison would do the opposite and wipe an in-flight upload.
        server.stop()
        server = MediaUploadServer(
            processor = null,
            uploader = null,
            internalClient = MockInternalMediaClient(),
            cacheDir = tempFolder.root,
            ioDispatcher = Dispatchers.Unconfined
        )

        assertFalse("Stale temp should have been swept", stale.exists())
        assertTrue("Fresh temp should be preserved", fresh.exists())
    }

    // MARK: - Fallback to internal media client

    @Test
    fun `uses passthrough when the processor does not modify the file`() {
        val processor = PassthroughProcessor()
        val mockUploader = MockInternalMediaClient()

        server.stop()
        server = MediaUploadServer(processor = processor, uploader = null, internalClient = mockUploader, cacheDir = tempFolder.root)

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
        assertTrue(processor.processFileCalled)
        // Passthrough: original body forwarded directly, not re-encoded.
        assertTrue(mockUploader.passthroughUploadCalled)
        assertFalse(mockUploader.uploadCalled)

        val json = JsonParser.parseString(response.body).asJsonObject
        assertEquals(99, json.get("id").asInt)
    }

    @Test
    fun `skips processing and the temp copy when the processor declines by metadata`() {
        val processor = DecliningProcessor()
        val mockUploader = MockInternalMediaClient()

        server.stop()
        server = MediaUploadServer(processor = processor, uploader = null, internalClient = mockUploader, cacheDir = tempFolder.root)

        val boundary = "test-boundary-decline"
        val body = buildMultipartBody(boundary, "clip.mov", "video/quicktime", "fake movie".toByteArray())

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
        // Declined by metadata → the processor is never asked to process (so the
        // file was never materialized), and the upload is passed through directly.
        assertFalse(processor.processFileCalled)
        assertTrue(mockUploader.passthroughUploadCalled)
        assertFalse(mockUploader.uploadCalled)
    }

    // MARK: - InternalMediaClient

    @Test
    fun `InternalMediaClient relays the WordPress response`() {
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
        val uploader = InternalMediaClient(
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
    fun `InternalMediaClient relays a WordPress error response instead of throwing`() {
        val mockWpServer = MockWebServer()
        mockWpServer.enqueue(MockResponse().setResponseCode(500).setBody("Internal error"))
        mockWpServer.start()

        val wpBaseUrl = mockWpServer.url("/wp-json/").toString()
        val uploader = InternalMediaClient(
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
    fun `InternalMediaClient relays the upload attachment ID header`() {
        // WordPress sets this header on an upload whose attachment row was
        // created before metadata generation fataled. The editor reads it to
        // retry post-process and clean up the orphan, so it must survive the
        // relay. Unrelated upstream headers are not relayed.
        val mockWpServer = MockWebServer()
        mockWpServer.enqueue(
            MockResponse()
                .setResponseCode(500)
                .setBody("""{"code":"rest_upload_error"}""")
                .setHeader("x-wp-upload-attachment-id", "4242")
                .setHeader("X-Powered-By", "PHP/8.2")
        )
        mockWpServer.start()

        val uploader = InternalMediaClient(
            httpClient = okhttp3.OkHttpClient(),
            siteApiRoot = mockWpServer.url("/wp-json/").toString(),
            authHeader = "Bearer test-token"
        )

        val file = tempFolder.newFile("orphan.jpg")
        file.writeBytes("data".toByteArray())

        val response = runBlocking { uploader.upload(file, "image/jpeg", "orphan.jpg", emptyList(), "") }

        assertEquals(500, response.statusCode)
        assertEquals(mapOf("x-wp-upload-attachment-id" to "4242"), response.headers)

        mockWpServer.shutdown()
    }

    @Test
    fun `InternalMediaClient deletes an attachment carrying namespace and force query`() {
        val mockWpServer = MockWebServer()
        mockWpServer.enqueue(MockResponse().setResponseCode(200).setBody("""{"deleted":true}"""))
        mockWpServer.start()

        val uploader = InternalMediaClient(
            httpClient = okhttp3.OkHttpClient(),
            siteApiRoot = mockWpServer.url("/wp-json/").toString(),
            authHeader = "Bearer test-token",
            siteApiNamespace = listOf("sites/123")
        )

        val response = runBlocking { uploader.deleteMedia("42", "?force=true") }

        assertEquals(200, response.statusCode)
        val recorded = mockWpServer.takeRequest()
        assertEquals("DELETE", recorded.method)
        assertEquals("/wp-json/wp/v2/sites/123/media/42?force=true", recorded.path)

        mockWpServer.shutdown()
    }

    @Test
    fun `InternalMediaClient normalizes an unslashed root and namespace`() {
        val mockWpServer = MockWebServer()
        mockWpServer.enqueue(MockResponse().setResponseCode(201).setBody("{}"))
        mockWpServer.start()

        val uploader = InternalMediaClient(
            httpClient = okhttp3.OkHttpClient(),
            siteApiRoot = mockWpServer.url("/wp-json").toString(), // no trailing slash
            authHeader = "Bearer test-token",
            siteApiNamespace = listOf("sites/123") // no trailing slash
        )
        val file = tempFolder.newFile("image.jpg")
        file.writeBytes("x".toByteArray())

        runBlocking { uploader.upload(file, "image/jpeg", "image.jpg", emptyList(), "") }

        assertEquals("/wp-json/wp/v2/sites/123/media", mockWpServer.takeRequest().path)

        mockWpServer.shutdown()
    }

    @Test
    fun `upload surfaces an error instead of hanging when the response body is truncated after headers`() {
        // Regression test: WordPress sends the 201 status line + headers, then the
        // body is truncated mid-transfer. OkHttp delivers onResponse for the 201 and
        // the body read throws there — a throw OkHttp swallows rather than routing to
        // onFailure. The upload must surface that as an error, not suspend forever
        // holding a connection permit.
        val mockWpServer = MockWebServer()
        mockWpServer.enqueue(
            MockResponse()
                .setResponseCode(201)
                .setBody("x".repeat(2048)) // large enough that DISCONNECT truncates it mid-body
                .setSocketPolicy(SocketPolicy.DISCONNECT_DURING_RESPONSE_BODY)
        )
        mockWpServer.start()

        val uploader = InternalMediaClient(
            httpClient = okhttp3.OkHttpClient(),
            siteApiRoot = mockWpServer.url("/wp-json/").toString(),
            authHeader = "Bearer test-token"
        )
        val file = tempFolder.newFile("image.jpg")
        file.writeBytes("fake image".toByteArray())

        // withTimeout is the regression guard: without the fix the coroutine never
        // resumes, so this fails with a TimeoutCancellationException instead of the
        // expected IOException.
        val error = runCatching {
            runBlocking {
                withTimeout(5_000) {
                    uploader.upload(file, "image/jpeg", "image.jpg", emptyList(), "")
                }
            }
        }.exceptionOrNull()

        assertTrue(
            "Expected an IOException from the truncated body, got: $error",
            error is IOException
        )

        mockWpServer.shutdown()
    }

    @Test
    fun `InternalMediaClient re-encode preserves extra parts and query`() {
        val mockWpServer = MockWebServer()
        mockWpServer.enqueue(MockResponse().setResponseCode(201).setBody("{}"))
        mockWpServer.start()

        val uploader = InternalMediaClient(
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

    @Test
    fun `re-encode forwards a non-UTF-8 field value verbatim`() {
        val mockWpServer = MockWebServer()
        mockWpServer.enqueue(MockResponse().setResponseCode(201).setBody("{}"))
        mockWpServer.start()

        val uploader = InternalMediaClient(
            httpClient = okhttp3.OkHttpClient(),
            siteApiRoot = mockWpServer.url("/wp-json/").toString(),
            authHeader = "Bearer test-token"
        )
        val file = tempFolder.newFile("image.jpg")
        file.writeBytes("fake image".toByteArray())

        // A value that is not valid UTF-8 (a lone 0xFF byte between two ASCII bytes).
        val binaryValue = byteArrayOf(0x61, 0xFF.toByte(), 0x62)
        val blobPart = org.wordpress.gutenberg.http.MultipartPart(
            name = "blob",
            filename = null,
            contentType = "application/octet-stream",
            body = org.wordpress.gutenberg.http.RequestBody.InMemory(binaryValue)
        )

        runBlocking {
            uploader.upload(file, "image/jpeg", "image.jpg", listOf(blobPart), "")
        }

        // The raw 0xFF byte survives verbatim — not coerced to a replacement char.
        val bodyBytes = mockWpServer.takeRequest().body.readByteArray()
        val found = bodyBytes.toList().windowed(binaryValue.size).any { it == binaryValue.toList() }
        assertTrue("Non-UTF-8 field value should pass through verbatim", found)

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
        val body: String,
        /** The header lines exactly as received, before collapsing into [headers]. */
        val rawHeaderLines: List<String> = emptyList()
    ) {
        /**
         * Every value sent for [name], in order. Unlike [headers], this preserves
         * repeats — the only way to catch a header emitted twice.
         */
        fun rawHeaderValues(name: String): List<String> =
            rawHeaderLines.mapNotNull { line ->
                val colonIndex = line.indexOf(':')
                if (colonIndex <= 0) return@mapNotNull null
                if (!line.substring(0, colonIndex).trim().equals(name, ignoreCase = true)) return@mapNotNull null
                line.substring(colonIndex + 1).trim()
            }
    }

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

        return RawHttpResponse(statusLine, responseHeaders, responseBody, lines.drop(1))
    }

    private fun buildMultipartBody(
        boundary: String,
        filename: String,
        mimeType: String,
        data: ByteArray,
        fields: List<MediaUploadField> = emptyList()
    ): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        for ((name, value) in fields) {
            out.write("--$boundary\r\n".toByteArray())
            out.write("Content-Disposition: form-data; name=\"$name\"\r\n\r\n".toByteArray())
            out.write(value.toByteArray())
            out.write("\r\n".toByteArray())
        }
        out.write("--$boundary\r\n".toByteArray())
        out.write("Content-Disposition: form-data; name=\"file\"; filename=\"$filename\"\r\n".toByteArray())
        out.write("Content-Type: $mimeType\r\n\r\n".toByteArray())
        out.write(data)
        out.write("\r\n--$boundary--\r\n".toByteArray())
        return out.toByteArray()
    }

    // MARK: - Mocks

    /**
     * A host uploader: it performs the upload on its own stack. `upload` returns the
     * finished attachment JSON (or throws).
     */
    private class MockUploader(
        private val uploadBody: ByteArray =
            """{"id":42,"source_url":"https://example.com/photo.jpg","media_type":"image"}""".toByteArray(),
        private val error: Exception? = null
    ) : MediaUploader {
        @Volatile var uploadCalled = false
        @Volatile var lastMimeType: String? = null
        @Volatile var lastFilename: String? = null
        @Volatile var lastFields: List<MediaUploadField> = emptyList()
        @Volatile var lastQuery: String? = null
        @Volatile var lastFileBytes: ByteArray? = null

        override suspend fun upload(upload: MediaUpload): ByteArray {
            uploadCalled = true
            lastMimeType = upload.mimeType
            lastFilename = upload.filename
            lastFields = upload.fields
            lastQuery = upload.query
            lastFileBytes = upload.file.readBytes()
            error?.let { throw it }
            return uploadBody
        }
    }

    private class PassthroughProcessor : MediaProcessor {
        @Volatile var processFileCalled = false

        override suspend fun processFile(file: File, mimeType: String, filename: String): ProcessedProxyFile {
            processFileCalled = true
            return ProcessedProxyFile.Original
        }
    }

    /**
     * Declines every file by metadata via [handlesFile], so the server must pass
     * through without materializing the file or calling [processFile].
     */
    private class DecliningProcessor : MediaProcessor {
        @Volatile var processFileCalled = false

        override fun handlesFile(mimeType: String, filename: String): Boolean = false

        override suspend fun processFile(file: File, mimeType: String, filename: String): ProcessedProxyFile {
            processFileCalled = true
            return ProcessedProxyFile.Original
        }
    }

    /** A processor that produces a new file with changed metadata (e.g. a transcode). */
    private class TranscodingProcessor : MediaProcessor {
        /** The processed file this processor wrote, for cleanup assertions. */
        @Volatile var producedFile: File? = null

        override suspend fun processFile(file: File, mimeType: String, filename: String): ProcessedProxyFile {
            val newFile = File(file.parentFile, "processed-${file.name}")
            newFile.writeBytes("processed".toByteArray())
            producedFile = newFile
            return ProcessedProxyFile.Processed(newFile, "video/mp4", "clip.mp4")
        }
    }

    private class MockInternalMediaClient(
        /** The response `upload`/`passthroughUpload` return. Defaults to a 201 success. */
        private val uploadResponse: MediaUploadResponse = MediaUploadResponse(
            201,
            """{"id":99,"source_url":"https://example.com/doc.pdf","media_type":"file"}""".toByteArray()
        )
    ) : InternalMediaClient(
        httpClient = okhttp3.OkHttpClient(),
        siteApiRoot = "https://example.com/wp-json/",
        authHeader = "Bearer mock"
    ) {
        @Volatile var uploadCalled = false
        @Volatile var passthroughUploadCalled = false
        @Volatile var lastUploadMimeType: String? = null
        @Volatile var lastUploadFilename: String? = null
        @Volatile var lastQuery: String? = null
        @Volatile var deleteMediaCalled = false
        @Volatile var deletedAttachmentId: String? = null

        override suspend fun upload(
            file: File, mimeType: String, filename: String,
            extraParts: List<org.wordpress.gutenberg.http.MultipartPart>, query: String
        ): MediaUploadResponse {
            uploadCalled = true
            lastUploadMimeType = mimeType
            lastUploadFilename = filename
            lastQuery = query
            return uploadResponse
        }

        override suspend fun passthroughUpload(
            body: org.wordpress.gutenberg.http.RequestBody,
            contentType: String,
            query: String
        ): MediaUploadResponse {
            passthroughUploadCalled = true
            lastQuery = query
            return uploadResponse
        }

        override suspend fun deleteMedia(attachmentId: String, query: String): MediaUploadResponse {
            deleteMediaCalled = true
            deletedAttachmentId = attachmentId
            return MediaUploadResponse(200, """{"deleted":true}""".toByteArray())
        }
    }

}
