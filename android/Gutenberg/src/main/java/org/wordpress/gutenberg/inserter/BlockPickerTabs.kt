package org.wordpress.gutenberg.inserter

import org.wordpress.gutenberg.model.BlockInserterPayload
import org.wordpress.gutenberg.model.BlockInserterSection
import org.wordpress.gutenberg.model.BlockType

/**
 * Prefix used by the JS bridge for sections that don't represent a real block
 * category (`gbk-most-used`, `gbk-contextual`, `gbk-search-only`, …). Browsable
 * tabs are derived from non-synthetic sections only.
 */
private const val SYNTHETIC_CATEGORY_PREFIX = "gbk-"

internal const val MOST_USED_CATEGORY = "gbk-most-used"

/**
 * One tab in the block picker. `Recent` is special-cased — it has its own
 * localized label and shows the payload's most-used blocks (falling back to
 * every browsable block when the payload doesn't carry a most-used section).
 * Every other tab is a [Category] driven by a non-synthetic payload section,
 * so the taxonomy is whatever the web editor's `getBlockCategories()` returns
 * (core categories first, plugin categories appended). This avoids hand-curating
 * a Kotlin-side allowlist that silently drops plugin and unfamiliar core blocks.
 */
internal sealed class BlockPickerTab {
    object Recent : BlockPickerTab()
    data class Category(val section: BlockInserterSection) : BlockPickerTab()
}

internal fun browsableSections(payload: BlockInserterPayload): List<BlockInserterSection> =
    payload.sections.filter { !it.category.startsWith(SYNTHETIC_CATEGORY_PREFIX) }

internal fun buildTabs(sections: List<BlockInserterSection>): List<BlockPickerTab> =
    buildList {
        add(BlockPickerTab.Recent)
        sections.forEach { add(BlockPickerTab.Category(it)) }
    }

internal fun allBrowsableBlocks(sections: List<BlockInserterSection>): List<BlockType> =
    dedupeById(sections.flatMap { it.blocks })

internal fun recentBlocks(
    payload: BlockInserterPayload,
    allBlocks: List<BlockType>,
): List<BlockType> {
    val mostUsed = payload.sections
        .firstOrNull { it.category == MOST_USED_CATEGORY }
        ?.blocks
        .orEmpty()
    return if (mostUsed.isNotEmpty()) dedupeById(mostUsed) else allBlocks
}

internal fun blocksForTab(
    tab: BlockPickerTab,
    recentBlocks: List<BlockType>,
): List<BlockType> = when (tab) {
    BlockPickerTab.Recent -> recentBlocks
    is BlockPickerTab.Category -> tab.section.blocks
}

internal fun dedupeById(blocks: List<BlockType>): List<BlockType> {
    val seen = HashSet<String>()
    return blocks.filter { seen.add(it.id) }
}
