package org.wordpress.gutenberg.inserter

import android.content.Context
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.Typeface
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
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
private const val ICON_SIZE_DP = 32

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
        val iconCache = SvgIconCache(iconSizePx)
        val iconTint = context.resolveTextColorPrimary()
        val recycler = RecyclerView(context).apply {
            layoutManager = LinearLayoutManager(context)
            adapter = InserterAdapter(items, iconCache, iconSizePx, iconTint) { block ->
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
            else -> BlockViewHolder(buildBlockView(context, iconSizePx), iconCache, iconTint)
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
    private val icon = container.getChildAt(0) as ImageView
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

private fun buildBlockView(context: Context, iconSizePx: Int): LinearLayout {
    val pad = context.dp(16)
    val iconMargin = context.dp(12)
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
        addView(
            ImageView(context).apply {
                layoutParams = LinearLayout.LayoutParams(iconSizePx, iconSizePx).apply {
                    rightMargin = iconMargin
                }
                scaleType = ImageView.ScaleType.FIT_CENTER
            },
        )
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

private fun Context.dp(value: Int): Int =
    (value * resources.displayMetrics.density).toInt()

private fun Context.resolveTextColorPrimary(): Int {
    val typed = TypedValue()
    theme.resolveAttribute(android.R.attr.textColorPrimary, typed, true)
    return resources.getColorStateList(typed.resourceId, theme).defaultColor
}
