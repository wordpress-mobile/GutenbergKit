package org.wordpress.gutenberg

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Covers how `GutenbergView` interprets the result of `editor.getTitleAndContent`.
 *
 * The case that matters is a failed read. When the editor's `ErrorBoundary`
 * catches, React unmounts the editor and deletes every `window.editor.*` method,
 * so the evaluation returns the string `"null"`. Treating that as an empty title
 * let the host persist it over the user's own — locally, and then on the server.
 */
class GutenbergViewTitleAndContentTest {
    private val originalContent = "<!-- wp:paragraph --><p>Body</p><!-- /wp:paragraph -->"

    @Test
    fun `returns null when the bridge method is gone`() {
        assertNull(parseTitleAndContent("null", originalContent))
    }

    @Test
    fun `returns null for a malformed result`() {
        assertNull(parseTitleAndContent("undefined", originalContent))
        assertNull(parseTitleAndContent("", originalContent))
        assertNull(parseTitleAndContent(null, originalContent))
    }

    @Test
    fun `returns null when expected fields are absent`() {
        assertNull(parseTitleAndContent("""{"title":"Only a title"}""", originalContent))
    }

    @Test
    fun `reports the edited title and content when changed`() {
        val fields = parseTitleAndContent(
            """{"title":"New title","content":"New body","changed":true}""",
            originalContent
        )

        assertEquals("New title", fields?.first)
        assertEquals("New body", fields?.second)
    }

    @Test
    fun `falls back to the original content when unchanged`() {
        val fields = parseTitleAndContent(
            """{"title":"New title","content":"ignored","changed":false}""",
            originalContent
        )

        assertEquals("New title", fields?.first)
        assertEquals(originalContent, fields?.second)
    }

    /**
     * A title the user genuinely cleared must still come through. The fix has to
     * separate "the read failed" from "the title is empty", or it would trade one
     * bug for a different kind of data loss.
     */
    @Test
    fun `reports a deliberately emptied title`() {
        val fields = parseTitleAndContent(
            """{"title":"","content":"Body","changed":true}""",
            originalContent
        )

        assertEquals("", fields?.first)
        assertEquals("Body", fields?.second)
    }
}
