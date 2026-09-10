package org.wordpress.gutenberg

import org.json.JSONException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Covers how `GutenbergView` interprets the result of `editor.getTitleAndContent`.
 * See [parseTitleAndContent] for why an unreadable result must fail.
 */
class GutenbergViewTitleAndContentTest {
    private val originalContent = "<!-- wp:paragraph --><p>Body</p><!-- /wp:paragraph -->"

    @Test
    fun `fails when the bridge method is gone`() {
        assertUnreadable("null")
    }

    @Test
    fun `fails for a malformed result`() {
        assertUnreadable("undefined")
        assertUnreadable("")
        assertUnreadable(null)
    }

    @Test
    fun `fails when expected fields are absent`() {
        assertUnreadable("""{"title":"Only a title"}""")
    }

    @Test
    fun `reports the edited title and content when changed`() {
        val fields = parseTitleAndContent(
            """{"title":"New title","content":"New body","changed":true}""",
            originalContent
        ).getOrThrow()

        assertEquals("New title", fields.first)
        assertEquals("New body", fields.second)
    }

    @Test
    fun `falls back to the original content when unchanged`() {
        val fields = parseTitleAndContent(
            """{"title":"New title","content":"ignored","changed":false}""",
            originalContent
        ).getOrThrow()

        assertEquals("New title", fields.first)
        assertEquals(originalContent, fields.second)
    }

    /**
     * A title the user cleared is a successful read and must still be reported.
     */
    @Test
    fun `reports a deliberately emptied title`() {
        val fields = parseTitleAndContent(
            """{"title":"","content":"Body","changed":true}""",
            originalContent
        ).getOrThrow()

        assertEquals("", fields.first)
        assertEquals("Body", fields.second)
    }

    private fun assertUnreadable(result: String?) {
        assertTrue(
            "expected <$result> to fail with a JSONException",
            parseTitleAndContent(result, originalContent).exceptionOrNull() is JSONException
        )
    }
}
