package org.wordpress.gutenberg.inserter

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import com.caverock.androidsvg.RenderOptions
import com.caverock.androidsvg.SVG
import kotlin.math.pow
import kotlin.math.roundToInt
import org.wordpress.gutenberg.model.BlockType

/**
 * Some @wordpress/icons (e.g. `core/icon`) declare `fill="none"` on the root
 * `<svg>` element and rely on the browser's block-editor CSS to override it
 * with `fill: currentColor`. AndroidSVG has no such cascade, so paths inherit
 * `fill="none"` and render invisibly. Injecting this rule at render time
 * restores the expected behaviour; the PorterDuff tint then recolours the
 * resulting pixels to match the theme.
 */
private const val DEFAULT_FILL_CSS = "svg { fill: currentColor; }"

/**
 * Used when a block declares a brand foreground colour (e.g. Pocket Casts
 * red): sets `color` so `currentColor` resolves to the brand colour and any
 * descendant paths without explicit fills pick it up.
 */
private fun foregroundCss(foreground: String) =
    "svg { color: $foreground; fill: currentColor; }"

/**
 * Captures fill declarations across SVG markup as raw value strings. Matches
 * three syntactic forms that appear in real WordPress and third-party block
 * icons:
 *  - `fill="..."` attributes (group 1)
 *  - `fill='...'` attributes (group 2)
 *  - `fill: ...` declarations inside `style="..."` and `<style>` blocks (group 3)
 *
 * `<style>` block selectors (e.g. `.cls-1 { fill: red }`) aren't tracked — we
 * extract the value regardless of whether the rule is actually applied via
 * `class="..."`. Worst case is a few defs-only fills inflate the multi-colour
 * count, biasing classification toward "render as-is" rather than tint;
 * preserving brand colour is the safer default for a branded icon, since the
 * inverse silently flattens it to a silhouette.
 */
private val FILL_DECLARATION_REGEX = Regex(
    """fill\s*(?:=\s*"([^"]*)"|=\s*'([^']*)'|:\s*([^;}"'<>]+))""",
    RegexOption.IGNORE_CASE,
)

/** Keywords that resolve to "no paint" or to the cascade — never a distinct colour. */
private val NON_COLOR_KEYWORDS = setOf(
    "none", "currentcolor", "transparent", "inherit", "initial", "unset",
)

/** Matches `rgb(r, g, b)` and `rgb(r%, g%, b%)`. SVG also permits `rgba(...)`,
 *  but @wordpress/icons doesn't emit it; if needed, extend here. */
private val RGB_FUNCTION_REGEX = Regex(
    """rgb\(\s*(\d+%?)\s*,\s*(\d+%?)\s*,\s*(\d+%?)\s*\)""",
    RegexOption.IGNORE_CASE,
)

/**
 * WCAG 2.x defines 3:1 as the minimum contrast for UI graphics and icons. Below
 * this, a brand colour reads as noise against the surface behind it (e.g. X's
 * `#000000` foreground on a dark bottom sheet), so we drop the brand colour
 * and let the theme tint take over.
 */
private const val MIN_CONTRAST_RATIO = 3.0

/**
 * Parses and caches block icon SVGs keyed by [BlockType.id], and caches the
 * rendered bitmap so RecyclerView rebinds don't re-render on every scroll.
 * Analogous to `BlockIconCache` in
 * `ios/Sources/GutenbergKit/Sources/Helpers/BlockIconCache.swift`, adapted for
 * the View-based dialog (iOS composes SVG nodes directly into SwiftUI; Android
 * rasterises to a Bitmap so the ImageView can apply a tint color filter).
 *
 * Not thread-safe; call from the UI thread.
 */
internal class SvgIconCache(
    private val renderSizePx: Int,
    /**
     * Opaque colour the icon actually sits on — typically the chip fill
     * composited over the dialog surface. Single-colour brand icons are
     * measured against this for the 3:1 WCAG check; it matters that the
     * reference matches what the user *sees* behind the icon, not the bare
     * surface (which makes marginal colours like WordPress blue appear to
     * pass while reading as dim in practice).
     */
    private val contrastSurface: Int,
) {

    /**
     * Result of rendering a block icon. [tintable] is `true` when the caller
     * should apply a theme tint — either because the source SVG is pure
     * monochrome, or because its single declared colour has insufficient
     * contrast against the surface and we've stripped brand colours to keep
     * the icon legible.
     */
    data class Icon(val bitmap: Bitmap, val tintable: Boolean)

    private val parsed = mutableMapOf<String, SVG?>()
    private val rendered = mutableMapOf<String, Icon?>()

    fun renderIcon(block: BlockType): Icon? {
        if (rendered.containsKey(block.id)) return rendered[block.id]
        val foreground = block.iconForeground?.takeIf { it.isNotBlank() }
        val tintable = shouldTint(block.icon, foreground, contrastSurface)
        val icon = svg(block)?.let { svg ->
            Icon(
                bitmap = render(svg, foreground.takeUnless { tintable }),
                tintable = tintable,
            )
        }
        rendered[block.id] = icon
        return icon
    }

    private fun svg(block: BlockType): SVG? {
        if (parsed.containsKey(block.id)) return parsed[block.id]
        val value = if (block.icon.isNullOrEmpty()) {
            null
        } else {
            runCatching { SVG.getFromString(block.icon) }.getOrNull()?.also(::normalize)
        }
        parsed[block.id] = value
        return value
    }

    /**
     * Some @wordpress/icons (e.g. core/site-tagline) declare intrinsic width/height
     * but omit `viewBox`. AndroidSVG then renders the paths at their native coordinate
     * size inside the target viewport instead of scaling to fill, so the icon appears
     * tiny. Synthesise a viewBox from the intrinsic dimensions and tell the document
     * to fill whatever viewport we render into.
     */
    private fun normalize(svg: SVG) {
        if (svg.documentViewBox == null) {
            val width = svg.documentWidth.takeIf { it > 0f } ?: return
            val height = svg.documentHeight.takeIf { it > 0f } ?: return
            svg.setDocumentViewBox(0f, 0f, width, height)
        }
        svg.setDocumentWidth("100%")
        svg.setDocumentHeight("100%")
    }

    private fun render(svg: SVG, foreground: String?): Bitmap {
        val bitmap = Bitmap.createBitmap(renderSizePx, renderSizePx, Bitmap.Config.ARGB_8888)
        val options = RenderOptions.create()
            .viewPort(0f, 0f, renderSizePx.toFloat(), renderSizePx.toFloat())
            .css(foreground?.let(::foregroundCss) ?: DEFAULT_FILL_CSS)
        svg.renderToCanvas(Canvas(bitmap), options)
        return bitmap
    }
}

/**
 * Decide whether the caller should apply the theme tint to the rendered
 * bitmap.
 *
 *  - No declared colours: pure monochrome — always tint so the icon picks
 *    up the theme's text colour.
 *  - Multiple declared colours (e.g. Pocket Casts: red outer + white
 *    inner): the icon relies on internal contrast, so render as-is. A
 *    PorterDuff tint would flatten it to a silhouette.
 *  - Single declared colour: keep it if the brand colour has at least
 *    [MIN_CONTRAST_RATIO] against [contrastSurface]; otherwise strip it
 *    and tint.
 */
internal fun shouldTint(svg: String?, foreground: String?, contrastSurface: Int): Boolean {
    val colors = collectSvgColors(svg, foreground)
    if (colors.isEmpty()) return true
    if (colors.size > 1) return false
    return contrastRatio(colors.single(), contrastSurface) < MIN_CONTRAST_RATIO
}

/**
 * Distinct paint colours declared in [svg] plus the optional [foreground].
 * `currentColor`, `none`, `transparent`, and the CSS cascade keywords don't
 * count — they either resolve to whatever the foreground/tint already
 * contributes, or they declare no concrete paint at all.
 */
internal fun collectSvgColors(svg: String?, foreground: String?): Set<Int> {
    val colors = mutableSetOf<Int>()
    foreground?.let { parseSvgColor(it)?.let(colors::add) }
    svg?.let { markup ->
        FILL_DECLARATION_REGEX.findAll(markup).forEach { match ->
            val raw = match.groupValues
                .drop(1)
                .firstOrNull { it.isNotEmpty() }
                ?: return@forEach
            parseSvgColor(raw)?.let(colors::add)
        }
    }
    return colors
}

/**
 * Parses a CSS/SVG colour value into an ARGB int, handling the variants that
 * appear in @wordpress/icons and common third-party block icons:
 *  - 3-, 4-, 6-, and 8-digit hex (web ordering for 4 and 8: alpha last)
 *  - Named colours (subset that [Color.parseColor] recognises)
 *  - `rgb(r, g, b)` and `rgb(r%, g%, b%)`
 *
 * Returns null for keywords like `none`, `currentColor`, `transparent`, the
 * CSS cascade keywords, or unrecognised input.
 */
internal fun parseSvgColor(raw: String): Int? {
    val value = raw.trim()
    if (value.isEmpty()) return null
    if (value.lowercase() in NON_COLOR_KEYWORDS) return null
    expandHexForAndroid(value)?.let {
        return runCatching { Color.parseColor(it) }.getOrNull()
    }
    parseRgbFunction(value)?.let { return it }
    return runCatching { Color.parseColor(value) }.getOrNull()
}

/**
 * Normalises a hex literal to the `#RRGGBB` / `#AARRGGBB` form
 * [Color.parseColor] accepts. SVG/CSS hex puts alpha last (`#RGBA`,
 * `#RRGGBBAA`); Android puts it first (`#AARRGGBB`), so we reorder for the
 * 4- and 8-digit forms. Returns null for non-hex input or unsupported digit
 * counts.
 */
private fun expandHexForAndroid(raw: String): String? {
    if (!raw.startsWith("#") || raw.length < 2) return null
    val digits = raw.substring(1)
    if (!digits.all { it.isHexDigit() }) return null
    return when (digits.length) {
        3 -> "#" + digits.asSequence().joinToString("") { "$it$it" }
        4 -> {
            val expanded = digits.asSequence().joinToString("") { "$it$it" }
            "#" + expanded.substring(6, 8) + expanded.substring(0, 6)
        }
        6 -> raw
        8 -> "#" + digits.substring(6, 8) + digits.substring(0, 6)
        else -> null
    }
}

private fun Char.isHexDigit(): Boolean =
    this in '0'..'9' || this in 'a'..'f' || this in 'A'..'F'

private fun parseRgbFunction(raw: String): Int? {
    val match = RGB_FUNCTION_REGEX.matchEntire(raw) ?: return null
    val r = parseRgbComponent(match.groupValues[1]) ?: return null
    val g = parseRgbComponent(match.groupValues[2]) ?: return null
    val b = parseRgbComponent(match.groupValues[3]) ?: return null
    return Color.argb(255, r, g, b)
}

private fun parseRgbComponent(raw: String): Int? = if (raw.endsWith('%')) {
    raw.dropLast(1).toIntOrNull()?.coerceIn(0, 100)?.let { (it / 100.0 * 255.0).roundToInt() }
} else {
    raw.toIntOrNull()?.coerceIn(0, 255)
}

internal fun isLight(color: Int): Boolean = relativeLuminance(color) > 0.5

internal fun contrastRatio(a: Int, b: Int): Double {
    val la = relativeLuminance(a)
    val lb = relativeLuminance(b)
    val lighter = maxOf(la, lb)
    val darker = minOf(la, lb)
    return (lighter + 0.05) / (darker + 0.05)
}

/** WCAG relative luminance — sRGB channels linearised and weighted for perceived brightness. */
private fun relativeLuminance(color: Int): Double {
    val r = linearize(Color.red(color) / 255.0)
    val g = linearize(Color.green(color) / 255.0)
    val b = linearize(Color.blue(color) / 255.0)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

private fun linearize(c: Double): Double =
    if (c <= 0.03928) c / 12.92 else ((c + 0.055) / 1.055).pow(2.4)
