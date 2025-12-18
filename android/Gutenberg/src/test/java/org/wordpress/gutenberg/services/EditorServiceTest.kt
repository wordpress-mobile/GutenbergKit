package org.wordpress.gutenberg.services

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.wordpress.gutenberg.EditorHTTPClientDownloadResponse
import org.wordpress.gutenberg.EditorHTTPClientProtocol
import org.wordpress.gutenberg.EditorHTTPClientResponse
import org.wordpress.gutenberg.model.EditorConfiguration
import org.wordpress.gutenberg.model.http.EditorHTTPHeaders
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList

class EditorServiceTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private lateinit var storageRoot: File
    private lateinit var cacheRoot: File

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
            .setAuthHeader("Bearer test-token")
            .build()
    }

    @Before
    fun setUp() {
        storageRoot = tempFolder.newFolder("storage")
        cacheRoot = tempFolder.newFolder("cache")
    }

    private fun makeService(
        configuration: EditorConfiguration = testConfiguration,
        httpClient: EditorHTTPClientProtocol = EditorServiceMockHTTPClient()
    ): EditorService {
        return EditorService.createForTesting(
            configuration = configuration,
            httpClient = httpClient,
            storageRoot = storageRoot,
            cacheRoot = cacheRoot
        )
    }

    // MARK: - fetchAssetBundleCount Tests

    @Test
    fun `fetchAssetBundleCount returns zero when no bundles exist`() {
        val service = makeService()
        assertEquals(0, service.fetchAssetBundleCount())
    }

    // MARK: - DependencyWeights Tests

    @Test
    fun `DependencyWeights have expected values`() {
        assertEquals(10.0, EditorService.DependencyWeights.EDITOR_SETTINGS.weight, 0.001)
        assertEquals(50.0, EditorService.DependencyWeights.ASSET_BUNDLE.weight, 0.001)
        assertEquals(10.0, EditorService.DependencyWeights.POST.weight, 0.001)
        assertEquals(10.0, EditorService.DependencyWeights.POST_TYPE.weight, 0.001)
        assertEquals(10.0, EditorService.DependencyWeights.ACTIVE_THEME.weight, 0.001)
        assertEquals(10.0, EditorService.DependencyWeights.SETTINGS_OPTIONS.weight, 0.001)
        assertEquals(10.0, EditorService.DependencyWeights.POST_TYPES.weight, 0.001)
    }

    @Test
    fun `DependencyWeights sum to expected total`() {
        val total = EditorService.DependencyWeights.entries.sumOf { it.weight }
        // Total should be 110 (10+50+10+10+10+10+10)
        assertEquals(110.0, total, 0.001)
    }

    @Test
    fun `DependencyWeights total companion property returns correct value`() {
        assertEquals(110.0, EditorService.DependencyWeights.total, 0.001)
    }

    // MARK: - cleanup and purge Tests

    @Test
    fun `cleanup does not throw when no bundles exist`() {
        val service = makeService()
        service.cleanup()
        service.cleanup() // Check that it can be called multiple times
    }

    @Test
    fun `purge completes without throwing for empty cache directory`() {
        val service = makeService()
        service.purge()
        service.purge() // Check that it can be called multiple times
    }

    // MARK: - prepare Tests with offline mode

    @Test
    fun `prepare returns empty dependencies when offline mode is enabled`() = runBlocking {
        val offlineConfiguration = testConfiguration.toBuilder()
            .setEnableOfflineMode(true)
            .build()

        val service = makeService(configuration = offlineConfiguration)
        val dependencies = service.prepare()

        assertNotNull(dependencies)
        assertEquals("undefined", dependencies.editorSettings.themeStyles)
    }
}

/**
 * Mock HTTP client for EditorService tests.
 */
class EditorServiceMockHTTPClient : EditorHTTPClientProtocol {

    var getCallCount = 0
        private set
    var downloadCallCount = 0
        private set
    var downloadedURLs = CopyOnWriteArrayList<String>()
        private set

    private val lock = Any()

    // Default responses
    private val emptyManifestJson = """
        {
            "scripts": "",
            "styles": "",
            "allowed_block_types": []
        }
    """.trimIndent()

    private val emptyEditorSettingsJson = """
        {
            "styles": []
        }
    """.trimIndent()

    private val emptyPostTypeJson = """
        {
            "name": "Posts",
            "slug": "post"
        }
    """.trimIndent()

    private val emptyPostTypesJson = """
        {
            "post": {"name": "Posts", "slug": "post"},
            "page": {"name": "Pages", "slug": "page"}
        }
    """.trimIndent()

    private val emptyThemeJson = """
        [{"name": "Twenty Twenty-Four"}]
    """.trimIndent()

    private val emptySettingsJson = """
        {"title": "Test Site"}
    """.trimIndent()

    override suspend fun download(url: String, destination: File): EditorHTTPClientDownloadResponse {
        synchronized(lock) {
            downloadCallCount++
            downloadedURLs.add(url)
        }

        destination.parentFile?.mkdirs()
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

        val responseData = when {
            url.contains("editor-assets") -> emptyManifestJson
            url.contains("wp-block-editor/v1/settings") -> emptyEditorSettingsJson
            url.contains("/wp/v2/types/") && url.contains("context=edit") -> emptyPostTypeJson
            url.contains("/wp/v2/types?context=view") -> emptyPostTypesJson
            url.contains("/wp/v2/themes") -> emptyThemeJson
            url.contains("/wp/v2/settings") -> emptySettingsJson
            url.contains("/wp/v2/posts/") -> """{"id": 1, "title": {"rendered": "Test"}}"""
            else -> "{}"
        }

        return EditorHTTPClientResponse(
            data = responseData.toByteArray(),
            statusCode = 200,
            headers = EditorHTTPHeaders()
        )
    }
}
