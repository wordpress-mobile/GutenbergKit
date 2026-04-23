package org.wordpress.gutenberg.inserter

import android.graphics.Bitmap
import android.graphics.Canvas
import com.caverock.androidsvg.RenderOptions
import com.caverock.androidsvg.SVG
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
 * Detects icons that declare their own colours on inner elements (e.g.
 * `embedPocketCastsIcon` uses a black outer circle with a `fill="#fff"` inner
 * shape). These rely on colour contrast to be recognisable, so a monochrome
 * PorterDuff tint would flatten them into a solid silhouette.
 *
 * @wordpress/icons never puts a hex `fill` on the root `<svg>`, so any
 * `fill="#..."` in the string implies a descendant element chose its own
 * colour and we should render the icon as-is.
 */
private val EXPLICIT_HEX_FILL = Regex("""fill="#""")

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
internal class SvgIconCache(private val renderSizePx: Int) {

    /**
     * Result of rendering a block icon. [tintable] is `true` when the source
     * SVG has no intrinsic colours and the caller should apply a theme tint
     * for legibility; `false` for branded icons that must render as-is to keep
     * their internal contrast.
     */
    data class Icon(val bitmap: Bitmap, val tintable: Boolean)

    private val parsed = mutableMapOf<String, SVG?>()
    private val rendered = mutableMapOf<String, Icon?>()

    fun renderIcon(block: BlockType): Icon? {
        if (rendered.containsKey(block.id)) return rendered[block.id]
        val icon = svg(block)?.let { svg ->
            Icon(
                bitmap = render(svg),
                tintable = !hasExplicitColor(block.icon),
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

    private fun render(svg: SVG): Bitmap {
        val bitmap = Bitmap.createBitmap(renderSizePx, renderSizePx, Bitmap.Config.ARGB_8888)
        val options = RenderOptions.create()
            .viewPort(0f, 0f, renderSizePx.toFloat(), renderSizePx.toFloat())
            .css(DEFAULT_FILL_CSS)
        svg.renderToCanvas(Canvas(bitmap), options)
        return bitmap
    }

    private fun hasExplicitColor(icon: String?): Boolean =
        icon != null && EXPLICIT_HEX_FILL.containsMatchIn(icon)
}
