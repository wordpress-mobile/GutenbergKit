package org.wordpress.gutenberg.http

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ParsedHTTPRequestTests {

    // MARK: - Case-insensitive Authorization header lookup (fix #1 regression test)

    @Test
    fun `header returns Authorization value with lowercase header name`() {
        // HTTP header names are case-insensitive per RFC 9110 §5.1.
        // The server uses header("Authorization") to authenticate — a client
        // sending "authorization" (lowercase) must be matched.
        val request = ParsedHTTPRequest(
            method = "GET",
            target = "/wp/v2/posts",
            httpVersion = "HTTP/1.1",
            headers = mapOf("authorization" to "Bearer tok123"),
            body = null,
            isComplete = true
        )

        assertEquals("Bearer tok123", request.header("Authorization"))
        assertEquals("Bearer tok123", request.header("authorization"))
        assertEquals("Bearer tok123", request.header("AUTHORIZATION"))
    }

    @Test
    fun `header returns Authorization value with mixed-case header name`() {
        val request = ParsedHTTPRequest(
            method = "GET",
            target = "/wp/v2/posts",
            httpVersion = "HTTP/1.1",
            headers = mapOf("AUTHORIZATION" to "Bearer secret"),
            body = null,
            isComplete = true
        )

        assertEquals("Bearer secret", request.header("Authorization"))
        assertEquals("Bearer secret", request.header("authorization"))
    }

    @Test
    fun `header returns null for missing Authorization`() {
        val request = ParsedHTTPRequest(
            method = "GET",
            target = "/wp/v2/posts",
            httpVersion = "HTTP/1.1",
            headers = mapOf("Accept" to "application/json"),
            body = null,
            isComplete = true
        )

        assertNull(request.header("Authorization"))
    }

    // MARK: - Case-insensitive Connection header lookup (fix #2 regression test)

    @Test
    fun `header returns Connection value with lowercase header name`() {
        val request = ParsedHTTPRequest(
            method = "GET",
            target = "/wp/v2/posts",
            httpVersion = "HTTP/1.1",
            headers = mapOf("connection" to "keep-alive"),
            body = null,
            isComplete = true
        )

        assertEquals("keep-alive", request.header("Connection"))
        assertEquals("keep-alive", request.header("connection"))
        assertEquals("keep-alive", request.header("CONNECTION"))
    }

    // MARK: - forwardingHeaders

    @Test
    fun `forwardingHeaders strips standard hop-by-hop headers`() {
        val request = ParsedHTTPRequest(
            method = "GET",
            target = "/wp/v2/posts",
            httpVersion = "HTTP/1.1",
            headers = mapOf(
                "Host" to "localhost",
                "Connection" to "keep-alive",
                "Transfer-Encoding" to "chunked",
                "Keep-Alive" to "timeout=5",
                "Accept" to "application/json",
                "Content-Type" to "text/plain"
            ),
            body = null,
            isComplete = true
        )

        val forwarded = request.forwardingHeaders()
        assertFalse(forwarded.keys.any { it.equals("Host", ignoreCase = true) })
        assertFalse(forwarded.keys.any { it.equals("Connection", ignoreCase = true) })
        assertFalse(forwarded.keys.any { it.equals("Transfer-Encoding", ignoreCase = true) })
        assertFalse(forwarded.keys.any { it.equals("Keep-Alive", ignoreCase = true) })
        assertEquals("application/json", forwarded["Accept"])
        assertEquals("text/plain", forwarded["Content-Type"])
    }

    @Test
    fun `forwardingHeaders strips Proxy-Authorization but keeps Authorization`() {
        val request = ParsedHTTPRequest(
            method = "GET",
            target = "/wp/v2/posts",
            httpVersion = "HTTP/1.1",
            headers = mapOf(
                "Proxy-Authorization" to "Bearer proxy-token",
                "Authorization" to "Basic dXNlcjpwYXNz",
                "Accept" to "application/json"
            ),
            body = null,
            isComplete = true
        )

        val forwarded = request.forwardingHeaders()
        assertFalse(forwarded.keys.any { it.equals("Proxy-Authorization", ignoreCase = true) })
        assertEquals("Basic dXNlcjpwYXNz", forwarded["Authorization"])
        assertEquals("application/json", forwarded["Accept"])
    }

    @Test
    fun `forwardingHeaders strips headers listed in Connection header`() {
        val request = ParsedHTTPRequest(
            method = "GET",
            target = "/wp/v2/posts",
            httpVersion = "HTTP/1.1",
            headers = mapOf(
                "Connection" to "X-Custom, X-Other",
                "X-Custom" to "value1",
                "X-Other" to "value2",
                "Accept" to "application/json"
            ),
            body = null,
            isComplete = true
        )

        val forwarded = request.forwardingHeaders()
        assertFalse(forwarded.keys.any { it.equals("Connection", ignoreCase = true) })
        assertFalse(forwarded.keys.any { it.equals("X-Custom", ignoreCase = true) })
        assertFalse(forwarded.keys.any { it.equals("X-Other", ignoreCase = true) })
        assertEquals("application/json", forwarded["Accept"])
    }

    @Test
    fun `forwardingHeaders preserves non-hop-by-hop headers`() {
        val request = ParsedHTTPRequest(
            method = "POST",
            target = "/wp/v2/posts",
            httpVersion = "HTTP/1.1",
            headers = mapOf(
                "Content-Type" to "application/json",
                "Accept" to "application/json",
                "X-WP-Nonce" to "abc123"
            ),
            body = null,
            isComplete = true
        )

        val forwarded = request.forwardingHeaders()
        assertEquals(3, forwarded.size)
        assertEquals("application/json", forwarded["Content-Type"])
        assertEquals("application/json", forwarded["Accept"])
        assertEquals("abc123", forwarded["X-WP-Nonce"])
    }
}
