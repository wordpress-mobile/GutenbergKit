package org.wordpress.gutenberg.media

import kotlinx.serialization.encodeToString
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Pins the JSON shape passed to `window.blockInserter.insertMedia(...)`.
 * If a field is renamed or its null-handling changes, the JS side will
 * silently receive `undefined`; these tests catch that at build time.
 */
class MediaInfoTest {

    @Test
    fun `omits null optional fields`() {
        val info = MediaInfo(url = "https://example/img.jpg", type = "image/jpeg")
        assertEquals(
            """{"url":"https://example/img.jpg","type":"image/jpeg","metadata":{}}""",
            MediaInfoJson.encodeToString(info),
        )
    }

    @Test
    fun `includes all fields when populated`() {
        val info = MediaInfo(
            id = 42,
            url = "https://example/img.jpg",
            type = "image/jpeg",
            title = "title",
            caption = "caption",
            alt = "alt",
            metadata = mapOf("source" to "inserter"),
        )
        assertEquals(
            """{"id":42,"url":"https://example/img.jpg","type":"image/jpeg",""" +
                """"title":"title","caption":"caption","alt":"alt",""" +
                """"metadata":{"source":"inserter"}}""",
            MediaInfoJson.encodeToString(info),
        )
    }

    @Test
    fun `serialises a list as a JSON array`() {
        val media = listOf(
            MediaInfo(url = "https://example/a.jpg", type = "image/jpeg"),
            MediaInfo(url = "https://example/b.png", type = "image/png"),
        )
        assertEquals(
            """[{"url":"https://example/a.jpg","type":"image/jpeg","metadata":{}},""" +
                """{"url":"https://example/b.png","type":"image/png","metadata":{}}]""",
            MediaInfoJson.encodeToString(media),
        )
    }
}
