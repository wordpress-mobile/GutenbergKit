package org.wordpress.gutenberg.services

import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.TestScope
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
import org.wordpress.gutenberg.model.http.EditorHttpMethod
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList

class EditorServiceTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    // Coroutine Scope for Tests
    val testScope = TestScope()

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
            cacheRoot = cacheRoot,
            coroutineScope = testScope,
            tempStorageRoot = tempFolder.newFolder("temp-storage")
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

    // MARK: - preparePreloadList Tests (negative postID handling)

    @Test
    fun `prepare does not fetch post when postID is negative`() = runBlocking {
        val mockClient = EditorServiceMockHTTPClient()
        val configuration = testConfiguration.toBuilder()
            .setPostId(-1)
            .build()

        val service = makeService(configuration = configuration, httpClient = mockClient)
        service.prepare()

        // Verify no request was made to /posts/-1
        val postRequests = mockClient.requestedURLs.filter { it.contains("/posts/-1") }
        assertEquals(
            "Should not request /posts/-1 for negative post IDs",
            emptyList<String>(),
            postRequests
        )
    }

    @Test
    fun `prepare does not fetch post when postID is zero`() = runBlocking {
        val mockClient = EditorServiceMockHTTPClient()
        val configuration = testConfiguration.toBuilder()
            .setPostId(0)
            .build()

        val service = makeService(configuration = configuration, httpClient = mockClient)
        service.prepare()

        // Verify no request was made to /posts/0
        val postRequests = mockClient.requestedURLs.filter { it.contains("/posts/0") }
        assertEquals(
            "Should not request /posts/0 for zero post IDs",
            emptyList<String>(),
            postRequests
        )
    }

    @Test
    fun `prepare fetches post when postID is positive`() = runBlocking {
        val mockClient = EditorServiceMockHTTPClient()
        val configuration = testConfiguration.toBuilder()
            .setPostId(123)
            .build()

        val service = makeService(configuration = configuration, httpClient = mockClient)
        service.prepare()

        // Verify a request was made to /posts/123
        val postRequests = mockClient.requestedURLs.filter { it.contains("/posts/123") }
        assert(postRequests.isNotEmpty()) { "Should request /posts/123 for positive post IDs" }
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

    /// URLs requested via `perform()`. Use this to verify which endpoints were called.
    private val _requestedURLs = CopyOnWriteArrayList<String>()
    val requestedURLs: List<String> get() = _requestedURLs.toList()

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
            _requestedURLs.add(url)
        }

        destination.parentFile?.mkdirs()
        destination.writeText("mock content")

        return EditorHTTPClientDownloadResponse(
            file = destination,
            statusCode = 200,
            headers = EditorHTTPHeaders()
        )
    }

    override suspend fun perform(method: EditorHttpMethod, url: String): EditorHTTPClientResponse {
        synchronized(lock) {
            if (method == EditorHttpMethod.GET) {
                getCallCount++
            }
            _requestedURLs.add(url)
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
