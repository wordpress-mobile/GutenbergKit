package org.wordpress.gutenberg.inserter

import android.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Robolectric is required because [parseSvgColor] delegates to [Color.parseColor]
 * for named colours and the resulting ARGB ints are produced via [Color.argb].
 */
@RunWith(RobolectricTestRunner::class)
class SvgIconCacheTest {

    // -- parseSvgColor ----------------------------------------------------

    @Test
    fun `parses 6-digit hex`() {
        assertEquals(Color.parseColor("#FF0073AA"), parseSvgColor("#0073AA"))
    }

    @Test
    fun `parses lowercase hex`() {
        assertEquals(Color.parseColor("#FFFF0073"), parseSvgColor("#ff0073"))
    }

    @Test
    fun `parses 3-digit hex shorthand`() {
        // #f0a expands to #ff00aa
        assertEquals(Color.parseColor("#FFFF00AA"), parseSvgColor("#f0a"))
    }

    @Test
    fun `parses 8-digit hex with alpha last (web ordering)`() {
        // #0073AA80 (web RRGGBBAA) reorders to Android #800073AA (AARRGGBB)
        assertEquals(Color.parseColor("#800073AA"), parseSvgColor("#0073AA80"))
    }

    @Test
    fun `parses 4-digit hex shorthand with alpha last`() {
        // #f0a8 → expanded #ff00aa88 (RRGGBBAA) → Android #88ff00aa (AARRGGBB)
        assertEquals(Color.parseColor("#88FF00AA"), parseSvgColor("#f0a8"))
    }

    @Test
    fun `5-digit hex returns null`() {
        assertNull(parseSvgColor("#12345"))
    }

    @Test
    fun `7-digit hex returns null`() {
        assertNull(parseSvgColor("#1234567"))
    }

    @Test
    fun `non-hex digits in hex literal return null`() {
        assertNull(parseSvgColor("#xyz"))
        assertNull(parseSvgColor("#zzzzzz"))
    }

    @Test
    fun `parses named colour`() {
        assertEquals(Color.RED, parseSvgColor("red"))
        assertEquals(Color.BLUE, parseSvgColor("blue"))
    }

    @Test
    fun `parses rgb function`() {
        assertEquals(Color.rgb(0, 115, 170), parseSvgColor("rgb(0, 115, 170)"))
    }

    @Test
    fun `parses rgb function without spaces`() {
        assertEquals(Color.rgb(0, 115, 170), parseSvgColor("rgb(0,115,170)"))
    }

    @Test
    fun `parses rgb function with percentages`() {
        assertEquals(Color.rgb(0, 128, 255), parseSvgColor("rgb(0%, 50%, 100%)"))
    }

    @Test
    fun `trims surrounding whitespace`() {
        assertEquals(Color.parseColor("#FF0073AA"), parseSvgColor("  #0073AA  "))
    }

    @Test
    fun `none returns null`() {
        assertNull(parseSvgColor("none"))
        assertNull(parseSvgColor("NONE"))
    }

    @Test
    fun `currentColor returns null regardless of case`() {
        assertNull(parseSvgColor("currentColor"))
        assertNull(parseSvgColor("currentcolor"))
        assertNull(parseSvgColor("CURRENTCOLOR"))
    }

    @Test
    fun `transparent returns null`() {
        assertNull(parseSvgColor("transparent"))
    }

    @Test
    fun `cascade keywords return null`() {
        assertNull(parseSvgColor("inherit"))
        assertNull(parseSvgColor("initial"))
        assertNull(parseSvgColor("unset"))
    }

    @Test
    fun `empty input returns null`() {
        assertNull(parseSvgColor(""))
        assertNull(parseSvgColor("   "))
    }

    @Test
    fun `garbage returns null`() {
        assertNull(parseSvgColor("not a colour"))
    }

    // -- collectSvgColors -------------------------------------------------

    @Test
    fun `extracts hex fill from double-quoted attribute`() {
        val svg = """<svg><path fill="#0073AA"/></svg>"""
        assertEquals(setOf(Color.parseColor("#FF0073AA")), collectSvgColors(svg, null))
    }

    @Test
    fun `extracts hex fill from single-quoted attribute`() {
        val svg = """<svg><path fill='#0073AA'/></svg>"""
        assertEquals(setOf(Color.parseColor("#FF0073AA")), collectSvgColors(svg, null))
    }

    @Test
    fun `extracts fill from inline style attribute`() {
        val svg = """<svg><path style="fill:#0073AA;stroke:none"/></svg>"""
        assertEquals(setOf(Color.parseColor("#FF0073AA")), collectSvgColors(svg, null))
    }

    @Test
    fun `extracts fill from inline style with spaces`() {
        val svg = """<svg><path style="fill: #0073AA ; stroke: none"/></svg>"""
        assertEquals(setOf(Color.parseColor("#FF0073AA")), collectSvgColors(svg, null))
    }

    @Test
    fun `extracts fill from style block`() {
        val svg = """<svg><style>.cls-1 { fill: #0073AA; }</style><path class="cls-1"/></svg>"""
        assertEquals(setOf(Color.parseColor("#FF0073AA")), collectSvgColors(svg, null))
    }

    @Test
    fun `extracts 3-digit hex shorthand from attribute`() {
        val svg = """<svg><path fill="#f0a"/></svg>"""
        assertEquals(setOf(Color.parseColor("#FFFF00AA")), collectSvgColors(svg, null))
    }

    @Test
    fun `extracts named colour from attribute`() {
        val svg = """<svg><path fill="red"/></svg>"""
        assertEquals(setOf(Color.RED), collectSvgColors(svg, null))
    }

    @Test
    fun `extracts rgb function from style attribute`() {
        val svg = """<svg><path style="fill:rgb(0, 115, 170)"/></svg>"""
        assertEquals(setOf(Color.rgb(0, 115, 170)), collectSvgColors(svg, null))
    }

    @Test
    fun `does not count fill none`() {
        val svg = """<svg fill="none"><path fill="#0073AA"/></svg>"""
        assertEquals(setOf(Color.parseColor("#FF0073AA")), collectSvgColors(svg, null))
    }

    @Test
    fun `does not count fill currentColor`() {
        val svg = """<svg><path fill="currentColor"/></svg>"""
        assertTrue(collectSvgColors(svg, null).isEmpty())
    }

    @Test
    fun `multi-fill icon produces multi-colour set`() {
        // Mirrors Pocket Casts: red outer + white inner.
        val svg = """
            <svg>
              <path fill="#F43E37"/>
              <path fill="#FFFFFF"/>
            </svg>
        """.trimIndent()
        assertEquals(2, collectSvgColors(svg, null).size)
    }

    @Test
    fun `mixes attribute and inline-style fills`() {
        val svg = """
            <svg>
              <path fill="#F43E37"/>
              <path style="fill:#FFFFFF"/>
            </svg>
        """.trimIndent()
        assertEquals(2, collectSvgColors(svg, null).size)
    }

    @Test
    fun `dedupes equivalent fill values across forms`() {
        val svg = """
            <svg>
              <path fill="#FFFFFF"/>
              <path fill="#fff"/>
              <path style="fill:rgb(255, 255, 255)"/>
            </svg>
        """.trimIndent()
        assertEquals(setOf(Color.WHITE), collectSvgColors(svg, null))
    }

    @Test
    fun `foreground alone produces a single-colour set`() {
        assertEquals(setOf(Color.parseColor("#FFF43E37")), collectSvgColors(null, "#F43E37"))
    }

    @Test
    fun `foreground combines with distinct inline fill`() {
        val svg = """<svg><path fill="#FFFFFF"/></svg>"""
        val colors = collectSvgColors(svg, "#F43E37")
        assertEquals(2, colors.size)
        assertTrue(colors.contains(Color.WHITE))
        assertTrue(colors.contains(Color.parseColor("#FFF43E37")))
    }

    @Test
    fun `foreground deduplicates with matching inline fill`() {
        val svg = """<svg><path fill="#F43E37"/></svg>"""
        assertEquals(1, collectSvgColors(svg, "#F43E37").size)
    }

    @Test
    fun `null svg with null foreground produces empty set`() {
        assertTrue(collectSvgColors(null, null).isEmpty())
    }

    @Test
    fun `blank foreground is treated as no foreground`() {
        // collectSvgColors itself doesn't blank-check; renderIcon does. But an
        // empty string parses to null and is dropped, so the contract holds.
        assertTrue(collectSvgColors(null, "").isEmpty())
    }

    // -- shouldTint -------------------------------------------------------

    @Test
    fun `monochrome icon is tinted`() {
        val svg = """<svg><path d="M0 0L10 10"/></svg>"""
        assertTrue(shouldTint(svg, foreground = null, contrastSurface = Color.BLACK))
    }

    @Test
    fun `multi-colour icon renders as-is regardless of surface`() {
        val svg = """<svg><path fill="#F43E37"/><path fill="#FFFFFF"/></svg>"""
        assertFalse(shouldTint(svg, foreground = null, contrastSurface = Color.BLACK))
        assertFalse(shouldTint(svg, foreground = null, contrastSurface = Color.WHITE))
    }

    @Test
    fun `single high-contrast brand colour renders as-is`() {
        // Yellow on black: contrast ~19:1, well above the 3:1 threshold.
        val svg = """<svg><path fill="#FFFF00"/></svg>"""
        assertFalse(shouldTint(svg, foreground = null, contrastSurface = Color.BLACK))
    }

    @Test
    fun `X-style black icon falls back to tint on dark surface`() {
        // #000000 on #2F2F2F: contrast ~1.7, below 3:1.
        val svg = """<svg><path fill="#000000"/></svg>"""
        assertTrue(
            shouldTint(svg, foreground = null, contrastSurface = Color.parseColor("#FF2F2F2F"))
        )
    }

    @Test
    fun `WordPress blue passes contrast on light surface`() {
        // #0073AA on white: contrast ~5.2.
        assertFalse(
            shouldTint(svg = null, foreground = "#0073AA", contrastSurface = Color.WHITE)
        )
    }

    @Test
    fun `WordPress blue falls back to tint on dark surface`() {
        // #0073AA on #2F2F2F: contrast ~2.1, below 3:1.
        assertTrue(
            shouldTint(svg = null, foreground = "#0073AA", contrastSurface = Color.parseColor("#FF2F2F2F"))
        )
    }

    @Test
    fun `multi-fill SVG with brand foreground still renders as-is`() {
        // Pocket Casts case: foreground=red + inline white path = 2 colours.
        val svg = """<svg><path fill="#FFFFFF"/></svg>"""
        assertFalse(
            shouldTint(svg, foreground = "#F43E37", contrastSurface = Color.parseColor("#FF2F2F2F"))
        )
    }

    @Test
    fun `single fill via inline style is contrast-checked`() {
        // Same as the X case but expressed via style attribute — must classify
        // identically. This is the regression that motivated the regex widen.
        val svg = """<svg><path style="fill:#000000"/></svg>"""
        assertTrue(
            shouldTint(svg, foreground = null, contrastSurface = Color.parseColor("#FF2F2F2F"))
        )
    }

    @Test
    fun `single fill via shorthand hex is contrast-checked`() {
        // Same colour via 3-digit shorthand — must not silently mis-classify
        // as monochrome the way the original regex would have.
        val svg = """<svg><path fill="#000"/></svg>"""
        assertTrue(
            shouldTint(svg, foreground = null, contrastSurface = Color.parseColor("#FF2F2F2F"))
        )
    }
}
