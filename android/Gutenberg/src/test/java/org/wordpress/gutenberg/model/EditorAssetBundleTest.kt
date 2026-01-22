package org.wordpress.gutenberg.model

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.Date
import java.util.UUID

class EditorAssetBundleTest {

    private val json = Json { ignoreUnknownKeys = true }

    // MARK: - Initialization Tests

    @Test
    fun `Default initialization creates bundle with empty manifest`() {
        val bundle = makeBundle()

        assertTrue(bundle.manifest.scripts.isEmpty())
        assertTrue(bundle.manifest.styles.isEmpty())
        assertTrue(bundle.manifest.allowedBlockTypes.isEmpty())
    }

    @Test
    fun `Default initialization sets downloadDate to current time`() {
        val beforeCreation = Date()
        val bundle = makeBundle()
        val afterCreation = Date()

        assertTrue(bundle.downloadDate >= beforeCreation)
        assertTrue(bundle.downloadDate <= afterCreation)
    }

    @Test
    fun `Initialization with manifest preserves manifest data`() {
        val manifest = createManifest(
            scripts = """<script src="https://example.com/app.js"></script>""",
            styles = """<link rel="stylesheet" href="https://example.com/style.css">""",
            blockTypes = listOf("core/paragraph", "core/heading")
        )

        val bundle = makeBundle(manifest = manifest)

        assertEquals(1, bundle.manifest.scripts.size)
        assertEquals(1, bundle.manifest.styles.size)
        assertEquals(listOf("core/paragraph", "core/heading"), bundle.manifest.allowedBlockTypes)
    }

    @Test
    fun `Initialization with custom downloadDate preserves date`() {
        val customDate = Date(1_000_000_000L)
        val bundle = makeBundle(downloadDate = customDate)

        assertEquals(customDate, bundle.downloadDate)
    }

    // MARK: - ID Tests

    @Test
    fun `Bundle ID equals manifest checksum`() {
        val manifest = createManifest(blockTypes = listOf("core/paragraph"))
        val bundle = makeBundle(manifest = manifest)

        assertEquals(manifest.checksum, bundle.id)
    }

    @Test
    fun `Empty bundle has empty ID`() {
        val bundle = makeBundle()
        assertEquals("empty", bundle.id)
    }

    @Test
    fun `Different manifests produce different bundle IDs`() {
        val manifest1 = createManifest(blockTypes = listOf("core/paragraph"))
        val manifest2 = createManifest(blockTypes = listOf("core/heading"))

        val bundle1 = makeBundle(manifest = manifest1)
        val bundle2 = makeBundle(manifest = manifest2)

        assertNotEquals(bundle1.id, bundle2.id)
    }

    @Test
    fun `Same manifest data produces same bundle ID`() {
        val jsonString = """
            {
                "scripts": "",
                "styles": "",
                "allowed_block_types": ["core/paragraph"]
            }
        """.trimIndent()

        val manifest1 = createManifestFromJson(jsonString)
        val manifest2 = createManifestFromJson(jsonString)

        val bundle1 = makeBundle(manifest = manifest1)
        val bundle2 = makeBundle(manifest = manifest2)

        assertEquals(bundle1.id, bundle2.id)
    }

    // MARK: - assetCount Tests

    @Test
    fun `assetCount returns zero for empty bundle`() {
        val bundle = makeBundle()
        assertEquals(0, bundle.assetCount)
    }

    @Test
    fun `assetCount reflects manifest asset URLs`() {
        val manifest = createManifest(
            scripts = """<script src="https://example.com/script1.js"></script><script src="https://example.com/script2.js"></script>""",
            styles = """<link rel="stylesheet" href="https://example.com/style.css">"""
        )
        val bundle = makeBundle(manifest = manifest)

        assertEquals(3, bundle.assetCount)
    }

    // MARK: - Codable Tests

    @Test
    fun `Bundle can be encoded and decoded`() {
        val manifest = createManifest(
            scripts = """<script src="https://example.com/app.js"></script>""",
            blockTypes = listOf("core/paragraph", "core/image")
        )
        val originalBundle = makeBundle(manifest = manifest)

        val rawBundle = EditorAssetBundle.RawAssetBundle(
            manifest = originalBundle.manifest,
            downloadDate = originalBundle.downloadDate
        )

        val encoded = json.encodeToString(rawBundle)
        val decoded = json.decodeFromString<EditorAssetBundle.RawAssetBundle>(encoded)

        assertEquals(originalBundle.manifest.checksum, decoded.manifest.checksum)
        assertEquals(originalBundle.downloadDate.time, decoded.downloadDate)
        assertEquals(originalBundle.manifest.allowedBlockTypes, decoded.manifest.allowedBlockTypes)
    }

    @Test
    fun `Bundle preserves rawScripts through encoding`() {
        val rawScripts = """<script src="https://example.com/app.js"></script><script>console.log('inline');</script>"""
        val manifest = createManifest(scripts = rawScripts)
        val originalBundle = makeBundle(manifest = manifest)

        val rawBundle = EditorAssetBundle.RawAssetBundle(
            manifest = originalBundle.manifest,
            downloadDate = originalBundle.downloadDate
        )

        val encoded = json.encodeToString(rawBundle)
        val decoded = json.decodeFromString<EditorAssetBundle.RawAssetBundle>(encoded)

        assertEquals(originalBundle.manifest.rawScripts, decoded.manifest.rawScripts)
    }

    @Test
    fun `Bundle preserves rawStyles through encoding`() {
        val rawStyles = """<link rel="stylesheet" href="https://example.com/style.css"><style>body {}</style>"""
        val manifest = createManifest(styles = rawStyles)
        val originalBundle = makeBundle(manifest = manifest)

        val rawBundle = EditorAssetBundle.RawAssetBundle(
            manifest = originalBundle.manifest,
            downloadDate = originalBundle.downloadDate
        )

        val encoded = json.encodeToString(rawBundle)
        val decoded = json.decodeFromString<EditorAssetBundle.RawAssetBundle>(encoded)

        assertEquals(originalBundle.manifest.rawStyles, decoded.manifest.rawStyles)
    }

    // MARK: - File Initialization Tests

    @Test
    fun `Bundle can be initialized from file`() {
        val manifest = createManifest(blockTypes = listOf("core/paragraph"))
        val originalBundle = makeBundle(manifest = manifest)

        // Create temp directory structure
        val tempDir = createTempDir()

        // Write manifest.json
        val manifestFile = File(tempDir, "manifest.json")
        val rawBundle = EditorAssetBundle.RawAssetBundle(
            manifest = originalBundle.manifest,
            downloadDate = originalBundle.downloadDate
        )
        val encoded = json.encodeToString(rawBundle)
        manifestFile.writeText(encoded)

        // Initialize from file
        val loadedBundle = EditorAssetBundle.fromFile(manifestFile)

        assertEquals(originalBundle.id, loadedBundle.id)
        assertEquals(originalBundle.manifest.allowedBlockTypes, loadedBundle.manifest.allowedBlockTypes)

        // Clean up
        tempDir.deleteRecursively()
    }

    @Test(expected = Exception::class)
    fun `Bundle initialization from invalid file throws error`() {
        val invalidFile = File("/nonexistent/path/bundle.json")
        EditorAssetBundle.fromFile(invalidFile)
    }

    @Test(expected = Exception::class)
    fun `Bundle initialization from invalid JSON throws error`() {
        val tempFile = File.createTempFile("test", ".json")
        tempFile.writeText("invalid json")

        try {
            EditorAssetBundle.fromFile(tempFile)
        } finally {
            tempFile.delete()
        }
    }

    // MARK: - hasAssetData Tests

    @Test
    fun `hasAssetData returns false for non-existent file`() {
        val bundle = makeBundle()
        val url = "https://example.com/nonexistent.js"

        assertFalse(bundle.hasAssetData(url))
    }

    @Test
    fun `hasAssetData returns true when file exists at expected path`() {
        // Create temp directory and file
        val tempDir = createTempDir()
        val assetDir = File(tempDir, "wp-content/plugins")
        assetDir.mkdirs()
        val assetFile = File(assetDir, "script.js")
        assetFile.writeText("test")

        val bundle = makeBundle(bundleRoot = tempDir)
        val url = "https://example.com/wp-content/plugins/script.js"

        assertTrue(bundle.hasAssetData(url))

        // Clean up
        tempDir.deleteRecursively()
    }

    // MARK: - assetDataPath Tests

    @Test
    fun `assetDataPath returns correct path based on URL path`() {
        val tempDir = createTempDir()
        val bundle = makeBundle(bundleRoot = tempDir)

        val url = "https://example.com/wp-content/plugins/script.js"
        val result = bundle.assetDataPath(url)

        assertTrue(result.path.contains("/wp-content/plugins/script.js"))

        tempDir.deleteRecursively()
    }

    @Test(expected = IllegalArgumentException::class)
    fun `assetDataPath throws for path traversal attempt with parent directory`() {
        val tempDir = createTempDir()
        val bundle = makeBundle(bundleRoot = tempDir)

        try {
            bundle.assetDataPath("https://example.com/../../../etc/passwd")
        } finally {
            tempDir.deleteRecursively()
        }
    }

    @Test
    fun `assetDataPath allows valid nested paths`() {
        val tempDir = createTempDir()
        val bundle = makeBundle(bundleRoot = tempDir)

        val url = "https://example.com/wp-content/plugins/my-plugin/assets/js/script.js"
        val result = bundle.assetDataPath(url)

        assertTrue(result.canonicalPath.startsWith(tempDir.canonicalPath))

        tempDir.deleteRecursively()
    }

    @Test
    fun `assetDataPath normalizes paths with dot segments`() {
        val tempDir = createTempDir()
        val bundle = makeBundle(bundleRoot = tempDir)

        // This path has ./  which should be normalized but stay within bundle
        val url = "https://example.com/wp-content/./plugins/script.js"
        val result = bundle.assetDataPath(url)

        assertTrue(result.canonicalPath.startsWith(tempDir.canonicalPath))
        assertTrue(result.path.contains("plugins/script.js"))

        tempDir.deleteRecursively()
    }

    // MARK: - assetData Tests

    @Test
    fun `assetData returns data for existing file`() {
        // Create temp directory and file
        val tempDir = createTempDir()
        val testContent = "console.log('test');"
        val assetFile = File(tempDir, "script.js")
        assetFile.writeText(testContent)

        val bundle = makeBundle(bundleRoot = tempDir)

        val requestUrl = "https://example.com/script.js"
        val data = bundle.assetData(requestUrl)

        assertEquals(testContent, String(data))

        // Clean up
        tempDir.deleteRecursively()
    }

    @Test(expected = Exception::class)
    fun `assetData throws when file doesn't exist`() {
        val bundle = makeBundle()
        val url = "https://example.com/nonexistent.js"
        bundle.assetData(url)
    }

    // MARK: - Equatable Tests

    @Test
    fun `Equal bundles are equal`() {
        val manifest = createManifest(blockTypes = listOf("core/paragraph"))
        val date = Date(1_700_000_000_000L)

        val bundle1 = makeBundle(manifest = manifest, downloadDate = date)
        val bundle2 = makeBundle(manifest = manifest, downloadDate = date)

        assertEquals(bundle1, bundle2)
    }

    @Test
    fun `Bundles with different manifests are not equal`() {
        val manifest1 = createManifest(blockTypes = listOf("core/paragraph"))
        val manifest2 = createManifest(blockTypes = listOf("core/heading"))

        val bundle1 = makeBundle(manifest = manifest1)
        val bundle2 = makeBundle(manifest = manifest2)

        assertNotEquals(bundle1, bundle2)
    }

    @Test
    fun `Bundles with different downloadDates are not equal`() {
        val manifest = createManifest(blockTypes = listOf("core/paragraph"))

        val bundle1 = makeBundle(manifest = manifest, downloadDate = Date(1000))
        val bundle2 = makeBundle(manifest = manifest, downloadDate = Date(2000))

        assertNotEquals(bundle1, bundle2)
    }

    // MARK: - Integration Tests

    @Test
    fun `Bundle round-trip through file system preserves all data`() {
        val manifest = createManifest(
            scripts = """<script src="https://example.com/app.js"></script>""",
            styles = """<link rel="stylesheet" href="https://example.com/style.css">""",
            blockTypes = listOf("core/paragraph", "core/heading", "jetpack/ai-assistant")
        )
        val customDate = Date(1_700_000_000_000L)
        val originalBundle = makeBundle(manifest = manifest, downloadDate = customDate)

        // Create temp directory
        val tempDir = createTempDir()

        // Write to file
        val tempFile = File(tempDir, "manifest.json")
        val rawBundle = EditorAssetBundle.RawAssetBundle(
            manifest = originalBundle.manifest,
            downloadDate = originalBundle.downloadDate
        )
        val encoded = json.encodeToString(rawBundle)
        tempFile.writeText(encoded)

        // Read back
        val loadedBundle = EditorAssetBundle.fromFile(tempFile)

        // Verify all data preserved
        assertEquals(originalBundle.id, loadedBundle.id)
        assertEquals(originalBundle.downloadDate, loadedBundle.downloadDate)
        assertEquals(originalBundle.manifest.scripts, loadedBundle.manifest.scripts)
        assertEquals(originalBundle.manifest.styles, loadedBundle.manifest.styles)
        assertEquals(originalBundle.manifest.allowedBlockTypes, loadedBundle.manifest.allowedBlockTypes)
        assertEquals(originalBundle.manifest.rawScripts, loadedBundle.manifest.rawScripts)
        assertEquals(originalBundle.manifest.rawStyles, loadedBundle.manifest.rawStyles)
        assertEquals(originalBundle.manifest.checksum, loadedBundle.manifest.checksum)

        // Clean up
        tempDir.deleteRecursively()
    }

    @Test
    fun `Multiple bundles with different dates have same ID if same manifest`() {
        val manifest = createManifest(blockTypes = listOf("core/paragraph"))

        val bundle1 = makeBundle(manifest = manifest, downloadDate = Date(1000))
        val bundle2 = makeBundle(manifest = manifest, downloadDate = Date(2000))

        assertEquals(bundle1.id, bundle2.id)
        assertNotEquals(bundle1.downloadDate, bundle2.downloadDate)
    }

    // MARK: - EditorRepresentation Tests

    @Test
    fun `setEditorRepresentation writes file to bundle root`() {
        val tempDir = createTempDir()

        val bundle = makeBundle(bundleRoot = tempDir)
        val representation = RemoteEditorAssetManifest.RawManifest(
            scripts = """<script src="test.js"></script>""",
            styles = """<link href="test.css">""",
            allowedBlockTypes = listOf("core/paragraph")
        )

        bundle.setEditorRepresentation(representation)

        val filePath = File(tempDir, "editor-representation.json")
        assertTrue(filePath.exists())

        tempDir.deleteRecursively()
    }

    @Test
    fun `getEditorRepresentation returns typed EditorRepresentation`() {
        val tempDir = createTempDir()

        val bundle = makeBundle(bundleRoot = tempDir)
        val original = RemoteEditorAssetManifest.RawManifest(
            scripts = """<script src="plugin.js"></script>""",
            styles = """<link href="theme.css">""",
            allowedBlockTypes = listOf("core/paragraph", "core/heading")
        )

        bundle.setEditorRepresentation(original)

        val retrieved = bundle.getEditorRepresentation()

        assertEquals(original.scripts, retrieved.scripts)
        assertEquals(original.styles, retrieved.styles)
        assertEquals(original.allowedBlockTypes, retrieved.allowedBlockTypes)

        tempDir.deleteRecursively()
    }

    @Test
    fun `getEditorRepresentation returns map for JSON serialization`() {
        val tempDir = createTempDir()

        val bundle = makeBundle(bundleRoot = tempDir)
        val original = RemoteEditorAssetManifest.RawManifest(
            scripts = """<script src="app.js"></script>""",
            styles = """<link href="style.css">""",
            allowedBlockTypes = listOf("core/image")
        )

        bundle.setEditorRepresentation(original)

        val retrieved = bundle.getEditorRepresentationAsMap()

        assertEquals(original.scripts, retrieved["scripts"])
        assertEquals(original.styles, retrieved["styles"])
        assertEquals(original.allowedBlockTypes, retrieved["allowed_block_types"])

        tempDir.deleteRecursively()
    }

    @Test(expected = Exception::class)
    fun `getEditorRepresentation throws when file does not exist`() {
        val tempDir = createTempDir()
        val bundle = makeBundle(bundleRoot = tempDir)

        try {
            bundle.getEditorRepresentation()
        } finally {
            tempDir.deleteRecursively()
        }
    }

    @Test
    fun `setEditorRepresentation overwrites existing file`() {
        val tempDir = createTempDir()

        val bundle = makeBundle(bundleRoot = tempDir)

        val first = RemoteEditorAssetManifest.RawManifest(
            scripts = "first",
            styles = "first",
            allowedBlockTypes = listOf("first")
        )
        bundle.setEditorRepresentation(first)

        val second = RemoteEditorAssetManifest.RawManifest(
            scripts = "second",
            styles = "second",
            allowedBlockTypes = listOf("second")
        )
        bundle.setEditorRepresentation(second)

        val retrieved = bundle.getEditorRepresentation()

        assertEquals("second", retrieved.scripts)
        assertEquals("second", retrieved.styles)
        assertEquals(listOf("second"), retrieved.allowedBlockTypes)

        tempDir.deleteRecursively()
    }

    @Test
    fun `EditorRepresentation round-trip preserves all fields`() {
        val tempDir = createTempDir()

        val bundle = makeBundle(bundleRoot = tempDir)
        val original = RemoteEditorAssetManifest.RawManifest(
            scripts = """<script src="https://example.com/gutenberg.js?ver=1.0"></script><script>console.log('inline');</script>""",
            styles = """<link rel="stylesheet" href="https://example.com/editor.css"><style>.block { color: red; }</style>""",
            allowedBlockTypes = listOf("core/paragraph", "core/heading", "core/image", "jetpack/ai-assistant")
        )

        bundle.setEditorRepresentation(original)
        val retrieved = bundle.getEditorRepresentation()

        assertEquals(original, retrieved)

        tempDir.deleteRecursively()
    }

    // MARK: - Test Helpers

    private fun makeBundle(
        manifest: LocalEditorAssetManifest = LocalEditorAssetManifest.empty,
        downloadDate: Date? = null,
        bundleRoot: File = createTempDir()
    ): EditorAssetBundle {
        return if (downloadDate != null) {
            EditorAssetBundle(manifest = manifest, downloadDate = downloadDate, bundleRoot = bundleRoot)
        } else {
            EditorAssetBundle(manifest = manifest, bundleRoot = bundleRoot)
        }
    }

    private fun createManifest(
        scripts: String = "",
        styles: String = "",
        blockTypes: List<String> = emptyList()
    ): LocalEditorAssetManifest {
        val blockTypesJson = blockTypes.joinToString(", ") { "\"$it\"" }
        val jsonString = """
            {
                "scripts": ${escapeJsonString(scripts)},
                "styles": ${escapeJsonString(styles)},
                "allowed_block_types": [$blockTypesJson]
            }
        """.trimIndent()
        return createManifestFromJson(jsonString)
    }

    private fun createManifestFromJson(jsonString: String): LocalEditorAssetManifest {
        val remote = RemoteEditorAssetManifest.fromData(jsonString)
        return LocalEditorAssetManifest.fromRemoteManifest(remote)
    }

    private fun escapeJsonString(string: String): String {
        val escaped = string
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
        return "\"$escaped\""
    }

    private fun createTempDir(): File {
        val tempDir = File(System.getProperty("java.io.tmpdir"), UUID.randomUUID().toString())
        tempDir.mkdirs()
        return tempDir
    }
}
