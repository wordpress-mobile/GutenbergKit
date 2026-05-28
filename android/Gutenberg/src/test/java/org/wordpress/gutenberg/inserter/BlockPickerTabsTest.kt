package org.wordpress.gutenberg.inserter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.wordpress.gutenberg.model.BlockInserterPayload
import org.wordpress.gutenberg.model.BlockInserterSection
import org.wordpress.gutenberg.model.BlockType

class BlockPickerTabsTest {

    private val paragraph = block("core/paragraph", title = "Paragraph", category = "text")
    private val heading = block("core/heading", title = "Heading", category = "text")
    private val image = block("core/image", title = "Image", category = "media")
    private val jetpackAi = block(
        "jetpack/ai-assistant",
        title = "AI Assistant",
        category = "jetpack",
    )
    private val headingH2 = block(
        "core/heading/h2",
        name = "core/heading",
        title = "Heading (H2)",
    )

    private val textSection = BlockInserterSection(
        category = "text", name = "Text", blocks = listOf(paragraph, heading),
    )
    private val mediaSection = BlockInserterSection(
        category = "media", name = "Media", blocks = listOf(image),
    )
    private val jetpackSection = BlockInserterSection(
        category = "jetpack", name = "Jetpack", blocks = listOf(jetpackAi),
    )
    private val mostUsedSection = BlockInserterSection(
        category = "gbk-most-used", name = null, blocks = listOf(paragraph),
    )
    private val searchOnlySection = BlockInserterSection(
        category = "gbk-search-only", name = null, blocks = listOf(headingH2),
    )

    @Test
    fun `browsableSections strips every gbk- prefixed section`() {
        val payload = BlockInserterPayload(
            sections = listOf(mostUsedSection, textSection, searchOnlySection, jetpackSection),
        )

        val browsable = browsableSections(payload)

        assertEquals(listOf(textSection, jetpackSection), browsable)
    }

    @Test
    fun `buildTabs puts Recent first then preserves payload section order`() {
        val tabs = buildTabs(listOf(textSection, mediaSection, jetpackSection))

        assertEquals(
            listOf(
                BlockPickerTab.Recent,
                BlockPickerTab.Category(textSection),
                BlockPickerTab.Category(mediaSection),
                BlockPickerTab.Category(jetpackSection),
            ),
            tabs,
        )
    }

    @Test
    fun `buildTabs returns just Recent when there are no browsable sections`() {
        assertEquals(listOf(BlockPickerTab.Recent), buildTabs(emptyList()))
    }

    @Test
    fun `recentBlocks uses the most-used section when present`() {
        val payload = BlockInserterPayload(
            sections = listOf(mostUsedSection, textSection),
        )
        val allBlocks = allBrowsableBlocks(browsableSections(payload))

        assertEquals(listOf(paragraph), recentBlocks(payload, allBlocks))
    }

    @Test
    fun `recentBlocks falls back to all blocks when most-used is missing`() {
        val payload = BlockInserterPayload(sections = listOf(textSection, mediaSection))
        val allBlocks = allBrowsableBlocks(browsableSections(payload))

        assertEquals(listOf(paragraph, heading, image), recentBlocks(payload, allBlocks))
    }

    @Test
    fun `blocksForTab returns recent for the Recent tab`() {
        val recent = listOf(paragraph, image)

        assertSame(recent, blocksForTab(BlockPickerTab.Recent, recent))
    }

    @Test
    fun `blocksForTab returns the section's blocks for a Category tab`() {
        val tab = BlockPickerTab.Category(jetpackSection)

        // The Jetpack AI block is unreachable under the old hardcoded-allowlist
        // path; this regression test pins it to the Jetpack tab.
        assertEquals(listOf(jetpackAi), blocksForTab(tab, recentBlocks = emptyList()))
    }

    @Test
    fun `allBrowsableBlocks dedupes by id across sections`() {
        // The JS bridge shouldn't emit the same block twice, but a block that
        // ends up in two sections (e.g. a contextual section reuse) shouldn't
        // double-count in the all-blocks fallback used by Recent.
        val duplicateSection = textSection.copy(blocks = listOf(paragraph))

        val all = allBrowsableBlocks(listOf(textSection, duplicateSection))

        assertEquals(listOf(paragraph, heading), all)
    }

    @Test
    fun `browsableSections is empty when only synthetic sections are present`() {
        val payload = BlockInserterPayload(sections = listOf(mostUsedSection, searchOnlySection))

        assertTrue(browsableSections(payload).isEmpty())
    }

    private fun block(
        id: String,
        name: String = id,
        title: String? = null,
        category: String? = null,
    ) = BlockType(
        id = id,
        name = name,
        title = title,
        category = category,
    )
}
