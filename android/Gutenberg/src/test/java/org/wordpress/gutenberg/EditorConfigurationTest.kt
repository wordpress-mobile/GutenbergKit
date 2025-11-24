package org.wordpress.gutenberg

import org.junit.Test
import org.junit.Assert.*

class EditorConfigurationTest {

    @Test
    fun `test EditorConfiguration builder sets all properties correctly`() {
        val config = EditorConfiguration.builder()
            .setTitle("Test Title")
            .setContent("Test Content")
            .setPostId(123)
            .setPostType("post")
            .setThemeStyles(true)
            .setPlugins(true)
            .setHideTitle(false)
            .setSiteURL("https://example.com")
            .setSiteApiRoot("https://example.com/wp-json")
            .setSiteApiNamespace(arrayOf("wp/v2"))
            .setNamespaceExcludedPaths(arrayOf("users"))
            .setAuthHeader("Bearer token")
            .setEditorSettings("{\"foo\":\"bar\"}")
            .setLocale("fr")
            .setCookies(mapOf("session" to "abc123"))
            .setEnableAssetCaching(true)
            .setCachedAssetHosts(setOf("example.com", "cdn.example.com"))
            .setEditorAssetsEndpoint("https://example.com/assets")
            .setEnableNetworkLogging(true)
            .build()

        assertEquals("Test Title", config.title)
        assertEquals("Test Content", config.content)
        assertEquals(123, config.postId)
        assertEquals("post", config.postType)
        assertTrue(config.themeStyles)
        assertTrue(config.plugins)
        assertFalse(config.hideTitle)
        assertEquals("https://example.com", config.siteURL)
        assertEquals("https://example.com/wp-json", config.siteApiRoot)
        assertArrayEquals(arrayOf("wp/v2"), config.siteApiNamespace)
        assertArrayEquals(arrayOf("users"), config.namespaceExcludedPaths)
        assertEquals("Bearer token", config.authHeader)
        assertEquals("{\"foo\":\"bar\"}", config.editorSettings)
        assertEquals("fr", config.locale)
        assertEquals(mapOf("session" to "abc123"), config.cookies)
        assertTrue(config.enableAssetCaching)
        assertEquals(setOf("example.com", "cdn.example.com"), config.cachedAssetHosts)
        assertEquals("https://example.com/assets", config.editorAssetsEndpoint)
        assertTrue(config.enableNetworkLogging)
    }

    @Test
    fun `test EditorConfiguration equals and hashCode`() {
        val config1 = EditorConfiguration.builder()
            .setTitle("Test")
            .setContent("Content")
            .build()

        val config2 = EditorConfiguration.builder()
            .setTitle("Test")
            .setContent("Content")
            .build()

        assertEquals(config1, config2)
        assertEquals(config1.hashCode(), config2.hashCode())
    }

    @Test
    fun `test EditorConfiguration not equals`() {
        val config1 = EditorConfiguration.builder()
            .setTitle("Test1")
            .setContent("Content")
            .build()

        val config2 = EditorConfiguration.builder()
            .setTitle("Test2")
            .setContent("Content")
            .build()

        assertNotEquals(config1, config2)
    }
}
