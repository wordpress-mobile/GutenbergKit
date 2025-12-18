package org.wordpress.gutenberg.model

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.wordpress.gutenberg.model.http.EditorHTTPHeaders
import org.wordpress.gutenberg.model.http.EditorURLResponse

class GBKitGlobalTest {

    companion object {
        private const val TEST_SITE_URL = "https://example.com"
        private const val TEST_API_ROOT = "https://example.com/wp-json"
    }

    // MARK: - Test Helpers

    private fun makeDependencies(): EditorDependencies {
        return EditorDependencies(
            editorSettings = EditorSettings.undefined,
            assetBundle = EditorAssetBundle.empty,
            preloadList = makePreloadList()
        )
    }

    private fun makePreloadList(): EditorPreloadList {
        return EditorPreloadList(
            postType = "post",
            postTypeData = EditorURLResponse(data = "{}", responseHeaders = EditorHTTPHeaders()),
            postTypesData = EditorURLResponse(data = "{}", responseHeaders = EditorHTTPHeaders()),
            activeThemeData = EditorURLResponse(data = "{}", responseHeaders = EditorHTTPHeaders()),
            settingsOptionsData = EditorURLResponse(data = "{}", responseHeaders = EditorHTTPHeaders())
        )
    }

    private fun makeConfiguration(
        postId: Int? = null,
        title: String? = null,
        content: String? = null,
        siteURL: String = TEST_SITE_URL,
        postType: String = "post",
        shouldUsePlugins: Boolean = true,
        shouldUseThemeStyles: Boolean = true
    ): EditorConfiguration {
        return EditorConfiguration.builder(siteURL, TEST_API_ROOT, postType)
            .setPostId(postId)
            .setTitle(title ?: "")
            .setContent(content ?: "")
            .setPlugins(shouldUsePlugins)
            .setThemeStyles(shouldUseThemeStyles)
            .setAuthHeader("Bearer test-token")
            .build()
    }

    // MARK: - Initialization

    @Test
    fun `initializes with configuration and dependencies`() {
        val configuration = makeConfiguration()
        val dependencies = makeDependencies()
        val global = GBKitGlobal.fromConfiguration(configuration, dependencies)
        assertEquals(TEST_SITE_URL, global.siteURL)
    }

    // MARK: - Property Mapping

    @Test
    fun `maps siteURL from configuration`() {
        val siteURL = "https://my-wordpress-site.com"
        val configuration = makeConfiguration(siteURL = siteURL)
        val global = GBKitGlobal.fromConfiguration(configuration, makeDependencies())
        assertEquals(siteURL, global.siteURL)
    }

    @Test
    fun `maps siteApiRoot from configuration`() {
        val configuration = makeConfiguration()
        val global = GBKitGlobal.fromConfiguration(configuration, makeDependencies())
        assertEquals(TEST_API_ROOT, global.siteApiRoot)
    }

    @Test
    fun `maps themeStyles from configuration`() {
        val withThemeStyles = makeConfiguration(shouldUseThemeStyles = true)
        val withoutThemeStyles = makeConfiguration(shouldUseThemeStyles = false)

        val globalWith = GBKitGlobal.fromConfiguration(withThemeStyles, makeDependencies())
        val globalWithout = GBKitGlobal.fromConfiguration(withoutThemeStyles, makeDependencies())

        assertTrue(globalWith.themeStyles)
        assertFalse(globalWithout.themeStyles)
    }

    @Test
    fun `maps plugins from configuration`() {
        val withPlugins = makeConfiguration(shouldUsePlugins = true)
        val withoutPlugins = makeConfiguration(shouldUsePlugins = false)

        val globalWith = GBKitGlobal.fromConfiguration(withPlugins, makeDependencies())
        val globalWithout = GBKitGlobal.fromConfiguration(withoutPlugins, makeDependencies())

        assertTrue(globalWith.plugins)
        assertFalse(globalWithout.plugins)
    }

    @Test
    fun `maps postID to post id`() {
        val withPostID = makeConfiguration(postId = 42)
        val withoutPostID = makeConfiguration(postId = null)

        val globalWith = GBKitGlobal.fromConfiguration(withPostID, makeDependencies())
        val globalWithout = GBKitGlobal.fromConfiguration(withoutPostID, makeDependencies())

        assertEquals(42, globalWith.post.id)
        assertEquals(-1, globalWithout.post.id)
    }

    @Test
    fun `maps title with percent encoding`() {
        val configuration = makeConfiguration(title = "Hello World")
        val global = GBKitGlobal.fromConfiguration(configuration, makeDependencies())
        assertEquals("Hello%20World", global.post.title)
    }

    @Test
    fun `maps content with percent encoding`() {
        val configuration = makeConfiguration(
            content = "<!-- wp:paragraph --><p>Test</p><!-- /wp:paragraph -->"
        )
        val global = GBKitGlobal.fromConfiguration(configuration, makeDependencies())
        assertTrue(global.post.content.contains("%"))
        assertFalse(global.post.content.contains("<"))
    }

    // MARK: - toJsonString()

    @Test
    fun `toJsonString produces valid JSON`() {
        val configuration = makeConfiguration()
        val global = GBKitGlobal.fromConfiguration(configuration, makeDependencies())

        val jsonString = global.toJsonString()
        val decoded = Json.parseToJsonElement(jsonString)

        assertTrue(decoded.toString().isNotEmpty())
    }

    @Test
    fun `toJsonString includes all required fields`() {
        val configuration = makeConfiguration(postId = 123, title = "Test", content = "Content")
        val global = GBKitGlobal.fromConfiguration(configuration, makeDependencies())

        val jsonString = global.toJsonString()

        assertTrue(jsonString.contains("siteURL"))
        assertTrue(jsonString.contains("siteApiRoot"))
        assertTrue(jsonString.contains("themeStyles"))
        assertTrue(jsonString.contains("plugins"))
        assertTrue(jsonString.contains("post"))
        assertTrue(jsonString.contains("locale"))
        assertTrue(jsonString.contains("logLevel"))
    }

    @Test
    fun `toJsonString round-trips through serialization`() {
        val configuration = makeConfiguration(postId = 99, title = "Round Trip", content = "Test content")
        val original = GBKitGlobal.fromConfiguration(configuration, makeDependencies())

        val jsonString = original.toJsonString()
        val decoded = Json.decodeFromString<GBKitGlobal>(jsonString)

        assertEquals(original.siteURL, decoded.siteURL)
        assertEquals(original.post.id, decoded.post.id)
        assertEquals(original.post.title, decoded.post.title)
        assertEquals(original.themeStyles, decoded.themeStyles)
        assertEquals(original.plugins, decoded.plugins)
    }

    // MARK: - Special Characters

    @Test
    fun `handles unicode in title`() {
        val configuration = makeConfiguration(title = "日本語タイトル")
        val global = GBKitGlobal.fromConfiguration(configuration, makeDependencies())

        val jsonString = global.toJsonString()
        assertTrue(jsonString.isNotEmpty())

        val decoded = Json.decodeFromString<GBKitGlobal>(jsonString)
        assertEquals(global.post.title, decoded.post.title)
    }

    @Test
    fun `handles emoji in content`() {
        val configuration = makeConfiguration(content = "Hello 👋 World 🌍")
        val global = GBKitGlobal.fromConfiguration(configuration, makeDependencies())

        val jsonString = global.toJsonString()
        assertTrue(jsonString.isNotEmpty())

        val decoded = Json.decodeFromString<GBKitGlobal>(jsonString)
        assertEquals(global.post.content, decoded.post.content)
    }

    @Test
    fun `handles special HTML characters in content`() {
        val configuration = makeConfiguration(content = "<script>alert('xss')</script>")
        val global = GBKitGlobal.fromConfiguration(configuration, makeDependencies())

        val jsonString = global.toJsonString()
        // Should be percent-encoded, not raw HTML
        assertFalse(jsonString.contains("<script>"))
    }

    // MARK: - Edge Cases

    @Test
    fun `handles empty title and content`() {
        val configuration = makeConfiguration(title = "", content = "")
        val global = GBKitGlobal.fromConfiguration(configuration, makeDependencies())

        val jsonString = global.toJsonString()
        assertTrue(jsonString.isNotEmpty())

        val decoded = Json.decodeFromString<GBKitGlobal>(jsonString)
        assertEquals("", decoded.post.title)
        assertEquals("", decoded.post.content)
    }

    @Test
    fun `handles very long content`() {
        val longContent = "Lorem ipsum dolor sit amet. ".repeat(1000)
        val configuration = makeConfiguration(content = longContent)
        val global = GBKitGlobal.fromConfiguration(configuration, makeDependencies())

        val jsonString = global.toJsonString()
        assertTrue(jsonString.isNotEmpty())

        val decoded = Json.decodeFromString<GBKitGlobal>(jsonString)
        assertTrue(decoded.post.content.isNotEmpty())
    }

    @Test
    fun `produces valid JavaScript object`() {
        val configuration = makeConfiguration(title = "Test", content = "Hello")
        val global = GBKitGlobal.fromConfiguration(configuration, makeDependencies())

        val jsonString = global.toJsonString()
        // Verify it can be parsed as JSON (which is valid JS)
        val parsed = Json.parseToJsonElement(jsonString)
        assertTrue(parsed.toString().isNotEmpty())
    }
}
