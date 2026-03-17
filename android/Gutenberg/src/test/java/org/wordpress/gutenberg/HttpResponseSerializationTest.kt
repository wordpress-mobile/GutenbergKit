package org.wordpress.gutenberg

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HttpResponseSerializationTest {

    @Test
    fun `Content-Length always matches actual body size`() {
        val response = HttpResponse(
            headers = mapOf("Content-Type" to "text/plain"),
            body = "hello".toByteArray()
        )
        val serialized = String(HttpServer.serializeResponse(response))

        assertTrue("Should contain Content-Length: 5", serialized.contains("Content-Length: 5\r\n"))
    }

    @Test
    fun `caller-provided Content-Length is replaced with actual body size`() {
        val response = HttpResponse(
            headers = mapOf("Content-Length" to "999", "Content-Type" to "text/plain"),
            body = "hello".toByteArray()
        )
        val serialized = String(HttpServer.serializeResponse(response))

        assertFalse("Wrong Content-Length must not appear", serialized.contains("Content-Length: 999"))
        assertTrue("Correct Content-Length must be present", serialized.contains("Content-Length: 5\r\n"))
    }

    @Test
    fun `case-insensitive Content-Length replacement`() {
        val response = HttpResponse(
            headers = mapOf("content-length" to "0", "Content-Type" to "text/plain"),
            body = "test body".toByteArray()
        )
        val serialized = String(HttpServer.serializeResponse(response))

        assertFalse("Wrong content-length must not appear", serialized.contains("content-length: 0"))
        assertTrue("Correct Content-Length must be present", serialized.contains("Content-Length: 9\r\n"))
    }

    @Test
    fun `Connection close is added when not present`() {
        val response = HttpResponse(body = "ok".toByteArray())
        val serialized = String(HttpServer.serializeResponse(response))

        assertTrue("Should contain Connection: close", serialized.contains("Connection: close\r\n"))
    }

    @Test
    fun `hop-by-hop Connection header is stripped and replaced with close`() {
        val response = HttpResponse(
            headers = mapOf("Connection" to "keep-alive"),
            body = "ok".toByteArray()
        )
        val serialized = String(HttpServer.serializeResponse(response))

        assertFalse("Hop-by-hop Connection must be stripped", serialized.contains("Connection: keep-alive"))
        assertTrue("Connection: close must be present", serialized.contains("Connection: close"))
    }

    @Test
    fun `hop-by-hop Transfer-Encoding header is stripped`() {
        val response = HttpResponse(
            headers = mapOf("Transfer-Encoding" to "chunked", "Content-Type" to "text/plain"),
            body = "ok".toByteArray()
        )
        val serialized = String(HttpServer.serializeResponse(response))

        assertFalse("Transfer-Encoding must be stripped", serialized.contains("Transfer-Encoding"))
    }

    @Test
    fun `401 response with WWW-Authenticate header serializes correctly`() {
        val response = HttpResponse(
            status = 401,
            headers = mapOf("WWW-Authenticate" to "Bearer")
        )
        val serialized = String(HttpServer.serializeResponse(response))

        assertTrue("Should start with 401 status line", serialized.startsWith("HTTP/1.1 401 Unauthorized\r\n"))
        assertTrue("Should contain WWW-Authenticate header", serialized.contains("WWW-Authenticate: Bearer\r\n"))
    }

    @Test
    fun `header values are sanitized`() {
        val response = HttpResponse(
            headers = mapOf("X-Test" to "value\u0007bell"),
            body = ByteArray(0)
        )
        val serialized = String(HttpServer.serializeResponse(response))

        assertFalse("BEL should be stripped", serialized.contains("\u0007"))
        assertTrue("Cleaned value present", serialized.contains("X-Test: valuebell"))
    }

    @Test
    fun `sanitize preserves obs-text (0x80+) per RFC 9110`() {
        val response = HttpResponse(
            headers = mapOf("X-Test" to "caf\u00e9"),
            body = ByteArray(0)
        )
        val serialized = String(HttpServer.serializeResponse(response))

        assertTrue("obs-text characters must be preserved", serialized.contains("X-Test: caf\u00e9"))
    }

    @Test
    fun `sanitize preserves HTAB in header values`() {
        val response = HttpResponse(
            headers = mapOf("X-Test" to "a\tb"),
            body = ByteArray(0)
        )
        val serialized = String(HttpServer.serializeResponse(response))

        assertTrue("HTAB must be preserved", serialized.contains("X-Test: a\tb"))
    }

    @Test
    fun `Date header is present in RFC 9110 HTTP-date format`() {
        val serialized = String(HttpServer.serializeResponse(HttpResponse()))

        val datePattern = Regex("""Date: \w{3}, \d{2} \w{3} \d{4} \d{2}:\d{2}:\d{2} GMT\r\n""")
        assertTrue("Date header must be present in HTTP-date format", datePattern.containsMatchIn(serialized))
    }

    @Test
    fun `Server header is present`() {
        val serialized = String(HttpServer.serializeResponse(HttpResponse()))

        assertTrue("Server header must be present", serialized.contains("Server: GutenbergKit\r\n"))
    }

    @Test
    fun `caller-provided Date header is replaced`() {
        val response = HttpResponse(
            headers = mapOf("Date" to "Thu, 01 Jan 1970 00:00:00 GMT"),
            body = ByteArray(0)
        )
        val serialized = String(HttpServer.serializeResponse(response))

        // The old date must not appear; a fresh one is generated
        val dateCount = Regex("""Date:""").findAll(serialized).count()
        assertEquals("Exactly one Date header", 1, dateCount)
        assertFalse("Caller-provided Date must be replaced", serialized.contains("Date: Thu, 01 Jan 1970"))
    }

    @Test
    fun `caller-provided Server header is replaced`() {
        val response = HttpResponse(
            headers = mapOf("Server" to "Apache"),
            body = ByteArray(0)
        )
        val serialized = String(HttpServer.serializeResponse(response))

        assertFalse("Caller-provided Server must be stripped", serialized.contains("Server: Apache"))
        assertTrue("Server: GutenbergKit must be present", serialized.contains("Server: GutenbergKit"))
    }
}
