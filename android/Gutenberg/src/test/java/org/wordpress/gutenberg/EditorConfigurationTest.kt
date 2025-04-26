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
            .setWebViewGlobals(listOf(
                WebViewGlobal("testString", WebViewGlobalValue.StringValue("test")),
                WebViewGlobal("testNumber", WebViewGlobalValue.NumberValue(42.0)),
                WebViewGlobal("testBoolean", WebViewGlobalValue.BooleanValue(true))
            ))
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
        assertEquals(3, editorConfig.webViewGlobals.size)
    }

    @Test
    fun `test WebViewGlobal StringValue toJavaScript conversion`() {
        val stringValue = WebViewGlobalValue.StringValue("test\nvalue")
        assertEquals("\"test\\nvalue\"", stringValue.toJavaScript())
    }

    @Test
    fun `test WebViewGlobal NumberValue toJavaScript conversion`() {
        val numberValue = WebViewGlobalValue.NumberValue(42.0)
        assertEquals("42.0", numberValue.toJavaScript())
    }

    @Test
    fun `test WebViewGlobal BooleanValue toJavaScript conversion`() {
        val booleanValue = WebViewGlobalValue.BooleanValue(true)
        assertEquals("true", booleanValue.toJavaScript())
    }

    @Test
    fun `test WebViewGlobal ObjectValue toJavaScript conversion`() {
        val objectValue = WebViewGlobalValue.ObjectValue(mapOf(
            "key1" to WebViewGlobalValue.StringValue("value1"),
            "key2" to WebViewGlobalValue.NumberValue(42.0)
        ))
        assertEquals("{\"key1\": \"value1\",\"key2\": 42.0}", objectValue.toJavaScript())
    }

    @Test
    fun `test WebViewGlobal ArrayValue toJavaScript conversion`() {
        val arrayValue = WebViewGlobalValue.ArrayValue(listOf(
            WebViewGlobalValue.StringValue("value1"),
            WebViewGlobalValue.NumberValue(42.0)
        ))
        assertEquals("[\"value1\",42.0]", arrayValue.toJavaScript())
    }

    @Test
    fun `test WebViewGlobal NullValue toJavaScript conversion`() {
        val nullValue = WebViewGlobalValue.NullValue
        assertEquals("null", nullValue.toJavaScript())
    }

    @Test
    fun `test WebViewGlobal valid identifier`() {
        val validGlobal = WebViewGlobal("validName", WebViewGlobalValue.StringValue("test"))
        assertEquals("validName", validGlobal.name)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `test WebViewGlobal invalid identifier throws exception`() {
        WebViewGlobal("123invalid", WebViewGlobalValue.StringValue("test"))
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
