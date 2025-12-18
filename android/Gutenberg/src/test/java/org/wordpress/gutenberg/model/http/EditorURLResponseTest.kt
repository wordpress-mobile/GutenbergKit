package org.wordpress.gutenberg.model.http

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class EditorURLResponseTest {

    // MARK: - Initialization Tests

    @Test
    fun `Initializes with data and headers`() {
        val data = "test content"
        val headers = EditorHTTPHeaders(mapOf("Content-Type" to "text/plain"))

        val response = EditorURLResponse(data = data, responseHeaders = headers)

        assertEquals(data, response.data)
        assertEquals(headers, response.responseHeaders)
    }

    // MARK: - Equatable Tests

    @Test
    fun `Equal responses are equal`() {
        val data = "test"
        val headers = EditorHTTPHeaders(mapOf("Content-Type" to "text/plain"))

        val response1 = EditorURLResponse(data = data, responseHeaders = headers)
        val response2 = EditorURLResponse(data = data, responseHeaders = headers)

        assertEquals(response1, response2)
    }

    @Test
    fun `Responses with different data are not equal`() {
        val headers = EditorHTTPHeaders(mapOf("Content-Type" to "text/plain"))

        val response1 = EditorURLResponse(data = "test1", responseHeaders = headers)
        val response2 = EditorURLResponse(data = "test2", responseHeaders = headers)

        assertNotEquals(response1, response2)
    }

    @Test
    fun `Responses with different headers are not equal`() {
        val data = "test"

        val response1 = EditorURLResponse(
            data = data,
            responseHeaders = EditorHTTPHeaders(mapOf("Content-Type" to "text/plain"))
        )
        val response2 = EditorURLResponse(
            data = data,
            responseHeaders = EditorHTTPHeaders(mapOf("Content-Type" to "application/json"))
        )

        assertNotEquals(response1, response2)
    }

    // MARK: - Codable Tests

    @Test
    fun `Response can be encoded and decoded`() {
        val data = "test content"
        val headers = EditorHTTPHeaders(
            mapOf(
                "Content-Type" to "application/json",
                "X-Request-Id" to "123"
            )
        )
        val original = EditorURLResponse(data = data, responseHeaders = headers)

        val encoded = Json.encodeToString(original)
        val decoded = Json.decodeFromString<EditorURLResponse>(encoded)

        assertEquals(original, decoded)
    }
}
