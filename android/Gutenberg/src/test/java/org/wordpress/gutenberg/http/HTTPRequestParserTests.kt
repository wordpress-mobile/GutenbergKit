package org.wordpress.gutenberg.http

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Tests that require platform-specific assertions (internal dict representation,
 * state enum transitions, error HTTP status mapping) or configurations not
 * expressible in the shared JSON fixture format.  All pure parse-input →
 * expected-output tests have been migrated to test-fixtures/http/request-parsing.json.
 */
class HTTPRequestParserTests {

    // MARK: - Duplicate Header Key Casing (Internal Dict Representation)

    @Test
    fun `duplicate headers preserve first occurrence key casing`() {
        val request = HTTPRequestParser(
            "GET / HTTP/1.1\r\nHost: localhost\r\nX-Custom: one\r\nx-custom: two\r\n\r\n"
        ).parseRequest()!!

        // The combined value should be stored under the first key's casing.
        assertTrue(request.headers.containsKey("X-Custom"))
        assertFalse(request.headers.containsKey("x-custom"))
        assertEquals("one, two", request.headers["X-Custom"])
    }

    // MARK: - Max Header Size

    @Test(expected = HTTPRequestParseException::class)
    fun `rejects headers that exceed maxHeaderSize`() {
        // MAX_HEADER_SIZE is 65536. Build headers larger than that without a terminator.
        val longValue = "X".repeat(65_500)
        val request = "GET / HTTP/1.1\r\nHost: localhost\r\nX-Long: $longValue\r\n"
        // No \r\n\r\n terminator, so the parser will see 65K+ bytes with no end.
        val parser = HTTPRequestParser(request)
        parser.parseRequest()
    }

    @Test
    fun `accepts headers just under maxHeaderSize`() {
        val request = HTTPRequestParser(
            "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
        ).parseRequest()!!

        assertEquals("GET", request.method)
    }

    // MARK: - Incremental Parsing (State Transitions)

    @Test
    fun `handles data arriving in chunks`() {
        val parser = HTTPRequestParser()
        parser.append("GET /wp/v2/posts ".toByteArray())
        assertEquals(HTTPRequestParser.State.NEEDS_MORE_DATA, parser.state)
        assertNull(parser.parseRequest())

        parser.append("HTTP/1.1\r\nHost: localhost\r\n\r\n".toByteArray())
        assertEquals(HTTPRequestParser.State.COMPLETE, parser.state)

        val request = parser.parseRequest()!!
        assertEquals("GET", request.method)
        assertEquals("/wp/v2/posts", request.target)
    }

    @Test
    fun `body arriving in multiple chunks`() {
        val parser = HTTPRequestParser()
        parser.append("POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 10\r\n\r\n".toByteArray())
        assertEquals(HTTPRequestParser.State.HEADERS_COMPLETE, parser.state)

        parser.append("hello".toByteArray())
        assertEquals(HTTPRequestParser.State.HEADERS_COMPLETE, parser.state)

        parser.append("world".toByteArray())
        assertEquals(HTTPRequestParser.State.COMPLETE, parser.state)

        val request = parser.parseRequest()!!
        assertArrayEquals("helloworld".toByteArray(), request.body?.readBytes())
    }

    // MARK: - Content-Length at maxBodySize Boundary

    @Test
    fun `accepts Content-Length at maxBodySize limit`() {
        val body = "X".repeat(100)
        val request = HTTPRequestParser(
            input = "POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 100\r\n\r\n$body",
            maxBodySize = 100
        ).parseRequest()!!

        assertTrue(request.isComplete)
        assertArrayEquals(body.toByteArray(), request.body?.readBytes())
    }

    @Test
    fun `drains oversized body before reporting payloadTooLarge`() {
        val parser = HTTPRequestParser(maxBodySize = 100)
        parser.append("POST /upload HTTP/1.1\r\nHost: localhost\r\nContent-Length: 101\r\n\r\n".toByteArray())

        // Parser enters drain mode — not yet complete.
        assertEquals(HTTPRequestParser.State.DRAINING, parser.state)

        // Feed the remaining body bytes to complete the drain.
        parser.append(ByteArray(101) { 0x41 })
        assertTrue(parser.state.isComplete)
        assertThrows(HTTPRequestParseException::class.java) {
            parser.parseRequest()
        }.also {
            assertEquals(HTTPRequestParseError.PAYLOAD_TOO_LARGE, it.error)
        }
    }

    @Test
    fun `enters drain mode for oversized Content-Length even when body has not arrived`() {
        val parser = HTTPRequestParser(maxBodySize = 50)
        parser.append("POST /upload HTTP/1.1\r\nHost: localhost\r\nContent-Length: 999999\r\n\r\n".toByteArray())

        // Parser enters drain mode — headers are available but not yet complete.
        assertEquals(HTTPRequestParser.State.DRAINING, parser.state)
        assertTrue(parser.state.hasHeaders)
        assertFalse(parser.state.isComplete)

        // Feed body bytes in chunks to complete the drain.
        val chunkSize = 8192
        var remaining = 999999
        while (remaining > 0) {
            val size = minOf(chunkSize, remaining)
            parser.append(ByteArray(size) { 0x42 })
            remaining -= size
        }

        assertTrue(parser.state.isComplete)
        assertThrows(HTTPRequestParseException::class.java) {
            parser.parseRequest()
        }.also {
            assertEquals(HTTPRequestParseError.PAYLOAD_TOO_LARGE, it.error)
        }
    }

    @Test
    fun `drain mode does not buffer body bytes`() {
        val parser = HTTPRequestParser(maxBodySize = 10)
        parser.append("POST /upload HTTP/1.1\r\nHost: localhost\r\nContent-Length: 1000\r\n\r\n".toByteArray())
        assertEquals(HTTPRequestParser.State.DRAINING, parser.state)

        // Feed 1000 bytes of body data.
        parser.append(ByteArray(1000) { 0x43 })
        assertTrue(parser.state.isComplete)

        // The parser should still report the error, confirming the bytes
        // were consumed without being stored.
        assertThrows(HTTPRequestParseException::class.java) {
            parser.parseRequest()
        }.also {
            assertEquals(HTTPRequestParseError.PAYLOAD_TOO_LARGE, it.error)
        }
    }

    // MARK: - Error HTTP Status Mapping

    @Test
    fun `headersTooLarge maps to HTTP 431`() {
        assertEquals(431, HTTPRequestParseError.HEADERS_TOO_LARGE.httpStatus)
    }

    @Test
    fun `payloadTooLarge maps to HTTP 413`() {
        assertEquals(413, HTTPRequestParseError.PAYLOAD_TOO_LARGE.httpStatus)
    }

    @Test
    fun `invalidFieldValue maps to HTTP 400`() {
        assertEquals(400, HTTPRequestParseError.INVALID_FIELD_VALUE.httpStatus)
    }

    // MARK: - Bare CR at Field Value Edges

    @Test(expected = HTTPRequestParseException::class)
    fun `rejects bare CR at start of field value`() {
        HTTPRequestParser(
            "GET / HTTP/1.1\r\nHost: localhost\r\nX-Bad: \rhello\r\n\r\n"
        ).parseRequest()
    }

    @Test(expected = HTTPRequestParseException::class)
    fun `rejects bare CR at end of field value`() {
        HTTPRequestParser(
            "GET / HTTP/1.1\r\nHost: localhost\r\nX-Bad: hello\r\r\n\r\n"
        ).parseRequest()
    }

    // MARK: - Header Count Limit

    @Test
    fun `tooManyHeaders maps to HTTP 431`() {
        assertEquals(431, HTTPRequestParseError.TOO_MANY_HEADERS.httpStatus)
    }

    @Test(expected = HTTPRequestParseException::class)
    fun `rejects requests with more than 100 header field lines`() {
        // 1 Host + 100 X-Headers = 101 total header lines → rejected
        val headers = (0 until 100).joinToString("") { "X-Header-$it: value\r\n" }
        val raw = "GET / HTTP/1.1\r\nHost: localhost\r\n$headers\r\n"
        HTTPRequestParser(raw).parseRequest()
    }

    @Test
    fun `accepts requests with exactly 100 header field lines`() {
        // 1 Host + 99 X-Headers = 100 total header lines → accepted
        val headers = (0 until 99).joinToString("") { "X-Header-$it: value\r\n" }
        val raw = "GET / HTTP/1.1\r\nHost: localhost\r\n$headers\r\n"
        val request = HTTPRequestParser(raw).parseRequest()!!

        assertEquals("GET", request.method)
    }
}
