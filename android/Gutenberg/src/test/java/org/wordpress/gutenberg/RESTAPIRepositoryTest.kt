package org.wordpress.gutenberg

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.wordpress.gutenberg.model.EditorCachePolicy
import org.wordpress.gutenberg.model.EditorConfiguration
import org.wordpress.gutenberg.model.EditorSettings
import org.wordpress.gutenberg.model.http.EditorHTTPHeaders
import org.wordpress.gutenberg.model.http.EditorHttpMethod
import org.wordpress.gutenberg.stores.EditorURLCache
import java.io.File

class RESTAPIRepositoryTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private lateinit var cacheRoot: File

    companion object {
        private const val TEST_SITE_URL = "https://example.com"
        private const val TEST_API_ROOT = "https://example.com/wp-json"
    }

    @Before
    fun setUp() {
        cacheRoot = tempFolder.newFolder("cache")
    }

    // MARK: - Test Fixtures

    private fun makeConfiguration(
        shouldUsePlugins: Boolean = true,
        shouldUseThemeStyles: Boolean = true
    ): EditorConfiguration {
        return EditorConfiguration.builder(TEST_SITE_URL, TEST_API_ROOT, "post")
            .setPlugins(shouldUsePlugins)
            .setThemeStyles(shouldUseThemeStyles)
            .setAuthHeader("Bearer test-token")
            .build()
    }

    private fun makeRepository(
        configuration: EditorConfiguration = makeConfiguration(),
        httpClient: EditorHTTPClientProtocol = MockHTTPClient()
    ): RESTAPIRepository {
        val cache = EditorURLCache(cacheRoot, EditorCachePolicy.Always)
        return RESTAPIRepository(
            configuration = configuration,
            httpClient = httpClient,
            cache = cache
        )
    }

    // MARK: - fetchPost Tests

    @Test
    fun `fetchPost returns response for valid post ID`() = runBlocking {
        val mockClient = MockHTTPClient()
        mockClient.getResponse = """{"id":123,"title":{"raw":"Test Post"}}"""

        val repository = makeRepository(httpClient = mockClient)

        val response = repository.fetchPost(id = 123)

        assertTrue(response.data.isNotEmpty())
        assertEquals(1, mockClient.getCallCount)
    }

    // MARK: - fetchEditorSettings Tests

    @Test
    fun `fetchEditorSettings returns undefined when theme styles disabled`() = runBlocking {
        val configuration = makeConfiguration(shouldUsePlugins = false, shouldUseThemeStyles = false)
        val mockClient = MockHTTPClient()
        val repository = makeRepository(configuration = configuration, httpClient = mockClient)

        val settings = repository.fetchEditorSettings()

        assertEquals(EditorSettings.undefined, settings)
        assertEquals(0, mockClient.getCallCount)
    }

    @Test
    fun `fetchEditorSettings returns undefined when plugins enabled but theme styles disabled`() = runBlocking {
        val configuration = makeConfiguration(shouldUsePlugins = true, shouldUseThemeStyles = false)
        val mockClient = MockHTTPClient()
        val repository = makeRepository(configuration = configuration, httpClient = mockClient)

        val settings = repository.fetchEditorSettings()

        assertEquals(EditorSettings.undefined, settings)
        assertEquals(0, mockClient.getCallCount)
    }

    @Test
    fun `fetchEditorSettings parses response correctly`() = runBlocking {
        val mockClient = MockHTTPClient()
        mockClient.getResponse = """{"styles":[{"css":".test{color:red}","isGlobalStyles":false}]}"""

        val repository = makeRepository(httpClient = mockClient)

        val settings = repository.fetchEditorSettings()

        assertTrue(settings.themeStyles.contains(".test{color:red}"))
    }

    @Test
    fun `fetchEditorSettings caches response`() = runBlocking {
        val mockClient = MockHTTPClient()
        mockClient.getResponse = """{"styles":[]}"""

        val configuration = makeConfiguration()
        val cache = EditorURLCache(cacheRoot, EditorCachePolicy.Always)
        val repository = RESTAPIRepository(
            configuration = configuration,
            httpClient = mockClient,
            cache = cache
        )

        repository.fetchEditorSettings()

        // Should be able to read from cache
        val cached = repository.readEditorSettings()
        assertNotNull(cached)
    }

    // MARK: - readEditorSettings Tests

    @Test
    fun `readEditorSettings returns null when not cached`() {
        val repository = makeRepository()

        val settings = repository.readEditorSettings()

        assertNull(settings)
    }

    @Test
    fun `readEditorSettings returns same values as fetchEditorSettings`() = runBlocking {
        val mockClient = MockHTTPClient()
        val rawJSON = """{"styles":[{"css":".theme-style{color:blue}","isGlobalStyles":true},{"css":".another{margin:0}","isGlobalStyles":false}]}"""
        mockClient.getResponse = rawJSON

        val configuration = makeConfiguration()
        val cache = EditorURLCache(cacheRoot, EditorCachePolicy.Always)
        val repository = RESTAPIRepository(
            configuration = configuration,
            httpClient = mockClient,
            cache = cache
        )

        val fetched = repository.fetchEditorSettings()
        val cached = repository.readEditorSettings()

        assertNotNull(cached)
        assertEquals(cached?.stringValue, fetched.stringValue)
        assertEquals(cached?.themeStyles, fetched.themeStyles)
        assertTrue(cached?.themeStyles?.contains(".theme-style{color:blue}") == true)
        assertTrue(cached?.themeStyles?.contains(".another{margin:0}") == true)
    }

    // MARK: - fetchPostType Tests

    @Test
    fun `fetchPostType returns response`() = runBlocking {
        val mockClient = MockHTTPClient()
        mockClient.getResponse = """{"slug":"post","name":"Posts"}"""

        val repository = makeRepository(httpClient = mockClient)

        val response = repository.fetchPostType("post")

        assertTrue(response.data.isNotEmpty())
    }

    @Test
    fun `fetchPostType caches response`() = runBlocking {
        val mockClient = MockHTTPClient()
        mockClient.getResponse = """{"slug":"post"}"""

        val configuration = makeConfiguration()
        val cache = EditorURLCache(cacheRoot, EditorCachePolicy.Always)
        val repository = RESTAPIRepository(
            configuration = configuration,
            httpClient = mockClient,
            cache = cache
        )

        repository.fetchPostType("post")

        assertNotNull(repository.readPostType("post"))
    }

    // MARK: - fetchActiveTheme Tests

    @Test
    fun `fetchActiveTheme returns response`() = runBlocking {
        val mockClient = MockHTTPClient()
        mockClient.getResponse = """[{"stylesheet":"twentytwentyfour"}]"""

        val repository = makeRepository(httpClient = mockClient)

        val response = repository.fetchActiveTheme()

        assertTrue(response.data.isNotEmpty())
    }

    @Test
    fun `fetchActiveTheme caches response`() = runBlocking {
        val mockClient = MockHTTPClient()
        mockClient.getResponse = """[{"stylesheet":"theme"}]"""

        val configuration = makeConfiguration()
        val cache = EditorURLCache(cacheRoot, EditorCachePolicy.Always)
        val repository = RESTAPIRepository(
            configuration = configuration,
            httpClient = mockClient,
            cache = cache
        )

        repository.fetchActiveTheme()

        assertNotNull(repository.readActiveTheme())
    }

    // MARK: - fetchSettingsOptions Tests

    @Test
    fun `fetchSettingsOptions returns response`() = runBlocking {
        val mockClient = MockHTTPClient()

        val repository = makeRepository(httpClient = mockClient)

        val response = repository.fetchSettingsOptions()

        // OPTIONS returns default empty response from mock
        assertNotNull(response)
    }

    // MARK: - fetchPostTypes Tests

    @Test
    fun `fetchPostTypes returns response`() = runBlocking {
        val mockClient = MockHTTPClient()
        mockClient.getResponse = """{"post":{"slug":"post"},"page":{"slug":"page"}}"""

        val repository = makeRepository(httpClient = mockClient)

        val response = repository.fetchPostTypes()

        assertTrue(response.data.isNotEmpty())
    }

    @Test
    fun `fetchPostTypes caches response`() = runBlocking {
        val mockClient = MockHTTPClient()
        mockClient.getResponse = """{"post":{}}"""

        val configuration = makeConfiguration()
        val cache = EditorURLCache(cacheRoot, EditorCachePolicy.Always)
        val repository = RESTAPIRepository(
            configuration = configuration,
            httpClient = mockClient,
            cache = cache
        )

        repository.fetchPostTypes()

        assertNotNull(repository.readPostTypes())
    }

    // MARK: - URL Building Tests

    @Test
    fun `URLs are normalized when API root has no trailing slash`() = runBlocking {
        val capturedURLs = mutableListOf<String>()
        val capturingClient = createCapturingClient { capturedURLs.add(it) }

        val configuration = EditorConfiguration.builder(
            TEST_SITE_URL,
            "https://example.com/wp-json",  // No trailing slash
            "post"
        ).setPlugins(true).setThemeStyles(true).setAuthHeader("Bearer test").build()

        val cache = EditorURLCache(cacheRoot, EditorCachePolicy.Always)
        val repository = RESTAPIRepository(configuration, capturingClient, cache)

        repository.fetchPost(id = 1)
        repository.fetchPostType("post")
        repository.fetchActiveTheme()
        repository.fetchPostTypes()

        val expectedURLs = setOf(
            "https://example.com/wp-json/wp/v2/posts/1?context=edit",
            "https://example.com/wp-json/wp/v2/types/post?context=edit",
            "https://example.com/wp-json/wp/v2/themes?context=edit&status=active",
            "https://example.com/wp-json/wp/v2/types?context=view"
        )

        assertEquals(expectedURLs, capturedURLs.toSet())
    }

    @Test
    fun `URLs are normalized when API root has trailing slash`() = runBlocking {
        val capturedURLs = mutableListOf<String>()
        val capturingClient = createCapturingClient { capturedURLs.add(it) }

        val configuration = EditorConfiguration.builder(
            TEST_SITE_URL,
            "https://example.com/wp-json/",  // With trailing slash
            "post"
        ).setPlugins(true).setThemeStyles(true).setAuthHeader("Bearer test").build()

        val cache = EditorURLCache(cacheRoot, EditorCachePolicy.Always)
        val repository = RESTAPIRepository(configuration, capturingClient, cache)

        repository.fetchPost(id = 1)
        repository.fetchPostType("post")
        repository.fetchActiveTheme()
        repository.fetchPostTypes()

        val expectedURLs = setOf(
            "https://example.com/wp-json/wp/v2/posts/1?context=edit",
            "https://example.com/wp-json/wp/v2/types/post?context=edit",
            "https://example.com/wp-json/wp/v2/themes?context=edit&status=active",
            "https://example.com/wp-json/wp/v2/types?context=view"
        )

        assertEquals(expectedURLs, capturedURLs.toSet())
    }

    @Test
    fun `URLs include namespace when siteApiNamespace is set`() = runBlocking {
        val capturedURLs = mutableListOf<String>()
        val capturingClient = createCapturingClient { capturedURLs.add(it) }

        val configuration = EditorConfiguration.builder(
            TEST_SITE_URL,
            "https://public-api.wordpress.com/wp-json",
            "post"
        )
            .setSiteApiNamespace(arrayOf("sites/123/"))
            .setPlugins(true)
            .setThemeStyles(true)
            .setAuthHeader("Bearer test")
            .build()

        val cache = EditorURLCache(cacheRoot, EditorCachePolicy.Always)
        val repository = RESTAPIRepository(configuration, capturingClient, cache)

        repository.fetchPost(id = 1)
        repository.fetchPostType("post")
        repository.fetchActiveTheme()
        repository.fetchPostTypes()

        val expectedURLs = setOf(
            "https://public-api.wordpress.com/wp-json/wp/v2/sites/123/posts/1?context=edit",
            "https://public-api.wordpress.com/wp-json/wp/v2/sites/123/types/post?context=edit",
            "https://public-api.wordpress.com/wp-json/wp/v2/sites/123/themes?context=edit&status=active",
            "https://public-api.wordpress.com/wp-json/wp/v2/sites/123/types?context=view"
        )

        assertEquals(expectedURLs, capturedURLs.toSet())
    }

    @Test
    fun `URLs include namespace without trailing slash`() = runBlocking {
        val capturedURLs = mutableListOf<String>()
        val capturingClient = createCapturingClient { capturedURLs.add(it) }

        val configuration = EditorConfiguration.builder(
            TEST_SITE_URL,
            "https://public-api.wordpress.com/wp-json",
            "post"
        )
            .setSiteApiNamespace(arrayOf("sites/123"))  // No trailing slash
            .setPlugins(true)
            .setThemeStyles(true)
            .setAuthHeader("Bearer test")
            .build()

        val cache = EditorURLCache(cacheRoot, EditorCachePolicy.Always)
        val repository = RESTAPIRepository(configuration, capturingClient, cache)

        repository.fetchPost(id = 1)
        repository.fetchPostType("post")
        repository.fetchActiveTheme()
        repository.fetchPostTypes()

        val expectedURLs = setOf(
            "https://public-api.wordpress.com/wp-json/wp/v2/sites/123/posts/1?context=edit",
            "https://public-api.wordpress.com/wp-json/wp/v2/sites/123/types/post?context=edit",
            "https://public-api.wordpress.com/wp-json/wp/v2/sites/123/themes?context=edit&status=active",
            "https://public-api.wordpress.com/wp-json/wp/v2/sites/123/types?context=view"
        )

        assertEquals(expectedURLs, capturedURLs.toSet())
    }

    @Test
    fun `editor settings URL includes namespace`() = runBlocking {
        val capturedURLs = mutableListOf<String>()
        val capturingClient = createCapturingClient { capturedURLs.add(it) }

        val configuration = EditorConfiguration.builder(
            TEST_SITE_URL,
            "https://public-api.wordpress.com/wp-json",
            "post"
        )
            .setSiteApiNamespace(arrayOf("sites/456/"))
            .setPlugins(true)
            .setThemeStyles(true)
            .setAuthHeader("Bearer test")
            .setEditorSettings(null)
            .build()

        val cache = EditorURLCache(cacheRoot, EditorCachePolicy.Always)
        val repository = RESTAPIRepository(configuration, capturingClient, cache)

        repository.fetchEditorSettings()

        assertEquals(1, capturedURLs.size)
        assertEquals(
            "https://public-api.wordpress.com/wp-json/wp-block-editor/v1/sites/456/settings",
            capturedURLs.first()
        )
    }

    @Test
    fun `settings options URL includes namespace`() = runBlocking {
        val capturedURLs = mutableListOf<String>()
        val capturingClient = createCapturingClient { capturedURLs.add(it) }

        val configuration = EditorConfiguration.builder(
            TEST_SITE_URL,
            "https://public-api.wordpress.com/wp-json",
            "post"
        )
            .setSiteApiNamespace(arrayOf("sites/789/"))
            .setPlugins(true)
            .setThemeStyles(true)
            .setAuthHeader("Bearer test")
            .build()

        val cache = EditorURLCache(cacheRoot, EditorCachePolicy.Always)
        val repository = RESTAPIRepository(configuration, capturingClient, cache)

        repository.fetchSettingsOptions()

        assertEquals(1, capturedURLs.size)
        assertEquals(
            "https://public-api.wordpress.com/wp-json/wp/v2/sites/789/settings",
            capturedURLs.first()
        )
    }

    private fun createCapturingClient(onRequest: (String) -> Unit): EditorHTTPClientProtocol {
        return object : EditorHTTPClientProtocol {
            override suspend fun download(url: String, destination: File): EditorHTTPClientDownloadResponse {
                throw NotImplementedError()
            }

            override suspend fun perform(method: EditorHttpMethod, url: String): EditorHTTPClientResponse {
                onRequest(url)
                return EditorHTTPClientResponse(
                    data = "{}".toByteArray(),
                    statusCode = 200,
                    headers = EditorHTTPHeaders()
                )
            }
        }
    }

    @Test
    fun `post URL includes context=edit query parameter`() = runBlocking {
        var capturedURL: String? = null
        val capturingClient = object : EditorHTTPClientProtocol {
            override suspend fun download(url: String, destination: File): EditorHTTPClientDownloadResponse {
                throw NotImplementedError()
            }

            override suspend fun perform(method: EditorHttpMethod, url: String): EditorHTTPClientResponse {
                capturedURL = url
                return EditorHTTPClientResponse(
                    data = "{}".toByteArray(),
                    statusCode = 200,
                    headers = EditorHTTPHeaders()
                )
            }
        }

        val configuration = makeConfiguration()
        val cache = EditorURLCache(cacheRoot, EditorCachePolicy.Always)
        val repository = RESTAPIRepository(
            configuration = configuration,
            httpClient = capturingClient,
            cache = cache
        )

        repository.fetchPost(id = 42)

        assertTrue(capturedURL?.contains("context=edit") == true)
        assertTrue(capturedURL?.contains("/posts/42") == true)
    }
}

// MARK: - Mock HTTP Client

/**
 * A mock HTTP client for testing that returns configurable responses.
 */
class MockHTTPClient : EditorHTTPClientProtocol {
    var getResponse: String = "{}"
    var optionsResponse: String = "{}"
    var getCallCount: Int = 0
        private set

    override suspend fun download(url: String, destination: File): EditorHTTPClientDownloadResponse {
        destination.parentFile?.mkdirs()
        destination.writeText(getResponse)
        return EditorHTTPClientDownloadResponse(
            file = destination,
            statusCode = 200,
            headers = EditorHTTPHeaders()
        )
    }

    override suspend fun perform(method: EditorHttpMethod, url: String): EditorHTTPClientResponse {
        if (method == EditorHttpMethod.GET) {
            getCallCount++
        }

        val responseData = when (method) {
            EditorHttpMethod.OPTIONS -> optionsResponse
            else -> getResponse
        }

        return EditorHTTPClientResponse(
            data = responseData.toByteArray(),
            statusCode = 200,
            headers = EditorHTTPHeaders()
        )
    }
}
