package org.wordpress.gutenberg

import org.junit.Test
import org.junit.Assert.*
import org.junit.Before

class EditorConfigurationTest {
    private lateinit var editorConfig: EditorConfiguration

    @Before
    fun setup() {
        editorConfig = EditorConfiguration.builder()
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
            .build()
    }

    @Test
    fun `test EditorConfiguration builder creates correct configuration`() {
        assertEquals("Test Title", editorConfig.title)
        assertEquals("Test Content", editorConfig.content)
        assertEquals(123, editorConfig.postId)
        assertEquals("post", editorConfig.postType)
        assertTrue(editorConfig.themeStyles)
        assertTrue(editorConfig.plugins)
        assertFalse(editorConfig.hideTitle)
        assertEquals("https://example.com", editorConfig.siteURL)
        assertEquals("https://example.com/wp-json", editorConfig.siteApiRoot)
        assertArrayEquals(arrayOf("wp/v2"), editorConfig.siteApiNamespace)
        assertArrayEquals(arrayOf("users"), editorConfig.namespaceExcludedPaths)
        assertEquals("Bearer token", editorConfig.authHeader)
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