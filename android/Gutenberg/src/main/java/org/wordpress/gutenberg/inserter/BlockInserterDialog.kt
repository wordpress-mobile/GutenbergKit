package org.wordpress.gutenberg.inserter

import android.content.Context
import android.graphics.Color
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.res.ResourcesCompat
import androidx.core.view.setPadding
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.bottomsheet.BottomSheetDialog
import org.wordpress.gutenberg.R
import org.wordpress.gutenberg.model.BlockInserterPayload
import org.wordpress.gutenberg.model.BlockInserterSection
import org.wordpress.gutenberg.model.BlockType

private const val SEARCH_ONLY_CATEGORY = "gbk-search-only"
private const val MOST_USED_CATEGORY = "gbk-most-used"
private const val CONTEXTUAL_CATEGORY = "gbk-contextual"
private const val ICON_CHIP_SIZE_DP = 44
private const val ICON_CHIP_CORNER_DP = 12
private const val ICON_SIZE_DP = 24

/** ~12% alpha — subtle tinted fill that reads as a chip against either background. */
private const val ICON_CHIP_FILL_ALPHA = 0x1F

/**
 * Stub bottom-sheet inserter shown when `enableNativeBlockInserter` is on.
 * Flat list of section headers + tappable block rows. Will be replaced by a
 * richer implementation in a follow-up PR.
 */
internal class BlockInserterDialog(
    context: Context,
    payload: BlockInserterPayload,
    private val onBlockSelected: (BlockType) -> Unit,
) : BottomSheetDialog(context) {

    init {
        val items = buildItems(payload)
        val iconSizePx = context.dp(ICON_SIZE_DP)
        val chipSizePx = context.dp(ICON_CHIP_SIZE_DP)
        val iconTint = context.resolveTextColorPrimary()
        val surface = context.resolveDialogSurface(iconTint)
        val iconCache = SvgIconCache(iconSizePx, effectiveChipColor(iconTint, surface))
        val recycler = RecyclerView(context).apply {
            layoutManager = LinearLayoutManager(context)
            adapter = InserterAdapter(
                items,
                iconCache,
                iconSizePx,
                chipSizePx,
                iconTint,
            ) { block ->
                onBlockSelected(block)
                dismiss()
            }
        }
        setContentView(recycler)
    }

    private fun buildItems(payload: BlockInserterPayload): List<Row> {
        val rows = mutableListOf<Row>()
        payload.sections
            .filter { it.blocks.isNotEmpty() && it.category != SEARCH_ONLY_CATEGORY }
            .forEach { section ->
                rows += Row.Header(section)
                section.blocks.forEach { rows += Row.Block(it) }
            }
        return rows
    }
}

private sealed class Row {
    data class Header(val section: BlockInserterSection) : Row()
    data class Block(val block: BlockType) : Row()
}

private const val TYPE_HEADER = 0
private const val TYPE_BLOCK = 1

private class InserterAdapter(
    private val rows: List<Row>,
    private val iconCache: SvgIconCache,
    private val iconSizePx: Int,
    private val chipSizePx: Int,
    private val iconTint: Int,
    private val onBlockClicked: (BlockType) -> Unit,
) : RecyclerView.Adapter<RecyclerView.ViewHolder>() {

    override fun getItemCount(): Int = rows.size

    override fun getItemViewType(position: Int): Int = when (rows[position]) {
        is Row.Header -> TYPE_HEADER
        is Row.Block -> TYPE_BLOCK
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        val context = parent.context
        return when (viewType) {
            TYPE_HEADER -> HeaderViewHolder(buildHeaderView(context))
            else -> BlockViewHolder(
                buildBlockView(context, iconSizePx, chipSizePx, iconTint),
                iconCache,
                iconTint,
            )
        }
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        when (val row = rows[position]) {
            is Row.Header -> (holder as HeaderViewHolder).bind(row.section)
            is Row.Block -> (holder as BlockViewHolder).bind(row.block, onBlockClicked)
        }
    }
}

private class HeaderViewHolder(view: View) : RecyclerView.ViewHolder(view) {
    private val label = view as TextView
    fun bind(section: BlockInserterSection) {
        label.text = section.name ?: defaultDisplayName(section.category)
    }

    private fun defaultDisplayName(category: String): String = when (category) {
        MOST_USED_CATEGORY -> label.context.getString(R.string.gbk_block_inserter_section_most_used)
        CONTEXTUAL_CATEGORY -> label.context.getString(R.string.gbk_block_inserter_section_suggested)
        else -> category.replaceFirstChar { it.uppercase() }
    }
}

private class BlockViewHolder(
    view: View,
    private val iconCache: SvgIconCache,
    private val iconTint: Int,
) : RecyclerView.ViewHolder(view) {
    private val container = view as LinearLayout
    private val icon = (container.getChildAt(0) as FrameLayout).getChildAt(0) as ImageView
    private val textContainer = container.getChildAt(1) as LinearLayout
    private val title = textContainer.getChildAt(0) as TextView
    private val description = textContainer.getChildAt(1) as TextView

    fun bind(block: BlockType, onClicked: (BlockType) -> Unit) {
        title.text = block.title ?: block.name
        val desc = block.description?.takeIf { it.isNotBlank() }
        description.text = desc
        description.visibility = if (desc == null) View.GONE else View.VISIBLE
        container.isEnabled = !block.isDisabled
        container.alpha = if (block.isDisabled) 0.5f else 1f
        container.setOnClickListener { if (!block.isDisabled) onClicked(block) }

        val rendered = iconCache.renderIcon(block)
        icon.setImageBitmap(rendered?.bitmap)
        icon.colorFilter = if (rendered?.tintable == true) {
            PorterDuffColorFilter(iconTint, PorterDuff.Mode.SRC_IN)
        } else {
            null
        }
    }
}

private fun buildHeaderView(context: Context): TextView {
    val horizontal = context.dp(16)
    val vertical = context.dp(8)
    return TextView(context).apply {
        layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        )
        setPadding(horizontal, vertical, horizontal, vertical)
        setTypeface(Typeface.DEFAULT, Typeface.BOLD)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
    }
}

private fun buildBlockView(
    context: Context,
    iconSizePx: Int,
    chipSizePx: Int,
    iconTint: Int,
): LinearLayout {
    val pad = context.dp(16)
    val iconMargin = context.dp(12)
    val cornerPx = context.dp(ICON_CHIP_CORNER_DP).toFloat()
    return LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        )
        setPadding(pad)
        gravity = Gravity.CENTER_VERTICAL
        background = ResourcesCompat.getDrawable(
            context.resources,
            android.R.drawable.list_selector_background,
            context.theme,
        )
        isClickable = true
        isFocusable = true
        addView(buildIconChip(context, iconSizePx, chipSizePx, iconTint, iconMargin, cornerPx))
        addView(
            LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                layoutParams = LinearLayout.LayoutParams(
                    0,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    1f,
                )
                addView(
                    TextView(context).apply {
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                    },
                )
                addView(
                    TextView(context).apply {
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                        alpha = 0.7f
                    },
                )
            },
        )
    }
}

private fun buildIconChip(
    context: Context,
    iconSizePx: Int,
    chipSizePx: Int,
    iconTint: Int,
    rightMarginPx: Int,
    cornerPx: Float,
): FrameLayout = FrameLayout(context).apply {
    layoutParams = LinearLayout.LayoutParams(chipSizePx, chipSizePx).apply {
        rightMargin = rightMarginPx
    }
    background = GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        cornerRadius = cornerPx
        setColor(chipFill(iconTint))
    }
    addView(
        ImageView(context).apply {
            layoutParams = FrameLayout.LayoutParams(iconSizePx, iconSizePx).apply {
                gravity = Gravity.CENTER
            }
            scaleType = ImageView.ScaleType.FIT_CENTER
        },
    )
}

/**
 * Derive a subtle chip fill from the theme's primary text colour so the chip
 * sits at a roughly uniform contrast against either a light or dark surface.
 * Brand-coloured icons (X's black, Dailymotion's #333436) would otherwise
 * disappear against the dialog's dark background.
 */
private fun chipFill(iconTint: Int): Int =
    (iconTint and 0x00FFFFFF) or (ICON_CHIP_FILL_ALPHA shl 24)

/**
 * Opaque approximation of what the icon renders against: the chip fill
 * composited over the dialog surface. Used as the contrast reference in
 * [SvgIconCache] so single-colour brand icons are measured against what the
 * user actually sees, not the bare surface behind the chip.
 */
private fun effectiveChipColor(iconTint: Int, surface: Int): Int {
    val alpha = ICON_CHIP_FILL_ALPHA / 255.0
    val r = (Color.red(iconTint) * alpha + Color.red(surface) * (1 - alpha)).toInt()
    val g = (Color.green(iconTint) * alpha + Color.green(surface) * (1 - alpha)).toInt()
    val b = (Color.blue(iconTint) * alpha + Color.blue(surface) * (1 - alpha)).toInt()
    return Color.rgb(r, g, b)
}

/**
 * Best-effort lookup of the bottom sheet's surface colour. Material themes
 * expose this as `?attr/colorSurface`; older themes as `?android:attr/
 * colorBackground`. Falls back to the inverse of [iconTint] for pathological
 * themes that define neither — still preferable to hardcoding black/white
 * because the real surface is usually off-black/off-white.
 */
private fun Context.resolveDialogSurface(iconTint: Int): Int {
    val typed = TypedValue()
    val attrs = intArrayOf(
        com.google.android.material.R.attr.colorSurface,
        android.R.attr.colorBackground,
    )
    for (attr in attrs) {
        if (theme.resolveAttribute(attr, typed, true)) {
            return if (typed.resourceId != 0) {
                resources.getColor(typed.resourceId, theme)
            } else {
                typed.data
            }
        }
    }
    return if (isLight(iconTint)) Color.BLACK else Color.WHITE
}

private fun Context.dp(value: Int): Int =
    (value * resources.displayMetrics.density).toInt()

private fun Context.resolveTextColorPrimary(): Int {
    val typed = TypedValue()
    theme.resolveAttribute(android.R.attr.textColorPrimary, typed, true)
    return resources.getColorStateList(typed.resourceId, theme).defaultColor
}
