package org.wordpress.gutenberg

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.wordpress.gutenberg.model.EditorAssetBundle
import org.wordpress.gutenberg.model.EditorCachePolicy
import org.wordpress.gutenberg.model.EditorConfiguration
import org.wordpress.gutenberg.model.EditorProgress
import org.wordpress.gutenberg.model.LocalEditorAssetManifest
import org.wordpress.gutenberg.model.TestResources
import org.wordpress.gutenberg.model.http.EditorHTTPHeaders
import org.wordpress.gutenberg.stores.EditorAssetsLibrary
import java.io.File
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList

class EditorAssetsLibraryTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private lateinit var storageRoot: File

    companion object {
        private const val TEST_SITE_URL = "https://example.com"
        private const val TEST_API_ROOT = "https://example.com/wp-json"

        val testConfiguration: EditorConfiguration = EditorConfiguration.builder(
            TEST_SITE_URL,
            TEST_API_ROOT,
            "post"
        )
            .setPlugins(true)
            .setThemeStyles(true)
            .build()

        val minimalConfiguration: EditorConfiguration = EditorConfiguration.builder(
            TEST_SITE_URL,
            TEST_API_ROOT,
            "post"
        )
            .setPlugins(false)
            .setThemeStyles(false)
            .build()
    }

    @Before
    fun setUp() {
        storageRoot = tempFolder.newFolder("assets")
    }

    private fun makeLibrary(
        configuration: EditorConfiguration = testConfiguration,
        httpClient: EditorHTTPClientProtocol = EditorAssetsLibraryMockHTTPClient(),
        cachePolicy: EditorCachePolicy = EditorCachePolicy.Always
    ): EditorAssetsLibrary {
        return EditorAssetsLibrary(
            configuration = configuration,
            httpClient = httpClient,
            cachePolicy = cachePolicy,
            storageRoot = storageRoot,
            tempStorageRoot = tempFolder.newFolder("temp-storage")
        )
    }

    /** Helper to create a unique manifest JSON for each test */
    private fun uniqueManifestJSON(identifier: String): String {
        return """
            {
                "scripts": "",
                "styles": "",
                "allowed_block_types": ["$identifier"]
            }
        """.trimIndent()
    }

    // MARK: - hasBundle Tests

    @Test
    fun `hasBundle returns false for non-existent checksum`() {
        val library = makeLibrary()

        val result = library.hasBundle("nonexistent-checksum-12345")
        assertFalse(result)
    }

    // MARK: - existingBundle Tests

    @Test
    fun `existingBundle returns nil for non-existent checksum`() {
        val library = makeLibrary()

        val result = library.existingBundle("nonexistent-checksum-12345")
        assertNull(result)
    }

    // MARK: - fetchManifest Tests

    @Test
    fun `fetchManifest fetches and parses remote manifest`() = runBlocking {
        val manifestJSON = """
            {
                "scripts": "<script src=\"https://example.com/plugin.js\"></script>",
                "styles": "<link rel=\"stylesheet\" href=\"https://example.com/plugin.css\">",
                "allowed_block_types": ["core/paragraph", "core/heading"]
            }
        """.trimIndent()

        val mockClient = EditorAssetsLibraryMockHTTPClient()
        mockClient.getResponse = manifestJSON.toByteArray()

        val library = makeLibrary(httpClient = mockClient, cachePolicy = EditorCachePolicy.Ignore)

        val manifest = library.fetchManifest()

        assertEquals(listOf("core/paragraph", "core/heading"), manifest.allowedBlockTypes)
        assertTrue(manifest.rawScripts.contains("plugin.js"))
        assertTrue(manifest.rawStyles.contains("plugin.css"))
    }

    @Test
    fun `fetchManifest with ignore cache policy always fetches new data`() = runBlocking {
        val manifestJSON = """
            {
                "scripts": "",
                "styles": "",
                "allowed_block_types": ["core/paragraph"]
            }
        """.trimIndent()

        val mockClient = EditorAssetsLibraryMockHTTPClient()
        mockClient.getResponse = manifestJSON.toByteArray()

        val library = makeLibrary(httpClient = mockClient, cachePolicy = EditorCachePolicy.Ignore)

        library.fetchManifest()
        library.fetchManifest()

        assertEquals(2, mockClient.getCallCount)
    }

    @Test
    fun `fetchManifest with always cache policy returns cached manifest when bundle exists on disk`() = runBlocking {
        val manifestJSON = uniqueManifestJSON("test-cached-manifest-${UUID.randomUUID()}")

        val mockClient = EditorAssetsLibraryMockHTTPClient()
        mockClient.getResponse = manifestJSON.toByteArray()

        val library = makeLibrary(httpClient = mockClient, cachePolicy = EditorCachePolicy.Always)

        // First, fetch the manifest and create a bundle on disk
        val originalManifest = library.fetchManifest()
        library.buildBundle(originalManifest)

        // Now fetch again - should return the on-disk manifest
        val cachedManifest = library.fetchManifest()

        // The checksums should match since it's the same manifest data
        assertEquals(cachedManifest.checksum, originalManifest.checksum)

        // Verify we made 2 HTTP calls (one for each fetchManifest)
        assertEquals(2, mockClient.getCallCount)
    }

    @Test
    fun `fetchManifest with always cache policy falls back to new manifest when no bundle exists`() = runBlocking {
        val manifestJSON = uniqueManifestJSON("test-no-cache-fallback-${UUID.randomUUID()}")

        val mockClient = EditorAssetsLibraryMockHTTPClient()
        mockClient.getResponse = manifestJSON.toByteArray()

        val library = makeLibrary(httpClient = mockClient, cachePolicy = EditorCachePolicy.Always)

        // Fetch with always cache policy when no bundle exists on disk
        val manifest = library.fetchManifest()

        // Should still return a valid manifest (created from remote data)
        assertTrue(manifest.checksum.isNotEmpty())
        assertEquals(1, mockClient.getCallCount)
    }

    // MARK: - readAssetBundles Tests

    @Test
    fun `readAssetBundles returns empty list when no bundles directory exists`() {
        val library = makeLibrary()
        assertTrue(library.readAssetBundles().isEmpty())
    }

    @Test
    fun `readAssetBundles returns empty list when directory exists but has no bundles`() {
        val library = makeLibrary()

        // Create the storage root directory without any bundles
        storageRoot.mkdirs()

        val bundles = library.readAssetBundles()
        assertTrue(bundles.isEmpty())
    }

    @Test
    fun `readAssetBundles returns single bundle after buildBundle`() = runBlocking {
        val manifestJSON = uniqueManifestJSON("test-single-bundle-${UUID.randomUUID()}")

        val mockClient = EditorAssetsLibraryMockHTTPClient()
        mockClient.getResponse = manifestJSON.toByteArray()

        val library = makeLibrary(httpClient = mockClient, cachePolicy = EditorCachePolicy.Ignore)

        val manifest = library.fetchManifest()
        val createdBundle = library.buildBundle(manifest)

        val bundles = library.readAssetBundles()

        assertEquals(1, bundles.size)
        assertEquals(bundles.first().id, createdBundle.id)
    }

    @Test
    fun `readAssetBundles returns multiple bundles sorted by download date`() = runBlocking {
        val mockClient = EditorAssetsLibraryMockHTTPClient()
        val library = makeLibrary(httpClient = mockClient, cachePolicy = EditorCachePolicy.Ignore)

        // Create first bundle
        val manifest1JSON = uniqueManifestJSON("test-multi-bundle-1-${UUID.randomUUID()}")
        mockClient.getResponse = manifest1JSON.toByteArray()

        val manifest1 = library.fetchManifest()
        val bundle1 = library.buildBundle(manifest1)

        // Small delay to ensure different download dates
        Thread.sleep(10)

        // Create second bundle
        val manifest2JSON = uniqueManifestJSON("test-multi-bundle-2-${UUID.randomUUID()}")
        mockClient.getResponse = manifest2JSON.toByteArray()

        val manifest2 = library.fetchManifest()
        val bundle2 = library.buildBundle(manifest2)

        val bundles = library.readAssetBundles()

        assertEquals(2, bundles.size)

        // Should be sorted newest to oldest (descending by downloadDate)
        assertEquals(bundles[0].id, bundle2.id)
        assertEquals(bundles[1].id, bundle1.id)
        assertTrue(bundles[0].downloadDate > bundles[1].downloadDate)
    }

    @Test
    fun `readAssetBundles ignores non-directory files in site root`() = runBlocking {
        val manifestJSON = uniqueManifestJSON("test-ignores-files-${UUID.randomUUID()}")

        val mockClient = EditorAssetsLibraryMockHTTPClient()
        mockClient.getResponse = manifestJSON.toByteArray()

        val library = makeLibrary(httpClient = mockClient, cachePolicy = EditorCachePolicy.Ignore)

        val manifest = library.fetchManifest()
        library.buildBundle(manifest)

        // Add a non-directory file to the storage root
        val randomFile = File(storageRoot, "random-file.txt")
        randomFile.writeText("random content")

        val bundles = library.readAssetBundles()

        // Should only return the actual bundle, not the random file
        assertEquals(1, bundles.size)
    }

    @Test
    fun `readAssetBundles returns bundles with correct manifest data`() = runBlocking {
        val blockTypes = listOf("core/paragraph", "core/heading", "core/image")
        val manifestJSON = """
            {
                "scripts": "",
                "styles": "",
                "allowed_block_types": ["core/paragraph", "core/heading", "core/image"]
            }
        """.trimIndent()

        val mockClient = EditorAssetsLibraryMockHTTPClient()
        mockClient.getResponse = manifestJSON.toByteArray()

        val library = makeLibrary(httpClient = mockClient, cachePolicy = EditorCachePolicy.Ignore)

        val manifest = library.fetchManifest()
        library.buildBundle(manifest)

        val bundles = library.readAssetBundles()

        assertEquals(1, bundles.size)

        val retrievedBundle = bundles[0]
        assertEquals(blockTypes, retrievedBundle.manifest.allowedBlockTypes)
    }

    // MARK: - buildBundle Tests

    @Test
    fun `buildBundle returns bundle for manifest with no assets`() = runBlocking {
        val manifestJSON = uniqueManifestJSON("test-empty-bundle-${UUID.randomUUID()}")

        val mockClient = EditorAssetsLibraryMockHTTPClient()
        mockClient.getResponse = manifestJSON.toByteArray()

        val library = makeLibrary(httpClient = mockClient, cachePolicy = EditorCachePolicy.Ignore)

        val manifest = library.fetchManifest()

        val bundle = library.buildBundle(manifest)

        assertEquals(bundle.manifest.checksum, manifest.checksum)
        assertTrue(bundle.id.isNotEmpty())
        assertEquals(0, mockClient.downloadCallCount)
    }

    @Test
    fun `buildBundle downloads all script and style assets`() = runBlocking {
        val manifestJSON = """
            {
                "scripts": "<script src=\"https://example.com/script1.js\"></script><script src=\"https://example.com/script2.js\"></script>",
                "styles": "<link rel=\"stylesheet\" href=\"https://example.com/style.css\">",
                "allowed_block_types": ["core/paragraph"]
            }
        """.trimIndent()

        val mockClient = EditorAssetsLibraryMockHTTPClient()
        mockClient.getResponse = manifestJSON.toByteArray()

        val library = makeLibrary(httpClient = mockClient, cachePolicy = EditorCachePolicy.Ignore)

        val manifest = library.fetchManifest()

        val progressTracker = ProgressTracker()

        library.buildBundle(manifest) { progress ->
            progressTracker.append(progress)
        }

        assertEquals(3, mockClient.downloadCallCount)

        // Should have downloaded 3 assets (2 scripts + 1 style)
        assertTrue(mockClient.downloadedURLs.contains("https://example.com/script1.js"))
        assertTrue(mockClient.downloadedURLs.contains("https://example.com/script2.js"))
        assertTrue(mockClient.downloadedURLs.contains("https://example.com/style.css"))

        // Progress should have been reported for each asset
        assertEquals(3, progressTracker.count)
    }

    @Test
    fun `buildBundle reports progress correctly`() = runBlocking {
        val manifestJSON = """
            {
                "scripts": "<script src=\"https://example.com/a.js\"></script><script src=\"https://example.com/b.js\"></script>",
                "styles": "",
                "allowed_block_types": []
            }
        """.trimIndent()

        val mockClient = EditorAssetsLibraryMockHTTPClient()
        mockClient.getResponse = manifestJSON.toByteArray()

        val library = makeLibrary(httpClient = mockClient, cachePolicy = EditorCachePolicy.Ignore)

        val manifest = library.fetchManifest()

        val progressTracker = ProgressTracker()
        library.buildBundle(manifest) { progress ->
            progressTracker.append(progress)
        }

        // Should have 2 progress updates
        assertEquals(2, progressTracker.count)

        // All updates should have total == 2
        for (progress in progressTracker.updates) {
            assertEquals(2, progress.total)
        }

        // Final progress should be complete
        val lastProgress = progressTracker.updates.lastOrNull()
        assertNotNull(lastProgress)
        assertEquals(1.0, lastProgress!!.fractionCompleted, 0.0)
    }

    // MARK: - downloadAssetBundle Tests

    @Test
    fun `downloadAssetBundle fetches manifest and builds bundle`() = runBlocking {
        val manifestJSON = uniqueManifestJSON("test-download-bundle-${UUID.randomUUID()}")

        val mockClient = EditorAssetsLibraryMockHTTPClient()
        mockClient.getResponse = manifestJSON.toByteArray()

        val library = makeLibrary(httpClient = mockClient)

        val bundle = library.downloadAssetBundle()

        assertTrue(bundle.id.isNotEmpty())
        assertEquals(1, mockClient.getCallCount)  // One call for the manifest
    }

    @Test
    fun `downloadAssetBundle reports progress`() = runBlocking {
        val manifestJSON = """
            {
                "scripts": "<script src=\"https://example.com/script.js\"></script>",
                "styles": "",
                "allowed_block_types": []
            }
        """.trimIndent()

        val mockClient = EditorAssetsLibraryMockHTTPClient()
        mockClient.getResponse = manifestJSON.toByteArray()

        val library = makeLibrary(httpClient = mockClient)

        val progressTracker = ProgressTracker()
        library.downloadAssetBundle { progress ->
            progressTracker.append(progress)
        }

        assertEquals(1, progressTracker.count)
        assertEquals(1, progressTracker.updates.first().total)
    }

    // MARK: - fetchManifest with Real Manifest Data Tests

    @Test
    fun `fetchManifest parses real manifest test case with many block types`() = runBlocking {
        val manifestData = TestResources.loadResource("editor-asset-manifest-test-case-1.json")

        val mockClient = EditorAssetsLibraryMockHTTPClient()
        mockClient.getResponse = manifestData.toByteArray()

        val library = makeLibrary(httpClient = mockClient, cachePolicy = EditorCachePolicy.Ignore)

        val manifest = library.fetchManifest()

        // Verify block types are parsed correctly
        assertTrue(manifest.allowedBlockTypes.contains("core/paragraph"))
        assertTrue(manifest.allowedBlockTypes.contains("core/heading"))
        assertTrue(manifest.allowedBlockTypes.contains("core/image"))
        assertTrue(manifest.allowedBlockTypes.contains("jetpack/ai-assistant"))
        assertTrue(manifest.allowedBlockTypes.size > 100)

        // Verify scripts are present
        assertTrue(manifest.rawScripts.contains("wp-polyfill"))
        assertTrue(manifest.rawScripts.contains("jquery"))
        assertTrue(manifest.rawScripts.contains("react"))
    }

    @Test
    fun `fetchManifest generates consistent checksum for same data`() = runBlocking {
        val manifestData = TestResources.loadResource("editor-asset-manifest-test-case-1.json")

        val mockClient = EditorAssetsLibraryMockHTTPClient()
        mockClient.getResponse = manifestData.toByteArray()

        val library = makeLibrary(httpClient = mockClient, cachePolicy = EditorCachePolicy.Ignore)

        val manifest1 = library.fetchManifest()
        val manifest2 = library.fetchManifest()

        assertEquals(manifest1.checksum, manifest2.checksum)
        assertTrue(manifest1.checksum.isNotEmpty())
    }

    // MARK: - EditorAssetBundle Tests

    @Test
    fun `EditorAssetBundle can be created from manifest`() = runBlocking {
        val manifestData = TestResources.loadResource("editor-asset-manifest-test-case-1.json")

        val mockClient = EditorAssetsLibraryMockHTTPClient()
        mockClient.getResponse = manifestData.toByteArray()

        val library = makeLibrary(httpClient = mockClient, cachePolicy = EditorCachePolicy.Ignore)

        val manifest = library.fetchManifest()

        val bundleRoot = tempFolder.newFolder("bundle")
        val bundle = EditorAssetBundle(manifest = manifest, bundleRoot = bundleRoot)

        assertEquals(bundle.id, manifest.checksum)
        assertEquals(bundle.manifest.allowedBlockTypes, manifest.allowedBlockTypes)
    }

    @Test
    fun `EditorAssetBundle downloadDate is set on creation`() {
        val beforeCreation = java.util.Date()

        val bundleRoot = tempFolder.newFolder("bundle")
        val bundle = EditorAssetBundle(manifest = LocalEditorAssetManifest.empty, bundleRoot = bundleRoot)

        val afterCreation = java.util.Date()

        assertTrue(bundle.downloadDate >= beforeCreation)
        assertTrue(bundle.downloadDate <= afterCreation)
    }

    @Test
    fun `Multiple bundles from same manifest have same ID`() = runBlocking {
        val manifestData = TestResources.loadResource("editor-asset-manifest-test-case-1.json")

        val mockClient = EditorAssetsLibraryMockHTTPClient()
        mockClient.getResponse = manifestData.toByteArray()

        val library = makeLibrary(httpClient = mockClient, cachePolicy = EditorCachePolicy.Ignore)

        val manifest = library.fetchManifest()

        val bundleRoot1 = tempFolder.newFolder("bundle1")
        val bundleRoot2 = tempFolder.newFolder("bundle2")
        val bundle1 = EditorAssetBundle(manifest = manifest, bundleRoot = bundleRoot1)
        val bundle2 = EditorAssetBundle(manifest = manifest, bundleRoot = bundleRoot2)

        assertEquals(bundle1.id, bundle2.id)
    }

    // MARK: - CachePolicy Tests

    @Test
    fun `EditorCachePolicy always is default behavior`() = runBlocking {
        val manifestJSON = """
            {
                "scripts": "",
                "styles": "",
                "allowed_block_types": []
            }
        """.trimIndent()

        val mockClient = EditorAssetsLibraryMockHTTPClient()
        mockClient.getResponse = manifestJSON.toByteArray()

        val library = makeLibrary(httpClient = mockClient)

        // Call fetchManifest with default cache policy
        library.fetchManifest()

        // The HTTP client should have been called
        assertEquals(1, mockClient.getCallCount)
    }

    @Test
    fun `EditorCachePolicy maxAge uses cached manifest when within timeout`() = runBlocking {
        val manifestJSON = uniqueManifestJSON("test-maxage-within-${UUID.randomUUID()}")

        val mockClient = EditorAssetsLibraryMockHTTPClient()
        mockClient.getResponse = manifestJSON.toByteArray()

        // Set maxAge to 1 hour (3600000 milliseconds)
        val library = makeLibrary(httpClient = mockClient, cachePolicy = EditorCachePolicy.MaxAge(3_600_000))

        // First fetch and create the bundle
        val originalManifest = library.fetchManifest()
        library.buildBundle(originalManifest)

        // Second fetch should use cached manifest since we're within the 1 hour timeout
        val cachedManifest = library.fetchManifest()

        assertEquals(cachedManifest.checksum, originalManifest.checksum)
        // Should have made 2 HTTP calls but second one used cached bundle
        assertEquals(2, mockClient.getCallCount)
    }

    @Test
    fun `EditorCachePolicy maxAge fetches new manifest when timeout expired`() = runBlocking {
        val manifestJSON = uniqueManifestJSON("test-maxage-expired-${UUID.randomUUID()}")

        val mockClient = EditorAssetsLibraryMockHTTPClient()
        mockClient.getResponse = manifestJSON.toByteArray()

        // Set maxAge to 0 milliseconds (immediately expired)
        val library = makeLibrary(httpClient = mockClient, cachePolicy = EditorCachePolicy.MaxAge(0))

        // First fetch and create the bundle
        val originalManifest = library.fetchManifest()
        library.buildBundle(originalManifest)

        // Second fetch should NOT use cached manifest since maxAge(0) means immediately expired
        val newManifest = library.fetchManifest()

        // The checksums should still match (same data) but the cache was bypassed
        assertEquals(newManifest.checksum, originalManifest.checksum)
        assertEquals(2, mockClient.getCallCount)
    }

    @Test
    fun `EditorCachePolicy maxAge with short timeout expires after delay`() = runBlocking {
        val manifestJSON = uniqueManifestJSON("test-maxage-delay-${UUID.randomUUID()}")

        val mockClient = EditorAssetsLibraryMockHTTPClient()
        mockClient.getResponse = manifestJSON.toByteArray()

        // Set maxAge to 50 milliseconds
        val library = makeLibrary(httpClient = mockClient, cachePolicy = EditorCachePolicy.MaxAge(50))

        // First fetch and create the bundle
        val originalManifest = library.fetchManifest()
        library.buildBundle(originalManifest)

        // Wait for the cache to expire
        Thread.sleep(100)

        // Third fetch should bypass cache since it's expired
        library.fetchManifest()

        // Both fetches should have made HTTP calls since cache expired
        assertEquals(2, mockClient.getCallCount)
    }

    @Test
    fun `EditorCachePolicy maxAge uses cache before expiry then fetches after`() = runBlocking {
        val manifestJSON = uniqueManifestJSON("test-maxage-transition-${UUID.randomUUID()}")

        val mockClient = EditorAssetsLibraryMockHTTPClient()
        mockClient.getResponse = manifestJSON.toByteArray()

        // Set maxAge to 100 milliseconds
        val library = makeLibrary(httpClient = mockClient, cachePolicy = EditorCachePolicy.MaxAge(100))

        // First fetch and create the bundle
        val originalManifest = library.fetchManifest()
        library.buildBundle(originalManifest)

        // Immediate second fetch should use cache (within 100ms)
        val cachedManifest = library.fetchManifest()
        assertEquals(cachedManifest.checksum, originalManifest.checksum)

        // Wait for cache to expire
        Thread.sleep(150)

        // Third fetch should create new manifest since cache expired
        val newManifest = library.fetchManifest()
        assertEquals(newManifest.checksum, originalManifest.checksum)

        // Should have made 3 HTTP calls total
        assertEquals(3, mockClient.getCallCount)
    }

    // MARK: - cleanup and purge Tests

    @Test
    fun `cleanup removes all bundles except the most recent`() = runBlocking {
        val mockClient = EditorAssetsLibraryMockHTTPClient()
        val library = makeLibrary(httpClient = mockClient, cachePolicy = EditorCachePolicy.Ignore)

        // Create first bundle
        mockClient.getResponse = uniqueManifestJSON("bundle-1-${UUID.randomUUID()}").toByteArray()
        val manifest1 = library.fetchManifest()
        library.buildBundle(manifest1)

        Thread.sleep(10)

        // Create second bundle
        mockClient.getResponse = uniqueManifestJSON("bundle-2-${UUID.randomUUID()}").toByteArray()
        val manifest2 = library.fetchManifest()
        library.buildBundle(manifest2)

        assertEquals(2, library.readAssetBundles().size)

        library.cleanup()

        val remainingBundles = library.readAssetBundles()
        assertEquals(1, remainingBundles.size)
        assertEquals(manifest2.checksum, remainingBundles[0].id)
    }

    @Test
    fun `purge removes all bundles`() = runBlocking {
        val mockClient = EditorAssetsLibraryMockHTTPClient()
        val library = makeLibrary(httpClient = mockClient, cachePolicy = EditorCachePolicy.Ignore)

        // Create bundles
        mockClient.getResponse = uniqueManifestJSON("bundle-1-${UUID.randomUUID()}").toByteArray()
        library.buildBundle(library.fetchManifest())

        mockClient.getResponse = uniqueManifestJSON("bundle-2-${UUID.randomUUID()}").toByteArray()
        library.buildBundle(library.fetchManifest())

        assertEquals(2, library.readAssetBundles().size)

        library.purge()

        assertTrue(library.readAssetBundles().isEmpty())
    }
}

// MARK: - Progress Tracker for Tests

class ProgressTracker {
    private val _updates = CopyOnWriteArrayList<EditorProgress>()

    val updates: List<EditorProgress>
        get() = _updates.toList()

    val count: Int
        get() = _updates.size

    fun append(progress: EditorProgress) {
        _updates.add(progress)
    }
}

// MARK: - Mock HTTP Client for EditorAssetsLibrary Tests

class EditorAssetsLibraryMockHTTPClient : EditorHTTPClientProtocol {

    var getResponse: ByteArray = ByteArray(0)
    var getCallCount = 0
        private set
    var downloadCallCount = 0
        private set
    var downloadedURLs = CopyOnWriteArrayList<String>()
        private set

    private val lock = Any()

    override suspend fun download(url: String, destination: File): EditorHTTPClientDownloadResponse {
        synchronized(lock) {
            downloadCallCount++
            downloadedURLs.add(url)
        }

        // Ensure parent directories exist
        destination.parentFile?.mkdirs()

        // Write mock content to the destination
        destination.writeText("mock content")

        return EditorHTTPClientDownloadResponse(
            file = destination,
            statusCode = 200,
            headers = EditorHTTPHeaders()
        )
    }

    override suspend fun perform(method: String, url: String): EditorHTTPClientResponse {
        synchronized(lock) {
            if (method == "GET") {
                getCallCount++
            }
        }

        return EditorHTTPClientResponse(
            data = getResponse,
            statusCode = 200,
            headers = EditorHTTPHeaders()
        )
    }
}
