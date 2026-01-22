package org.wordpress.gutenberg.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RemoteEditorAssetManifestTest {

    // MARK: - Decoding

    @Test
    fun `decodes from valid JSON`() {
        val json = """
            {
                "scripts": "<script src=\"https://example.com/script.js\"></script>",
                "styles": "<link rel=\"stylesheet\" href=\"https://example.com/style.css\">",
                "allowed_block_types": ["core/paragraph", "core/heading"]
            }
        """.trimIndent()

        val manifest = RemoteEditorAssetManifest.fromData(json)

        assertEquals("""<script src="https://example.com/script.js"></script>""", manifest.scripts)
        assertEquals("""<link rel="stylesheet" href="https://example.com/style.css">""", manifest.styles)
        assertEquals(listOf("core/paragraph", "core/heading"), manifest.allowedBlockTypes)
    }

    @Test
    fun `decodes empty allowed block types`() {
        val json = """
            {
                "scripts": "",
                "styles": "",
                "allowed_block_types": []
            }
        """.trimIndent()

        val manifest = RemoteEditorAssetManifest.fromData(json)

        assertTrue(manifest.allowedBlockTypes.isEmpty())
    }

    @Test
    fun `generates checksum from data`() {
        val json = """
            {
                "scripts": "<script src=\"https://example.com/script.js\"></script>",
                "styles": "",
                "allowed_block_types": []
            }
        """.trimIndent()

        val manifest = RemoteEditorAssetManifest.fromData(json)

        assertTrue(manifest.checksum.isNotEmpty())
    }

    @Test
    fun `same data produces same checksum`() {
        val json = """
            {
                "scripts": "<script src=\"https://example.com/script.js\"></script>",
                "styles": "",
                "allowed_block_types": []
            }
        """.trimIndent()

        val manifest1 = RemoteEditorAssetManifest.fromData(json)
        val manifest2 = RemoteEditorAssetManifest.fromData(json)

        assertEquals(manifest1.checksum, manifest2.checksum)
    }

    @Test
    fun `different data produces different checksum`() {
        val json1 = """
            {
                "scripts": "<script src=\"https://example.com/script1.js\"></script>",
                "styles": "",
                "allowed_block_types": []
            }
        """.trimIndent()

        val json2 = """
            {
                "scripts": "<script src=\"https://example.com/script2.js\"></script>",
                "styles": "",
                "allowed_block_types": []
            }
        """.trimIndent()

        val manifest1 = RemoteEditorAssetManifest.fromData(json1)
        val manifest2 = RemoteEditorAssetManifest.fromData(json2)

        assertNotEquals(manifest1.checksum, manifest2.checksum)
    }

    @Test
    fun `preserves raw scripts content`() {
        val scriptsContent = """<script src="https://example.com/app.js"></script>"""
        val json = """
            {
                "scripts": "<script src=\"https://example.com/app.js\"></script>",
                "styles": "",
                "allowed_block_types": []
            }
        """.trimIndent()

        val manifest = RemoteEditorAssetManifest.fromData(json)

        assertEquals(scriptsContent, manifest.scripts)
    }

    @Test
    fun `preserves raw styles content`() {
        val stylesContent = """<link rel="stylesheet" href="https://example.com/style.css">"""
        val json = """
            {
                "scripts": "",
                "styles": "<link rel=\"stylesheet\" href=\"https://example.com/style.css\">",
                "allowed_block_types": []
            }
        """.trimIndent()

        val manifest = RemoteEditorAssetManifest.fromData(json)

        assertEquals(stylesContent, manifest.styles)
    }

    // MARK: - Integration Tests

    @Test
    fun `successfully decodes test case 1`() {
        val json = TestResources.loadResource("editor-asset-manifest-test-case-1.json")
        val manifest = RemoteEditorAssetManifest.fromData(json)

        assertTrue(manifest.scripts.isNotEmpty())
        assertTrue(manifest.checksum.isNotEmpty())
    }
}
