package org.wordpress.gutenberg.model

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EditorConfigurationBuilderTest {

    // MARK: - Test Fixtures

    companion object {
        const val TEST_SITE_URL = "https://example.com"
        const val TEST_API_ROOT = "https://example.com/wp-json"
        val TEST_POST_TYPE = PostTypeDetails.post
    }

    private fun builder() = EditorConfiguration.builder(TEST_SITE_URL, TEST_API_ROOT, TEST_POST_TYPE)

    // MARK: - Default Values Tests

    @Test
    fun `Builder uses correct default values`() {
        val config = builder().build()

        assertEquals("", config.title)
        assertEquals("", config.content)
        assertNull(config.postId)
        assertEquals(TEST_POST_TYPE, config.postType)
        assertEquals("draft", config.postStatus)
        assertFalse(config.themeStyles)
        assertFalse(config.plugins)
        assertFalse(config.hideTitle)
        assertEquals(TEST_SITE_URL, config.siteURL)
        assertEquals(TEST_API_ROOT, config.siteApiRoot)
        assertArrayEquals(arrayOf<String>(), config.siteApiNamespace)
        assertArrayEquals(arrayOf<String>(), config.namespaceExcludedPaths)
        assertEquals("", config.authHeader)
        assertNull(config.editorSettings)
        assertEquals("en", config.locale)
        assertEquals(emptyMap<String, String>(), config.cookies)
        assertFalse(config.enableAssetCaching)
        assertEquals(emptySet<String>(), config.cachedAssetHosts)
        assertNull(config.editorAssetsEndpoint)
        assertFalse(config.enableNetworkLogging)
        assertFalse(config.enableOfflineMode)
        assertEquals(UserCapabilities(), config.userCapabilities)
        assertFalse(config.userCapabilities.uploadFiles)
    }

    @Test
    fun `setUserCapabilities updates userCapabilities`() {
        val config = builder()
            .setUserCapabilities(UserCapabilities(uploadFiles = true))
            .build()

        assertTrue(config.userCapabilities.uploadFiles)
    }

    // MARK: - Individual Setter Tests

    @Test
    fun `setTitle updates title`() {
        val config = builder()
            .setTitle("My Post Title")
            .build()

        assertEquals("My Post Title", config.title)
    }

    @Test
    fun `setContent updates content`() {
        val config = builder()
            .setContent("<p>Hello world</p>")
            .build()

        assertEquals("<p>Hello world</p>", config.content)
    }

    @Test
    fun `setPostId updates postId`() {
        val config = builder()
            .setPostId(123u)
            .build()

        assertEquals(123u, config.postId)
    }

    @Test
    fun `setPostId with zero results in null`() {
        val config = builder()
            .setPostId(0u)
            .build()

        assertNull(config.postId)
    }

    @Test
    fun `setPostId with null clears postId`() {
        val config = builder()
            .setPostId(123u)
            .setPostId(null)
            .build()

        assertNull(config.postId)
    }

    @Test
    fun `setPostType updates postType`() {
        val config = builder()
            .setPostType(PostTypeDetails.page)
            .build()

        assertEquals(PostTypeDetails.page, config.postType)
    }

    @Test
    fun `setPostStatus updates postStatus`() {
        val config = builder()
            .setPostStatus("publish")
            .build()

        assertEquals("publish", config.postStatus)
    }

    @Test
    fun `setThemeStyles updates themeStyles`() {
        val config = builder()
            .setThemeStyles(true)
            .build()

        assertTrue(config.themeStyles)
    }

    @Test
    fun `setPlugins updates plugins`() {
        val config = builder()
            .setPlugins(true)
            .build()

        assertTrue(config.plugins)
    }

    @Test
    fun `setHideTitle updates hideTitle`() {
        val config = builder()
            .setHideTitle(true)
            .build()

        assertTrue(config.hideTitle)
    }

    @Test
    fun `setSiteURL updates siteURL`() {
        val newURL = "https://other.com"
        val config = builder()
            .setSiteURL(newURL)
            .build()

        assertEquals(newURL, config.siteURL)
    }

    @Test
    fun `setSiteApiRoot updates siteApiRoot`() {
        val newURL = "https://other.com/wp-json/v2"
        val config = builder()
            .setSiteApiRoot(newURL)
            .build()

        assertEquals(newURL, config.siteApiRoot)
    }

    @Test
    fun `setSiteApiNamespace updates siteApiNamespace`() {
        val namespaces = arrayOf("wp/v2", "wp/v3")
        val config = builder()
            .setSiteApiNamespace(namespaces)
            .build()

        assertArrayEquals(namespaces, config.siteApiNamespace)
    }

    @Test
    fun `setNamespaceExcludedPaths updates namespaceExcludedPaths`() {
        val paths = arrayOf("/oembed", "/batch")
        val config = builder()
            .setNamespaceExcludedPaths(paths)
            .build()

        assertArrayEquals(paths, config.namespaceExcludedPaths)
    }

    @Test
    fun `setAuthHeader updates authHeader`() {
        val config = builder()
            .setAuthHeader("Bearer token123")
            .build()

        assertEquals("Bearer token123", config.authHeader)
    }

    @Test
    fun `setEditorSettings updates editorSettings`() {
        val settings = """{"colors":[]}"""
        val config = builder()
            .setEditorSettings(settings)
            .build()

        assertEquals(settings, config.editorSettings)
    }

    @Test
    fun `setLocale updates locale`() {
        val config = builder()
            .setLocale("fr_FR")
            .build()

        assertEquals("fr_FR", config.locale)
    }

    @Test
    fun `setCookies updates cookies`() {
        val cookies = mapOf("session" to "abc123")
        val config = builder()
            .setCookies(cookies)
            .build()

        assertEquals(cookies, config.cookies)
    }

    @Test
    fun `setEnableAssetCaching updates enableAssetCaching`() {
        val config = builder()
            .setEnableAssetCaching(true)
            .build()

        assertTrue(config.enableAssetCaching)
    }

    @Test
    fun `setCachedAssetHosts updates cachedAssetHosts`() {
        val hosts = setOf("example.com", "cdn.example.com")
        val config = builder()
            .setCachedAssetHosts(hosts)
            .build()

        assertEquals(hosts, config.cachedAssetHosts)
    }

    @Test
    fun `setEditorAssetsEndpoint updates editorAssetsEndpoint`() {
        val endpoint = "https://example.com/assets"
        val config = builder()
            .setEditorAssetsEndpoint(endpoint)
            .build()

        assertEquals(endpoint, config.editorAssetsEndpoint)
    }

    @Test
    fun `setEnableNetworkLogging updates enableNetworkLogging`() {
        val config = builder()
            .setEnableNetworkLogging(true)
            .build()

        assertTrue(config.enableNetworkLogging)
    }

    @Test
    fun `setEnableOfflineMode updates enableOfflineMode`() {
        val config = builder()
            .setEnableOfflineMode(true)
            .build()

        assertTrue(config.enableOfflineMode)
    }

    // MARK: - Method Chaining Tests

    @Test
    fun `Builder supports method chaining`() {
        val config = builder()
            .setTitle("Chained Title")
            .setContent("<p>Chained content</p>")
            .setPostId(456u)
            .setPlugins(true)
            .setThemeStyles(true)
            .setLocale("de_DE")
            .setEnableNetworkLogging(true)
            .build()

        assertEquals("Chained Title", config.title)
        assertEquals("<p>Chained content</p>", config.content)
        assertEquals(456u, config.postId)
        assertTrue(config.plugins)
        assertTrue(config.themeStyles)
        assertEquals("de_DE", config.locale)
        assertTrue(config.enableNetworkLogging)
    }

    // MARK: - Multiple Builds Tests

    @Test
    fun `Multiple builds from same builder produce equal configs`() {
        val builder = builder().setTitle("Test")

        val config1 = builder.build()
        val config2 = builder.build()

        assertEquals(config1, config2)
    }

    // MARK: - toBuilder Tests

    @Test
    fun `toBuilder preserves all configuration values`() {
        val original = builder()
            .setTitle("Round Trip Title")
            .setContent("<p>Round trip content</p>")
            .setPostId(999u)
            .setPostType(PostTypeDetails.page)
            .setPostStatus("draft")
            .setThemeStyles(true)
            .setPlugins(true)
            .setHideTitle(true)
            .setSiteURL(TEST_SITE_URL)
            .setSiteApiRoot(TEST_API_ROOT)
            .setSiteApiNamespace(arrayOf("wp/v2", "custom/v1"))
            .setNamespaceExcludedPaths(arrayOf("/excluded"))
            .setAuthHeader("Bearer roundtrip")
            .setEditorSettings("""{"roundtrip":true}""")
            .setLocale("es_ES")
            .setCookies(mapOf("roundtrip" to "cookie"))
            .setEnableAssetCaching(true)
            .setCachedAssetHosts(setOf("cdn.example.com"))
            .setEditorAssetsEndpoint("https://example.com/roundtrip-assets")
            .setEnableNetworkLogging(true)
            .setEnableOfflineMode(true)
            .build()

        val rebuilt = original.toBuilder().build()

        assertEquals(original, rebuilt)
    }

    @Test
    fun `toBuilder allows modification of existing config`() {
        val original = builder()
            .setTitle("Original Title")
            .setPostId(100u)
            .build()

        val modified = original.toBuilder()
            .setTitle("Modified Title")
            .build()

        assertEquals("Original Title", original.title)
        assertEquals("Modified Title", modified.title)
        assertEquals(100u, modified.postId)
    }

    @Test
    fun `toBuilder preserves array values`() {
        val namespaces = arrayOf("wp/v2", "wp/v3")
        val excludedPaths = arrayOf("/oembed", "/batch")

        val original = builder()
            .setSiteApiNamespace(namespaces)
            .setNamespaceExcludedPaths(excludedPaths)
            .build()

        val rebuilt = original.toBuilder().build()

        assertArrayEquals(namespaces, rebuilt.siteApiNamespace)
        assertArrayEquals(excludedPaths, rebuilt.namespaceExcludedPaths)
    }

    @Test
    fun `toBuilder preserves collection values`() {
        val cookies = mapOf("session" to "abc", "token" to "xyz")
        val cachedHosts = setOf("cdn1.example.com", "cdn2.example.com")

        val original = builder()
            .setCookies(cookies)
            .setCachedAssetHosts(cachedHosts)
            .build()

        val rebuilt = original.toBuilder().build()

        assertEquals(cookies, rebuilt.cookies)
        assertEquals(cachedHosts, rebuilt.cachedAssetHosts)
    }

    @Test
    fun `toBuilder preserves nullable values when set`() {
        val original = builder()
            .setPostId(123u)
            .setPostType(PostTypeDetails.post)
            .setPostStatus("publish")
            .setEditorSettings("""{"test":true}""")
            .setEditorAssetsEndpoint("https://example.com/assets")
            .build()

        val rebuilt = original.toBuilder().build()

        assertEquals(123u, rebuilt.postId)
        assertEquals(PostTypeDetails.post, rebuilt.postType)
        assertEquals("publish", rebuilt.postStatus)
        assertEquals("""{"test":true}""", rebuilt.editorSettings)
        assertEquals("https://example.com/assets", rebuilt.editorAssetsEndpoint)
    }

    @Test
    fun `toBuilder preserves nullable values when null`() {
        val original = builder()
            .setPostId(null)
            .setEditorSettings(null)
            .setEditorAssetsEndpoint(null)
            .build()

        val rebuilt = original.toBuilder().build()

        assertNull(rebuilt.postId)
        assertNull(rebuilt.editorSettings)
        assertNull(rebuilt.editorAssetsEndpoint)
    }

    // MARK: - siteId Tests

    @Test
    fun `siteId extracts host from siteURL`() {
        val config = EditorConfiguration.builder("https://example.com/blog", TEST_API_ROOT)
            .build()

        assertEquals("example.com", config.siteId)
    }

    @Test
    fun `siteId extracts host from siteURL with port`() {
        val config = EditorConfiguration.builder("https://example.com:8080/blog", TEST_API_ROOT)
            .build()

        assertEquals("example.com", config.siteId)
    }

    @Test
    fun `siteId extracts subdomain from siteURL`() {
        val config = EditorConfiguration.builder("https://blog.example.com/posts", TEST_API_ROOT)
            .build()

        assertEquals("blog.example.com", config.siteId)
    }

    @Test
    fun `siteId returns UUID for empty siteURL`() {
        val config = EditorConfiguration.builder("", TEST_API_ROOT)
            .build()

        // Should be a valid UUID format (36 characters with hyphens)
        assertTrue(config.siteId.matches(Regex("[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}")))
    }

    @Test
    fun `siteId returns UUID for invalid URL`() {
        val config = EditorConfiguration.builder("not a valid url", TEST_API_ROOT)
            .build()

        // Should be a valid UUID format
        assertTrue(config.siteId.matches(Regex("[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}")))
    }

    @Test
    fun `siteId is consistent for same URL`() {
        val config = builder().build()

        val siteId1 = config.siteId
        val siteId2 = config.siteId

        assertEquals(siteId1, siteId2)
    }

    // MARK: - bundled() Tests

    @Test
    fun `bundled returns configuration with offline mode enabled`() {
        val config = EditorConfiguration.bundled()

        assertTrue(config.enableOfflineMode)
        assertEquals("https://example.com", config.siteURL)
        assertEquals("https://example.com/wp-json/", config.siteApiRoot)
        assertEquals(PostTypeDetails.post, config.postType)
    }
}

class EditorConfigurationTest {

    companion object {
        const val TEST_SITE_URL = "https://example.com"
        const val TEST_API_ROOT = "https://example.com/wp-json"
        val TEST_POST_TYPE = PostTypeDetails.post
    }

    private fun builder() = EditorConfiguration.builder(TEST_SITE_URL, TEST_API_ROOT, TEST_POST_TYPE)

    // MARK: - Equatable Tests
    // Tests are ordered to match property declaration order in EditorConfiguration

    @Test
    fun `Configurations with same values are equal`() {
        val config1 = builder()
            .setTitle("Test")
            .setContent("<p>Content</p>")
            .build()

        val config2 = builder()
            .setTitle("Test")
            .setContent("<p>Content</p>")
            .build()

        assertEquals(config1, config2)
    }

    @Test
    fun `Configurations with different title are not equal`() {
        val config1 = builder()
            .setTitle("Title 1")
            .build()

        val config2 = builder()
            .setTitle("Title 2")
            .build()

        assertNotEquals(config1, config2)
    }

    @Test
    fun `Configurations with different content are not equal`() {
        val config1 = builder()
            .setContent("Content 1")
            .build()

        val config2 = builder()
            .setContent("Content 2")
            .build()

        assertNotEquals(config1, config2)
    }

    @Test
    fun `Configurations with different postId are not equal`() {
        val config1 = builder()
            .setPostId(1u)
            .build()

        val config2 = builder()
            .setPostId(2u)
            .build()

        assertNotEquals(config1, config2)
    }

    @Test
    fun `Configurations with different postType are not equal`() {
        val config1 = EditorConfiguration.builder(TEST_SITE_URL, TEST_API_ROOT, PostTypeDetails.post)
            .build()

        val config2 = EditorConfiguration.builder(TEST_SITE_URL, TEST_API_ROOT, PostTypeDetails.page)
            .build()

        assertNotEquals(config1, config2)
    }

    @Test
    fun `Configurations with different postStatus are not equal`() {
        val config1 = builder()
            .setPostStatus("draft")
            .build()

        val config2 = builder()
            .setPostStatus("publish")
            .build()

        assertNotEquals(config1, config2)
    }

    @Test
    fun `Configurations with different themeStyles are not equal`() {
        val config1 = builder()
            .setThemeStyles(true)
            .build()

        val config2 = builder()
            .setThemeStyles(false)
            .build()

        assertNotEquals(config1, config2)
    }

    @Test
    fun `Configurations with different plugins are not equal`() {
        val config1 = builder()
            .setPlugins(true)
            .build()

        val config2 = builder()
            .setPlugins(false)
            .build()

        assertNotEquals(config1, config2)
    }

    @Test
    fun `Configurations with different hideTitle are not equal`() {
        val config1 = builder()
            .setHideTitle(true)
            .build()

        val config2 = builder()
            .setHideTitle(false)
            .build()

        assertNotEquals(config1, config2)
    }

    @Test
    fun `Configurations with different siteURL are not equal`() {
        val config1 = EditorConfiguration.builder("https://site1.com", TEST_API_ROOT)
            .build()

        val config2 = EditorConfiguration.builder("https://site2.com", TEST_API_ROOT)
            .build()

        assertNotEquals(config1, config2)
    }

    @Test
    fun `Configurations with different siteApiRoot are not equal`() {
        val config1 = EditorConfiguration.builder(TEST_SITE_URL, "https://example.com/wp-json/v1")
            .build()

        val config2 = EditorConfiguration.builder(TEST_SITE_URL, "https://example.com/wp-json/v2")
            .build()

        assertNotEquals(config1, config2)
    }

    @Test
    fun `Configurations with different siteApiNamespace are not equal`() {
        val config1 = builder()
            .setSiteApiNamespace(arrayOf("wp/v2"))
            .build()

        val config2 = builder()
            .setSiteApiNamespace(arrayOf("wp/v3"))
            .build()

        assertNotEquals(config1, config2)
    }

    @Test
    fun `Configurations with different namespaceExcludedPaths are not equal`() {
        val config1 = builder()
            .setNamespaceExcludedPaths(arrayOf("/oembed"))
            .build()

        val config2 = builder()
            .setNamespaceExcludedPaths(arrayOf("/batch"))
            .build()

        assertNotEquals(config1, config2)
    }

    @Test
    fun `Configurations with different authHeader are not equal`() {
        val config1 = builder()
            .setAuthHeader("Bearer token1")
            .build()

        val config2 = builder()
            .setAuthHeader("Bearer token2")
            .build()

        assertNotEquals(config1, config2)
    }

    @Test
    fun `Configurations with different editorSettings are not equal`() {
        val config1 = builder()
            .setEditorSettings("""{"theme":"light"}""")
            .build()

        val config2 = builder()
            .setEditorSettings("""{"theme":"dark"}""")
            .build()

        assertNotEquals(config1, config2)
    }

    @Test
    fun `Configurations with different locale are not equal`() {
        val config1 = builder()
            .setLocale("en_US")
            .build()

        val config2 = builder()
            .setLocale("fr_FR")
            .build()

        assertNotEquals(config1, config2)
    }

    @Test
    fun `Configurations with different cookies are not equal`() {
        val config1 = builder()
            .setCookies(mapOf("session" to "abc"))
            .build()

        val config2 = builder()
            .setCookies(mapOf("session" to "xyz"))
            .build()

        assertNotEquals(config1, config2)
    }

    @Test
    fun `Configurations with different enableAssetCaching are not equal`() {
        val config1 = builder()
            .setEnableAssetCaching(true)
            .build()

        val config2 = builder()
            .setEnableAssetCaching(false)
            .build()

        assertNotEquals(config1, config2)
    }

    @Test
    fun `Configurations with different cachedAssetHosts are not equal`() {
        val config1 = builder()
            .setCachedAssetHosts(setOf("cdn1.example.com"))
            .build()

        val config2 = builder()
            .setCachedAssetHosts(setOf("cdn2.example.com"))
            .build()

        assertNotEquals(config1, config2)
    }

    @Test
    fun `Configurations with different editorAssetsEndpoint are not equal`() {
        val config1 = builder()
            .setEditorAssetsEndpoint("https://example.com/assets1")
            .build()

        val config2 = builder()
            .setEditorAssetsEndpoint("https://example.com/assets2")
            .build()

        assertNotEquals(config1, config2)
    }

    @Test
    fun `Configurations with different enableNetworkLogging are not equal`() {
        val config1 = builder()
            .setEnableNetworkLogging(true)
            .build()

        val config2 = builder()
            .setEnableNetworkLogging(false)
            .build()

        assertNotEquals(config1, config2)
    }

    @Test
    fun `Configurations with different enableOfflineMode are not equal`() {
        val config1 = builder()
            .setEnableOfflineMode(true)
            .build()

        val config2 = builder()
            .setEnableOfflineMode(false)
            .build()

        assertNotEquals(config1, config2)
    }

    @Test
    fun `Configurations with different siteId are not equal`() {
        // siteId is derived from siteURL, so different URLs with different hosts produce different siteIds
        val config1 = EditorConfiguration.builder("https://site1.example.com", TEST_API_ROOT)
            .build()

        val config2 = EditorConfiguration.builder("https://site2.example.com", TEST_API_ROOT)
            .build()

        assertNotEquals(config1.siteId, config2.siteId)
        assertNotEquals(config1, config2)
    }

    // MARK: - Hashable Tests

    @Test
    fun `Identical configurations have same hash`() {
        val config1 = builder()
            .setTitle("Test")
            .setContent("Content")
            .build()

        val config2 = builder()
            .setTitle("Test")
            .setContent("Content")
            .build()

        assertEquals(config1.hashCode(), config2.hashCode())
    }

    @Test
    fun `Configurations can be used in Set`() {
        val config1 = builder()
            .setPostId(1u)
            .build()

        val config2 = builder()
            .setPostId(2u)
            .build()

        val config3 = builder()
            .setPostId(1u)
            .build()

        val set = setOf(config1, config2, config3)

        assertEquals(2, set.size)
    }

    @Test
    fun `Configuration can be used as map key`() {
        val config1 = builder()
            .setTitle("Key 1")
            .build()

        val config2 = builder()
            .setTitle("Key 2")
            .build()

        val map = mutableMapOf<EditorConfiguration, String>()
        map[config1] = "Value 1"
        map[config2] = "Value 2"

        assertEquals("Value 1", map[config1])
        assertEquals("Value 2", map[config2])
    }

    // MARK: - Full Configuration Test

    @Test
    fun `test EditorConfiguration builder sets all properties correctly`() {
        val config = EditorConfiguration.builder("https://example.com", "https://example.com/wp-json", PostTypeDetails.post)
            .setTitle("Test Title")
            .setContent("Test Content")
            .setPostId(123u)
            .setPostType(PostTypeDetails.post)
            .setPostStatus("publish")
            .setThemeStyles(true)
            .setPlugins(true)
            .setHideTitle(false)
            .setSiteURL("https://example.com")
            .setSiteApiRoot("https://example.com/wp-json")
            .setSiteApiNamespace(arrayOf("wp/v2"))
            .setNamespaceExcludedPaths(arrayOf("users"))
            .setAuthHeader("Bearer token")
            .setEditorSettings("""{"foo":"bar"}""")
            .setLocale("fr")
            .setCookies(mapOf("session" to "abc123"))
            .setEnableAssetCaching(true)
            .setCachedAssetHosts(setOf("example.com", "cdn.example.com"))
            .setEditorAssetsEndpoint("https://example.com/assets")
            .setEnableNetworkLogging(true)
            .setEnableOfflineMode(false)
            .build()

        assertEquals("Test Title", config.title)
        assertEquals("Test Content", config.content)
        assertEquals(123u, config.postId)
        assertEquals(PostTypeDetails.post, config.postType)
        assertEquals("publish", config.postStatus)
        assertTrue(config.themeStyles)
        assertTrue(config.plugins)
        assertFalse(config.hideTitle)
        assertEquals("https://example.com", config.siteURL)
        assertEquals("https://example.com/wp-json", config.siteApiRoot)
        assertArrayEquals(arrayOf("wp/v2"), config.siteApiNamespace)
        assertArrayEquals(arrayOf("users"), config.namespaceExcludedPaths)
        assertEquals("Bearer token", config.authHeader)
        assertEquals("""{"foo":"bar"}""", config.editorSettings)
        assertEquals("fr", config.locale)
        assertEquals(mapOf("session" to "abc123"), config.cookies)
        assertTrue(config.enableAssetCaching)
        assertEquals(setOf("example.com", "cdn.example.com"), config.cachedAssetHosts)
        assertEquals("https://example.com/assets", config.editorAssetsEndpoint)
        assertTrue(config.enableNetworkLogging)
        assertFalse(config.enableOfflineMode)
    }
}
