package org.wordpress.gutenberg.model.http

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

class EditorHTTPHeadersTest {

    // MARK: - Initialization Tests

    @Test
    fun `Empty initializer creates empty headers`() {
        val headers = EditorHTTPHeaders()

        assertNull(headers["Content-Type"])
        assertNull(headers["Accept"])
    }

    @Test
    fun `Map initializer creates headers with values`() {
        val headers = EditorHTTPHeaders(
            mapOf(
                "Content-Type" to "application/json",
                "Accept" to "text/html"
            )
        )

        assertEquals("application/json", headers["Content-Type"])
        assertEquals("text/html", headers["Accept"])
    }

    @Test
    fun `Map initializer handles empty map`() {
        val headers = EditorHTTPHeaders(emptyMap())

        assertNull(headers["Content-Type"])
    }

    @Test
    fun `Map initializer handles single entry`() {
        val headers = EditorHTTPHeaders(mapOf("X-Custom-Header" to "custom-value"))

        assertEquals("custom-value", headers["X-Custom-Header"])
    }

    // MARK: - Subscript Tests

    @Test
    fun `Subscript getter returns value for existing key`() {
        val headers = EditorHTTPHeaders(mapOf("Content-Type" to "application/json"))

        assertEquals("application/json", headers["Content-Type"])
    }

    @Test
    fun `Subscript getter returns nil for missing key`() {
        val headers = EditorHTTPHeaders(mapOf("Content-Type" to "application/json"))

        assertNull(headers["Accept"])
    }

    @Test
    fun `Subscript setter adds new value`() {
        val headers = EditorHTTPHeaders()

        headers["Content-Type"] = "application/json"

        assertEquals("application/json", headers["Content-Type"])
    }

    @Test
    fun `Subscript setter updates existing value`() {
        val headers = EditorHTTPHeaders(mapOf("Content-Type" to "text/plain"))

        headers["Content-Type"] = "application/json"

        assertEquals("application/json", headers["Content-Type"])
    }

    @Test
    fun `Subscript setter removes value when set to null`() {
        val headers = EditorHTTPHeaders(mapOf("Content-Type" to "application/json"))

        headers["Content-Type"] = null

        assertNull(headers["Content-Type"])
    }

    @Test
    fun `Subscript is case-insensitive`() {
        val headers = EditorHTTPHeaders(mapOf("Content-Type" to "application/json"))

        assertEquals("application/json", headers["Content-Type"])
        assertEquals("application/json", headers["content-type"])
        assertEquals("application/json", headers["CONTENT-TYPE"])
    }

    @Test
    fun `Subscript setter is case-insensitive`() {
        val headers = EditorHTTPHeaders(mapOf("Content-Type" to "text/plain"))

        // Setting with different case should update the same key
        headers["CONTENT-TYPE"] = "application/json"

        assertEquals("application/json", headers["Content-Type"])
        assertEquals("application/json", headers["content-type"])
    }

    @Test
    fun `Headers with same keys but different case are equal`() {
        val headers1 = EditorHTTPHeaders(mapOf("Content-Type" to "application/json"))
        val headers2 = EditorHTTPHeaders(mapOf("content-type" to "application/json"))

        assertEquals(headers1, headers2)
    }

    // MARK: - Equatable Tests

    @Test
    fun `Equal headers are equal`() {
        val headers1 = EditorHTTPHeaders(
            mapOf(
                "Content-Type" to "application/json",
                "Accept" to "text/html"
            )
        )
        val headers2 = EditorHTTPHeaders(
            mapOf(
                "Content-Type" to "application/json",
                "Accept" to "text/html"
            )
        )

        assertEquals(headers1, headers2)
    }

    @Test
    fun `Empty headers are equal`() {
        val headers1 = EditorHTTPHeaders()
        val headers2 = EditorHTTPHeaders()

        assertEquals(headers1, headers2)
    }

    @Test
    fun `Headers with different values are not equal`() {
        val headers1 = EditorHTTPHeaders(mapOf("Content-Type" to "application/json"))
        val headers2 = EditorHTTPHeaders(mapOf("Content-Type" to "text/plain"))

        assertNotEquals(headers1, headers2)
    }

    @Test
    fun `Headers with different keys are not equal`() {
        val headers1 = EditorHTTPHeaders(mapOf("Content-Type" to "application/json"))
        val headers2 = EditorHTTPHeaders(mapOf("Accept" to "application/json"))

        assertNotEquals(headers1, headers2)
    }

    @Test
    fun `Headers with different counts are not equal`() {
        val headers1 = EditorHTTPHeaders(mapOf("Content-Type" to "application/json"))
        val headers2 = EditorHTTPHeaders(
            mapOf(
                "Content-Type" to "application/json",
                "Accept" to "text/html"
            )
        )

        assertNotEquals(headers1, headers2)
    }

    // MARK: - Codable Tests

    @Test
    fun `Headers can be encoded and decoded`() {
        val original = EditorHTTPHeaders(
            mapOf(
                "Content-Type" to "application/json",
                "Accept" to "text/html",
                "X-Custom-Header" to "custom-value"
            )
        )

        val encoded = Json.encodeToString(original)
        val decoded = Json.decodeFromString<EditorHTTPHeaders>(encoded)

        assertEquals(original, decoded)
    }

    @Test
    fun `Empty headers can be encoded and decoded`() {
        val original = EditorHTTPHeaders()

        val encoded = Json.encodeToString(original)
        val decoded = Json.decodeFromString<EditorHTTPHeaders>(encoded)

        assertEquals(original, decoded)
    }

    @Test
    fun `Headers preserve values through encoding round-trip`() {
        val original = EditorHTTPHeaders(
            mapOf(
                "Content-Type" to "application/json; charset=utf-8",
                "Authorization" to "Bearer token123",
                "X-Request-ID" to "550e8400-e29b-41d4-a716-446655440000"
            )
        )

        val encoded = Json.encodeToString(original)
        val decoded = Json.decodeFromString<EditorHTTPHeaders>(encoded)

        assertEquals("application/json; charset=utf-8", decoded["Content-Type"])
        assertEquals("Bearer token123", decoded["Authorization"])
        assertEquals("550e8400-e29b-41d4-a716-446655440000", decoded["X-Request-ID"])
    }

    // MARK: - Edge Cases

    @Test
    fun `Headers handle empty string values`() {
        val headers = EditorHTTPHeaders(mapOf("Empty-Header" to ""))

        assertEquals("", headers["Empty-Header"])
    }

    @Test
    fun `Headers handle values with special characters`() {
        val headers = EditorHTTPHeaders(
            mapOf(
                "Content-Type" to "application/json; charset=utf-8",
                "Link" to """<https://example.com/page>; rel="next"""",
                "Set-Cookie" to "session=abc123; Path=/; HttpOnly"
            )
        )

        assertEquals("application/json; charset=utf-8", headers["Content-Type"])
        assertEquals("""<https://example.com/page>; rel="next"""", headers["Link"])
        assertEquals("session=abc123; Path=/; HttpOnly", headers["Set-Cookie"])
    }

    @Test
    fun `Headers handle unicode values`() {
        val headers = EditorHTTPHeaders(
            mapOf(
                "X-Greeting" to "こんにちは",
                "X-Emoji" to "🎉"
            )
        )

        assertEquals("こんにちは", headers["X-Greeting"])
        assertEquals("🎉", headers["X-Emoji"])
    }

    @Test
    fun `Headers handle very long values`() {
        val longValue = "a".repeat(10000)
        val headers = EditorHTTPHeaders(mapOf("X-Long-Header" to longValue))

        assertEquals(longValue, headers["X-Long-Header"])
    }

    @Test
    fun `Headers handle keys with hyphens`() {
        val headers = EditorHTTPHeaders(
            mapOf(
                "Content-Type" to "text/html",
                "X-Custom-Multi-Part-Header" to "value",
                "Accept-Language" to "en-US"
            )
        )

        assertEquals("text/html", headers["Content-Type"])
        assertEquals("value", headers["X-Custom-Multi-Part-Header"])
        assertEquals("en-US", headers["Accept-Language"])
    }

    // MARK: - Filtering Tests

    @Test
    fun `Filtering returns only matching headers`() {
        val headers = EditorHTTPHeaders(
            mapOf(
                "Content-Type" to "application/json",
                "Accept" to "text/html",
                "Link" to """<https://example.com>; rel="next""""
            )
        )

        val filtered = headers.filtering("Content-Type", "Link")

        assertEquals("application/json", filtered["Content-Type"])
        assertEquals("""<https://example.com>; rel="next"""", filtered["Link"])
        assertNull(filtered["Accept"])
    }

    @Test
    fun `Filtering with no matching keys returns empty headers`() {
        val headers = EditorHTTPHeaders(
            mapOf(
                "Content-Type" to "application/json",
                "Accept" to "text/html"
            )
        )

        val filtered = headers.filtering("X-Custom-Header")

        assertNull(filtered["Content-Type"])
        assertNull(filtered["Accept"])
        assertNull(filtered["X-Custom-Header"])
    }

    @Test
    fun `Filtering is case-insensitive`() {
        val headers = EditorHTTPHeaders(
            mapOf(
                "Content-Type" to "application/json",
                "Accept" to "text/html",
                "Link" to "<https://example.com>"
            )
        )

        // Filter with different case than stored keys
        val filtered = headers.filtering("content-type", "LINK")

        assertEquals("application/json", filtered["Content-Type"])
        assertEquals("<https://example.com>", filtered["Link"])
        assertNull(filtered["Accept"])
    }
}
