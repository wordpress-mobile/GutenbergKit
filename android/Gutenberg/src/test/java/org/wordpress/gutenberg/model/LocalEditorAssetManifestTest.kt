package org.wordpress.gutenberg.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalEditorAssetManifestTest {

    // MARK: - assetUrls - Script Parsing

    @Test
    fun `parses script src attributes`() {
        val json = """
            {
                "scripts": "<script src=\"https://example.com/app.js\"></script><script src=\"https://example.com/vendor.js\"></script>",
                "styles": "",
                "allowed_block_types": []
            }
        """.trimIndent()

        val manifest = createManifestFromJson(json)
        val links = manifest.assetUrls

        assertEquals(listOf("https://example.com/app.js", "https://example.com/vendor.js"), links)
    }

    @Test
    fun `parses stylesheet href attributes`() {
        val json = """
            {
                "scripts": "",
                "styles": "<link rel=\"stylesheet\" href=\"https://example.com/main.css\"><link rel=\"stylesheet\" href=\"https://example.com/theme.css\">",
                "allowed_block_types": []
            }
        """.trimIndent()

        val manifest = createManifestFromJson(json)
        val links = manifest.assetUrls

        assertEquals(listOf("https://example.com/main.css", "https://example.com/theme.css"), links)
    }

    @Test
    fun `parses both scripts and styles`() {
        val json = """
            {
                "scripts": "<script src=\"https://example.com/app.js\"></script>",
                "styles": "<link rel=\"stylesheet\" href=\"https://example.com/style.css\">",
                "allowed_block_types": []
            }
        """.trimIndent()

        val manifest = createManifestFromJson(json)
        val links = manifest.assetUrls

        assertEquals(listOf("https://example.com/app.js", "https://example.com/style.css"), links)
    }

    // MARK: - assetUrls - Protocol-Relative URLs

    @Test
    fun `resolves protocol-relative URLs with default scheme`() {
        val json = """
            {
                "scripts": "<script src=\"//cdn.example.com/script.js\"></script>",
                "styles": "<link rel=\"stylesheet\" href=\"//cdn.example.com/style.css\">",
                "allowed_block_types": []
            }
        """.trimIndent()

        val manifest = createManifestFromJson(json)
        val links = manifest.assetUrls

        assertEquals(listOf("https://cdn.example.com/script.js", "https://cdn.example.com/style.css"), links)
    }

    @Test
    fun `uses https as default scheme when none specified`() {
        val json = """
            {
                "scripts": "<script src=\"//cdn.example.com/script.js\"></script>",
                "styles": "",
                "allowed_block_types": []
            }
        """.trimIndent()

        val manifest = createManifestFromJson(json)
        val links = manifest.assetUrls

        assertEquals(listOf("https://cdn.example.com/script.js"), links)
    }

    // MARK: - assetUrls - Filtering

    @Test
    fun `ignores inline scripts without src`() {
        val json = """
            {
                "scripts": "<script>console.log('inline');</script><script src=\"https://example.com/app.js\"></script>",
                "styles": "",
                "allowed_block_types": []
            }
        """.trimIndent()

        val manifest = createManifestFromJson(json)
        val links = manifest.assetUrls

        assertEquals(listOf("https://example.com/app.js"), links)
    }

    @Test
    fun `ignores link tags without stylesheet rel`() {
        val json = """
            {
                "scripts": "",
                "styles": "<link rel=\"preload\" href=\"https://example.com/font.woff2\"><link rel=\"stylesheet\" href=\"https://example.com/style.css\">",
                "allowed_block_types": []
            }
        """.trimIndent()

        val manifest = createManifestFromJson(json)
        val links = manifest.assetUrls

        assertEquals(listOf("https://example.com/style.css"), links)
    }

    @Test
    fun `returns empty list for empty scripts and styles`() {
        val json = """
            {
                "scripts": "",
                "styles": "",
                "allowed_block_types": []
            }
        """.trimIndent()

        val manifest = createManifestFromJson(json)
        val links = manifest.assetUrls

        assertEquals(emptyList<String>(), links)
    }

    // MARK: - Empty Manifest

    @Test
    fun `empty manifest is empty`() {
        assertTrue(LocalEditorAssetManifest.empty.scripts.isEmpty())
        assertTrue(LocalEditorAssetManifest.empty.styles.isEmpty())
        assertTrue(LocalEditorAssetManifest.empty.allowedBlockTypes.isEmpty())
        assertTrue(LocalEditorAssetManifest.empty.rawStyles.isEmpty())
        assertTrue(LocalEditorAssetManifest.empty.rawScripts.isEmpty())
        assertTrue(LocalEditorAssetManifest.empty.assetUrls.isEmpty())
    }

    // MARK: - Test Helpers

    private fun createManifestFromJson(jsonString: String): LocalEditorAssetManifest {
        val remote = RemoteEditorAssetManifest.fromData(jsonString)
        return LocalEditorAssetManifest.fromRemoteManifest(remote)
    }
}
