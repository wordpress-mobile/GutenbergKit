package org.wordpress.gutenberg

import org.junit.Assert.assertEquals
import org.junit.Test

class StringExtensionsTest {

    // MARK: - Path-based API Roots

    @Test
    fun `appends path when API root has no trailing slash`() {
        assertEquals(
            "https://example.com/wp-json/wp/v2/media",
            "https://example.com/wp-json".appendingRestPath("/wp/v2/media")
        )
    }

    @Test
    fun `appends path when API root has trailing slash`() {
        assertEquals(
            "https://example.com/wp-json/wp/v2/media",
            "https://example.com/wp-json/".appendingRestPath("/wp/v2/media")
        )
    }

    @Test
    fun `appends path without a leading slash`() {
        assertEquals(
            "https://example.com/wp-json/wp/v2/media",
            "https://example.com/wp-json".appendingRestPath("wp/v2/media")
        )
    }

    @Test
    fun `preserves the query string of an appended path`() {
        assertEquals(
            "https://example.com/wp-json/wp/v2/themes?context=edit&status=active",
            "https://example.com/wp-json".appendingRestPath("/wp/v2/themes?context=edit&status=active")
        )
    }

    // MARK: - Query-based API Roots (plain permalinks)

    @Test
    fun `appends path to the route of a query-based API root`() {
        assertEquals(
            "https://example.com/?rest_route=/wp/v2/media",
            "https://example.com/?rest_route=/".appendingRestPath("/wp/v2/media")
        )
    }

    @Test
    fun `merges the path query string into a query-based API root`() {
        assertEquals(
            "https://example.com/?rest_route=/wp/v2/themes&context=edit&status=active",
            "https://example.com/?rest_route=/".appendingRestPath("/wp/v2/themes?context=edit&status=active")
        )
    }

    @Test
    fun `keeps exactly one leading slash when the API root omits its trailing slash`() {
        assertEquals(
            "https://example.com/?rest_route=/wp/v2/media",
            "https://example.com/?rest_route=".appendingRestPath("/wp/v2/media")
        )
    }

    @Test
    fun `appends path without a leading slash to a query-based API root`() {
        assertEquals(
            "https://example.com/?rest_route=/wp/v2/media",
            "https://example.com/?rest_route=/".appendingRestPath("wp/v2/media")
        )
    }
}
