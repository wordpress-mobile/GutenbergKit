package org.wordpress.gutenberg

import org.junit.Assert.assertEquals
import org.junit.Test

class RestUrlBuilderTest {

    @Test
    fun `appends the path when no namespace is configured`() {
        assertEquals(
            "https://example.com/wp-json/wp/v2/media",
            RestUrlBuilder.namespaced("https://example.com/wp-json", null, "/wp/v2/media")
        )
    }

    @Test
    fun `inserts the namespace after the version segment`() {
        assertEquals(
            "https://example.com/wp-json/wp/v2/sites/123/media",
            RestUrlBuilder.namespaced("https://example.com/wp-json", "sites/123/", "/wp/v2/media")
        )
    }

    @Test
    fun `normalizes an unslashed root and namespace`() {
        assertEquals(
            "https://example.com/wp-json/wp/v2/sites/123/media",
            RestUrlBuilder.namespaced("https://example.com/wp-json", "sites/123", "/wp/v2/media")
        )
    }

    @Test
    fun `does not double the slash when the root already ends in one`() {
        assertEquals(
            "https://example.com/wp-json/wp/v2/sites/123/media",
            RestUrlBuilder.namespaced("https://example.com/wp-json/", "sites/123", "/wp/v2/media")
        )
    }

    @Test
    fun `inserts the namespace after a non-wp-v2 version segment`() {
        assertEquals(
            "https://example.com/wp-json/wp-block-editor/v1/sites/123/settings",
            RestUrlBuilder.namespaced("https://example.com/wp-json", "sites/123", "/wp-block-editor/v1/settings")
        )
    }

    @Test
    fun `namespaces a two-segment path`() {
        assertEquals(
            "https://example.com/wp-json/wp/v2/sites/123/",
            RestUrlBuilder.namespaced("https://example.com/wp-json", "sites/123", "/wp/v2")
        )
    }

    // MARK: - Query-based API Roots (plain permalinks)

    @Test
    fun `appends the path to the route of a query-based root`() {
        assertEquals(
            "https://example.com/?rest_route=/wp/v2/types",
            RestUrlBuilder.namespaced("https://example.com/?rest_route=/", null, "/wp/v2/types")
        )
    }

    @Test
    fun `merges the path query string into a query-based root`() {
        assertEquals(
            "https://example.com/?rest_route=/wp/v2/sites/123/themes&context=edit&status=active",
            RestUrlBuilder.namespaced(
                "https://example.com/?rest_route=/",
                "sites/123",
                "/wp/v2/themes?context=edit&status=active"
            )
        )
    }
}
