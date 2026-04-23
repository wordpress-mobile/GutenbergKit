package org.wordpress.gutenberg.model

import kotlinx.serialization.SerializationException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class BlockInserterTest {

    @Test
    fun `parses a full payload from the web bridge`() {
        val payload = BlockInserterPayload.fromJson(FULL_PAYLOAD_JSON)

        val section = payload.sections.single()
        assertEquals("gbk-most-used", section.category)
        assertNull(section.name)

        val block = section.blocks.single()
        assertEquals("core/paragraph", block.id)
        assertEquals("Paragraph", block.title)
        assertEquals(listOf("text"), block.keywords)
        assertEquals("<svg></svg>", block.icon)
        assertEquals(0.5, block.frecency, 0.0)

        val pattern = payload.patterns.single()
        assertEquals("core/query-standard-posts", pattern.name)
        assertEquals(listOf("core/query"), pattern.blockTypes)
        assertNull(pattern.description)
        assertEquals(1200, pattern.viewportWidth)

        assertEquals("Galerie", payload.patternCategories.single().label)

        val rect = payload.sourceRect
        assertNotNull(rect)
        assertEquals(10.0, rect!!.x, 0.0)
        assertEquals(40.0, rect.height, 0.0)
    }

    @Test
    fun `tolerates a minimal payload with only sections`() {
        val json = """{"sections": [{"category": "text", "blocks": []}]}"""

        val payload = BlockInserterPayload.fromJson(json)

        assertEquals(1, payload.sections.size)
        assertEquals("text", payload.sections.first().category)
        assertTrue(payload.patterns.isEmpty())
        assertTrue(payload.patternCategories.isEmpty())
        assertNull(payload.sourceRect)
    }

    @Test
    fun `uses fallback category when section is missing one`() {
        val json = """{"sections": [{"name": null, "blocks": []}]}"""

        val payload = BlockInserterPayload.fromJson(json)

        assertEquals("gbk-missing-category", payload.sections.first().category)
    }

    @Test
    fun `treats null strings as null, not empty`() {
        val json = """
            {"sections": [{"category": "text", "blocks": [
              {"id": "core/paragraph", "name": "core/paragraph",
               "title": "Paragraph", "description": null, "icon": null,
               "category": null, "keywords": [], "frecency": 0,
               "isDisabled": false, "isSearchOnly": false, "parents": []}
            ]}]}
        """.trimIndent()

        val block = BlockInserterPayload.fromJson(json).sections.first().blocks.first()

        assertNull(block.description)
        assertNull(block.icon)
        assertNull(block.category)
    }

    @Test
    fun `throws SerializationException on malformed input`() {
        assertThrows(SerializationException::class.java) {
            BlockInserterPayload.fromJson("not json")
        }
    }
}

private val FULL_PAYLOAD_JSON = """
    {
      "sections": [
        {
          "category": "gbk-most-used",
          "name": null,
          "blocks": [
            {
              "id": "core/paragraph",
              "name": "core/paragraph",
              "title": "Paragraph",
              "description": "Start with the basic building block of all narrative.",
              "category": "text",
              "keywords": ["text"],
              "icon": "<svg></svg>",
              "frecency": 0.5,
              "isDisabled": false,
              "isSearchOnly": false,
              "parents": []
            }
          ]
        }
      ],
      "patterns": [
        {
          "name": "core/query-standard-posts",
          "title": "Standard Posts",
          "content": "<!-- wp:query --><!-- /wp:query -->",
          "blockTypes": ["core/query"],
          "categories": ["query"],
          "description": null,
          "keywords": [],
          "source": "pattern-directory",
          "viewportWidth": 1200
        }
      ],
      "patternCategories": [
        {"name": "gallery", "label": "Galerie"}
      ],
      "sourceRect": {"x": 10, "y": 20, "width": 30, "height": 40}
    }
""".trimIndent()
