package org.wordpress.gutenberg

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import kotlin.test.assertFailsWith

/** Reads requests the way org.json's getters did on Android, which hosts depend on. */
class RecordedNetworkRequestTest {
    private fun request(fields: String) = RecordedNetworkRequest.fromJson(
        Json.parseToJsonElement(
            """{"url":"https://example.com","method":"POST","requestHeaders":{"Accept":"*/*"},""" +
                """"status":200,"responseHeaders":{},"duration":5$fields}"""
        ).jsonObject
    )

    @Test
    fun `reads the request's fields`() {
        val request = request(""","requestBody":"a=1","statusText":"OK","responseBody":"{}"""")

        assertEquals("https://example.com", request.url)
        assertEquals("POST", request.method)
        assertEquals(mapOf("Accept" to "*/*"), request.requestHeaders)
        assertEquals("a=1", request.requestBody)
        assertEquals(200, request.status)
        assertEquals("OK", request.statusText)
        assertEquals("{}", request.responseBody)
        assertEquals(5, request.duration)
    }

    @Test
    fun `leaves out a missing or empty body`() {
        assertNull(request("").requestBody)
        assertNull(request(""","requestBody":""""").requestBody)
    }

    // org.json on Android reads a null as "null"; hosts that build a request from
    // it would otherwise get no body for a POST.
    @Test
    fun `reads a null body as Android's org json did`() {
        assertEquals("null", request(""","requestBody":null""").requestBody)
    }

    @Test
    fun `drops the fraction of a fractional number`() {
        val request = RecordedNetworkRequest.fromJson(
            Json.parseToJsonElement(
                """{"url":"u","method":"GET","requestHeaders":{},"status":200,"responseHeaders":{},"duration":12.7}"""
            ).jsonObject
        )

        assertEquals(12, request.duration)
    }

    @Test
    fun `fails without a required field`() {
        assertFailsWith<IllegalArgumentException> {
            RecordedNetworkRequest.fromJson(Json.parseToJsonElement("""{"url":"https://example.com"}""").jsonObject)
        }
    }
}
