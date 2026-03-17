package org.wordpress.gutenberg.http

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

/**
 * Tests for the chunked (file-backed) multipart parsing path.
 *
 * The in-memory path is tested extensively in [FixtureTests] and the shared
 * JSON fixture files. These tests verify the chunked scanner that runs when
 * the body is backed by a file on disk.
 */
class ChunkedMultipartTests {

    // MARK: - Basic Parsing

    @Test
    fun `single text field parsed from file-backed body`() {
        val (file, request) = makeFileBackedRequest(
            fields = listOf(Field("title", value = "My Blog Post".toByteArray())),
            boundary = "AaB03x"
        )
        file.deleteOnExit()

        val parts = request.multipartParts()

        assertEquals(1, parts.size)
        assertEquals("title", parts[0].name)
        assertEquals(null, parts[0].filename)
        assertEquals("text/plain", parts[0].contentType)
        assertArrayEquals("My Blog Post".toByteArray(), parts[0].body.readBytes())
    }

    @Test
    fun `multiple parts parsed from file-backed body`() {
        val (file, request) = makeFileBackedRequest(
            fields = listOf(
                Field("title", value = "Hello".toByteArray()),
                Field("file", filename = "photo.jpg", contentType = "image/jpeg", value = "jpeg-data".toByteArray()),
                Field("caption", value = "A photo".toByteArray()),
            ),
            boundary = "WebKitBoundary123"
        )
        file.deleteOnExit()

        val parts = request.multipartParts()

        assertEquals(3, parts.size)
        assertEquals("title", parts[0].name)
        assertArrayEquals("Hello".toByteArray(), parts[0].body.readBytes())
        assertEquals("file", parts[1].name)
        assertEquals("photo.jpg", parts[1].filename)
        assertEquals("image/jpeg", parts[1].contentType)
        assertArrayEquals("jpeg-data".toByteArray(), parts[1].body.readBytes())
        assertEquals("caption", parts[2].name)
        assertArrayEquals("A photo".toByteArray(), parts[2].body.readBytes())
    }

    @Test
    fun `empty part body parsed correctly`() {
        val (file, request) = makeFileBackedRequest(
            fields = listOf(Field("empty", value = ByteArray(0))),
            boundary = "AaB03x"
        )
        file.deleteOnExit()

        val parts = request.multipartParts()

        assertEquals(1, parts.size)
        assertEquals("empty", parts[0].name)
        assertArrayEquals(ByteArray(0), parts[0].body.readBytes())
    }

    @Test
    fun `binary data preserved through file-backed parsing`() {
        val binaryContent = ByteArray(128) { 0x00 } +
            ByteArray(256) { it.toByte() } +
            ByteArray(128) { 0xFF.toByte() }

        val (file, request) = makeFileBackedRequest(
            fields = listOf(Field("file", filename = "binary.bin", contentType = "application/octet-stream", value = binaryContent)),
            boundary = "BinaryBoundary99"
        )
        file.deleteOnExit()

        val parts = request.multipartParts()

        assertEquals(1, parts.size)
        assertEquals("binary.bin", parts[0].filename)
        assertArrayEquals(binaryContent, parts[0].body.readBytes())
    }

    @Test
    fun `preamble before first boundary is ignored`() {
        val boundary = "AaB03x"
        val body = "This is the preamble. It should be ignored.\r\n" +
            "--$boundary\r\nContent-Disposition: form-data; name=\"field\"\r\n\r\nvalue\r\n--$boundary--\r\n"

        val (file, request) = makeFileBackedRequestFromRawBody(body, boundary)
        file.deleteOnExit()

        val parts = request.multipartParts()

        assertEquals(1, parts.size)
        assertEquals("field", parts[0].name)
        assertArrayEquals("value".toByteArray(), parts[0].body.readBytes())
    }

    @Test
    fun `transport padding after boundary is skipped`() {
        val boundary = "AaB03x"
        val body = "--$boundary  \t \r\nContent-Disposition: form-data; name=\"field\"\r\n\r\nvalue\r\n--$boundary--\r\n"

        val (file, request) = makeFileBackedRequestFromRawBody(body, boundary)
        file.deleteOnExit()

        val parts = request.multipartParts()

        assertEquals(1, parts.size)
        assertEquals("field", parts[0].name)
        assertArrayEquals("value".toByteArray(), parts[0].body.readBytes())
    }

    // MARK: - Error Cases

    @Test(expected = MultipartParseException::class)
    fun `close-delimiter-only body throws malformedBody`() {
        val boundary = "AaB03x"
        val body = "--$boundary--\r\n"

        val (file, request) = makeFileBackedRequestFromRawBody(body, boundary)
        file.deleteOnExit()

        request.multipartParts()
    }

    @Test(expected = MultipartParseException::class)
    fun `missing close delimiter throws malformedBody`() {
        val boundary = "AaB03x"
        val body = "--$boundary\r\nContent-Disposition: form-data; name=\"field\"\r\n\r\nvalue"

        val (file, request) = makeFileBackedRequestFromRawBody(body, boundary)
        file.deleteOnExit()

        request.multipartParts()
    }

    // MARK: - Chunk Boundary Edge Cases

    @Test
    fun `boundary split across chunk boundary is found correctly`() {
        val boundary = "AaB03x"
        val delimiter = "--$boundary" // 10 bytes

        // We want the second delimiter to start 5 bytes before the 65536 chunk boundary.
        val splitPoint = 65_536 - 5

        val headerBytes = "--$boundary\r\nContent-Disposition: form-data; name=\"pad\"\r\n\r\n".toByteArray()
        val headerOverhead = headerBytes.size
        val crlfBeforeDelimiter = 2
        val paddingLength = splitPoint - headerOverhead - crlfBeforeDelimiter

        val padding = ByteArray(paddingLength) { 'A'.code.toByte() }

        val (file, request) = makeFileBackedRequest(
            fields = listOf(
                Field("pad", value = padding),
                Field("after", value = "found-it".toByteArray()),
            ),
            boundary = boundary
        )
        file.deleteOnExit()

        // Verify the delimiter actually straddles the chunk boundary.
        val fileData = file.readBytes()
        val delimBytes = delimiter.toByteArray()
        val delimStart = ReadOnlyBytes(fileData).indexOf(delimBytes, headerOverhead)
        assertEquals("Delimiter should start at $splitPoint", splitPoint, delimStart)

        val parts = request.multipartParts()

        assertEquals(2, parts.size)
        assertEquals("pad", parts[0].name)
        assertEquals(paddingLength.toLong(), parts[0].body.size)
        assertEquals("after", parts[1].name)
        assertArrayEquals("found-it".toByteArray(), parts[1].body.readBytes())
    }

    @Test
    fun `large body spanning multiple chunks parses correctly`() {
        val largeContent = ByteArray(200_000) { 'X'.code.toByte() }

        val (file, request) = makeFileBackedRequest(
            fields = listOf(
                Field("large", filename = "big.bin", contentType = "application/octet-stream", value = largeContent),
                Field("meta", value = "description".toByteArray()),
            ),
            boundary = "LargeBoundary42"
        )
        file.deleteOnExit()

        val parts = request.multipartParts()

        assertEquals(2, parts.size)
        assertEquals("large", parts[0].name)
        assertEquals(largeContent.size.toLong(), parts[0].body.size)
        assertArrayEquals(largeContent, parts[0].body.readBytes())
        assertEquals("meta", parts[1].name)
        assertArrayEquals("description".toByteArray(), parts[1].body.readBytes())
    }

    // MARK: - fileSlice Source

    @Test
    fun `file-backed body with non-zero offset (fileSlice) parses correctly`() {
        val boundary = "AaB03x"
        val multipartBody = "--$boundary\r\nContent-Disposition: form-data; name=\"field\"\r\n\r\nvalue\r\n--$boundary--\r\n"
        val multipartData = multipartBody.toByteArray()

        val garbagePrefix = ByteArray(500) { 'Z'.code.toByte() }
        val file = File.createTempFile("slice-test-", null)
        file.deleteOnExit()
        file.writeBytes(garbagePrefix + multipartData)

        val body = RequestBody.FileBacked(
            file = file,
            fileOffset = garbagePrefix.size.toLong(),
            size = multipartData.size.toLong()
        )
        val request = ParsedHTTPRequest(
            method = "POST",
            target = "/upload",
            httpVersion = "HTTP/1.1",
            headers = mapOf("Content-Type" to "multipart/form-data; boundary=$boundary", "Host" to "localhost"),
            body = body,
            isComplete = true
        )

        val parts = request.multipartParts()

        assertEquals(1, parts.size)
        assertEquals("field", parts[0].name)
        assertArrayEquals("value".toByteArray(), parts[0].body.readBytes())
    }

    // MARK: - Part Count Limit

    @Test(expected = MultipartParseException::class)
    fun `rejects multipart body with more than 100 parts (in-memory)`() {
        val fields = (0 until 101).map { Field("field$it", value = "val$it".toByteArray()) }
        val bodyData = buildMultipartBody(fields, "AaB03x")
        val body = RequestBody.InMemory(bodyData)
        val request = ParsedHTTPRequest(
            method = "POST",
            target = "/upload",
            httpVersion = "HTTP/1.1",
            headers = mapOf("Content-Type" to "multipart/form-data; boundary=AaB03x", "Host" to "localhost"),
            body = body,
            isComplete = true
        )
        request.multipartParts()
    }

    @Test
    fun `accepts multipart body with exactly 100 parts (in-memory)`() {
        val fields = (0 until 100).map { Field("field$it", value = "val$it".toByteArray()) }
        val bodyData = buildMultipartBody(fields, "AaB03x")
        val body = RequestBody.InMemory(bodyData)
        val request = ParsedHTTPRequest(
            method = "POST",
            target = "/upload",
            httpVersion = "HTTP/1.1",
            headers = mapOf("Content-Type" to "multipart/form-data; boundary=AaB03x", "Host" to "localhost"),
            body = body,
            isComplete = true
        )
        val parts = request.multipartParts()
        assertEquals(100, parts.size)
    }

    @Test(expected = MultipartParseException::class)
    fun `rejects multipart body with more than 100 parts (file-backed)`() {
        val fields = (0 until 101).map { Field("field$it", value = "val$it".toByteArray()) }
        val (file, request) = makeFileBackedRequest(fields, "AaB03x")
        file.deleteOnExit()
        request.multipartParts()
    }

    @Test
    fun `accepts multipart body with exactly 100 parts (file-backed)`() {
        val fields = (0 until 100).map { Field("field$it", value = "val$it".toByteArray()) }
        val (file, request) = makeFileBackedRequest(fields, "AaB03x")
        file.deleteOnExit()
        val parts = request.multipartParts()
        assertEquals(100, parts.size)
    }

    // MARK: - Helpers

    private data class Field(
        val name: String,
        val filename: String? = null,
        val contentType: String? = null,
        val value: ByteArray
    )

    private fun makeFileBackedRequest(
        fields: List<Field>,
        boundary: String
    ): Pair<File, ParsedHTTPRequest> {
        val body = buildMultipartBody(fields, boundary)

        val file = File.createTempFile("multipart-test-", null)
        file.writeBytes(body)

        val requestBody = RequestBody.FileBacked(
            file = file,
            fileOffset = 0,
            size = body.size.toLong()
        )
        val request = ParsedHTTPRequest(
            method = "POST",
            target = "/upload",
            httpVersion = "HTTP/1.1",
            headers = mapOf("Content-Type" to "multipart/form-data; boundary=$boundary", "Host" to "localhost"),
            body = requestBody,
            isComplete = true
        )
        return file to request
    }

    private fun makeFileBackedRequestFromRawBody(
        body: String,
        boundary: String
    ): Pair<File, ParsedHTTPRequest> {
        val bodyData = body.toByteArray()
        val file = File.createTempFile("multipart-test-", null)
        file.writeBytes(bodyData)

        val requestBody = RequestBody.FileBacked(
            file = file,
            fileOffset = 0,
            size = bodyData.size.toLong()
        )
        val request = ParsedHTTPRequest(
            method = "POST",
            target = "/upload",
            httpVersion = "HTTP/1.1",
            headers = mapOf("Content-Type" to "multipart/form-data; boundary=$boundary", "Host" to "localhost"),
            body = requestBody,
            isComplete = true
        )
        return file to request
    }

    private fun buildMultipartBody(fields: List<Field>, boundary: String): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        for (field in fields) {
            out.write("--$boundary\r\n".toByteArray())
            var disposition = "Content-Disposition: form-data; name=\"${field.name}\""
            if (field.filename != null) {
                disposition += "; filename=\"${field.filename}\""
            }
            out.write("$disposition\r\n".toByteArray())
            if (field.contentType != null) {
                out.write("Content-Type: ${field.contentType}\r\n".toByteArray())
            }
            out.write("\r\n".toByteArray())
            out.write(field.value)
            out.write("\r\n".toByteArray())
        }
        out.write("--$boundary--\r\n".toByteArray())
        return out.toByteArray()
    }
}
