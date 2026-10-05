package org.wordpress.gutenberg

import org.junit.Assert.assertEquals
import org.junit.Test

class HttpRequestTest {

    private fun request(target: String) = HttpRequest(
        method = "POST",
        target = target,
        headers = emptyMap()
    )

    @Test
    fun `path is the whole target when there is no query`() {
        assertEquals("/upload", request("/upload").path)
        assertEquals("", request("/upload").query)
    }

    @Test
    fun `path and query split on the first question mark`() {
        val parsed = request("/upload?_embed=wp:featuredmedia")
        assertEquals("/upload", parsed.path)
        assertEquals("?_embed=wp:featuredmedia", parsed.query)
    }

    @Test
    fun `a trailing question mark yields an empty query`() {
        val parsed = request("/upload?")
        assertEquals("/upload", parsed.path)
        assertEquals("", parsed.query)
    }

    @Test
    fun `later question marks belong to the query`() {
        val parsed = request("/search?q=a?b")
        assertEquals("/search", parsed.path)
        assertEquals("?q=a?b", parsed.query)
    }

    @Test
    fun `multiple query parameters are preserved`() {
        val parsed = request("/wp/v2/posts?per_page=10&page=2")
        assertEquals("/wp/v2/posts", parsed.path)
        assertEquals("?per_page=10&page=2", parsed.query)
    }
}
