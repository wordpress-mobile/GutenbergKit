package org.wordpress.gutenberg.inserter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.wordpress.gutenberg.model.BlockType

class BlockSearchTest {

    private val paragraph = block(
        id = "core/paragraph", name = "core/paragraph", title = "Paragraph",
        keywords = listOf("text"),
    )
    private val heading = block(
        id = "core/heading", name = "core/heading", title = "Heading",
    )
    private val image = block(
        id = "core/image", name = "core/image", title = "Image",
        keywords = listOf("photo", "picture"),
    )
    private val gallery = block(
        id = "core/gallery", name = "core/gallery", title = "Gallery",
        description = "Display multiple images in a gallery.",
    )

    private val all = listOf(paragraph, heading, image, gallery)

    @Test
    fun `empty query returns all blocks unchanged`() {
        assertEquals(all, searchBlocks("", all))
        assertEquals(all, searchBlocks("   ", all))
    }

    @Test
    fun `exact title match ranks first`() {
        val results = searchBlocks("image", all)
        assertEquals(image, results.first())
    }

    @Test
    fun `keyword match surfaces blocks with matching keyword`() {
        val results = searchBlocks("photo", all)
        assertTrue(image in results)
    }

    @Test
    fun `prefix match is preferred over generic contains`() {
        val results = searchBlocks("head", all)
        assertEquals(heading, results.first())
    }

    @Test
    fun `description match returns the block when nothing else matches`() {
        val results = searchBlocks("display", all)
        assertEquals(listOf(gallery), results)
    }

    @Test
    fun `fuzzy match tolerates a single typo in title`() {
        val results = searchBlocks("imge", all)
        assertEquals(image, results.first())
    }

    @Test
    fun `no match returns empty`() {
        assertTrue(searchBlocks("asdfghjkl", all).isEmpty())
    }

    @Test
    fun `search is case insensitive`() {
        assertEquals(image, searchBlocks("IMAGE", all).first())
    }

    private fun block(
        id: String,
        name: String,
        title: String? = null,
        description: String? = null,
        keywords: List<String> = emptyList(),
    ) = BlockType(
        id = id,
        name = name,
        title = title,
        description = description,
        keywords = keywords,
    )
}
