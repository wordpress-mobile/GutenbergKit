package org.wordpress.gutenberg.http

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class TrimOWSTests {

    // MARK: - No-op cases

    @Test
    fun `returns same instance when no OWS present`() {
        val input = "hello"
        assertSame(input, input.trimOWS())
    }

    @Test
    fun `returns same instance for empty string`() {
        val input = ""
        assertSame(input, input.trimOWS())
    }

    // MARK: - Leading whitespace

    @Test
    fun `trims leading spaces`() {
        assertEquals("hello", "   hello".trimOWS())
    }

    @Test
    fun `trims leading tabs`() {
        assertEquals("hello", "\t\thello".trimOWS())
    }

    @Test
    fun `trims mixed leading SP and HTAB`() {
        assertEquals("hello", " \t \thello".trimOWS())
    }

    // MARK: - Trailing whitespace

    @Test
    fun `trims trailing spaces`() {
        assertEquals("hello", "hello   ".trimOWS())
    }

    @Test
    fun `trims trailing tabs`() {
        assertEquals("hello", "hello\t\t".trimOWS())
    }

    @Test
    fun `trims mixed trailing SP and HTAB`() {
        assertEquals("hello", "hello \t \t".trimOWS())
    }

    // MARK: - Both ends

    @Test
    fun `trims both leading and trailing OWS`() {
        assertEquals("hello", " \t hello \t ".trimOWS())
    }

    @Test
    fun `all OWS returns empty string`() {
        assertEquals("", " \t \t ".trimOWS())
    }

    // MARK: - Preserves interior whitespace

    @Test
    fun `preserves interior spaces`() {
        assertEquals("hello world", " hello world ".trimOWS())
    }

    @Test
    fun `preserves interior tabs`() {
        assertEquals("hello\tworld", "\thello\tworld\t".trimOWS())
    }

    // MARK: - Does NOT strip non-OWS characters

    @Test
    fun `preserves leading CR`() {
        assertEquals("\rhello", "\rhello".trimOWS())
    }

    @Test
    fun `preserves trailing CR`() {
        assertEquals("hello\r", "hello\r".trimOWS())
    }

    @Test
    fun `preserves leading LF`() {
        assertEquals("\nhello", "\nhello".trimOWS())
    }

    @Test
    fun `preserves trailing LF`() {
        assertEquals("hello\n", "hello\n".trimOWS())
    }

    @Test
    fun `preserves vertical tab`() {
        assertEquals("\u000Bhello", "\u000Bhello".trimOWS())
    }

    @Test
    fun `preserves form feed`() {
        assertEquals("\u000Chello", "\u000Chello".trimOWS())
    }

    @Test
    fun `preserves null byte`() {
        assertEquals("\u0000hello", "\u0000hello".trimOWS())
    }

    // MARK: - OWS around non-OWS control chars

    @Test
    fun `trims OWS but preserves CR between`() {
        assertEquals("\rhello\r", " \rhello\r ".trimOWS())
    }

    @Test
    fun `trims OWS but preserves LF between`() {
        assertEquals("\nhello\n", "\t\nhello\n\t".trimOWS())
    }
}
