package org.wordpress.gutenberg.model

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class EditorSettingsTest {

    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun `throws when JSON is invalid`() {
        val invalidJSON = "not valid json"

        assertThrows(Exception::class.java, {
            EditorSettings.fromData(invalidJSON)
        })
    }

    // MARK: - themeStyles Tests

    @Test
    fun `themeStyles is empty when styles array is empty`() {
        val jsonString = """{"styles": []}"""
        val settings = EditorSettings.fromData(jsonString)
        assertTrue(settings.themeStyles.isEmpty())
    }

    @Test
    fun `themeStyles extracts single css value`() {
        val jsonString = """{"styles": [{"css": "body { color: red; }", "isGlobalStyles": true}]}"""
        val settings = EditorSettings.fromData(jsonString)
        assertEquals("body { color: red; }", settings.themeStyles)
    }

    @Test
    fun `themeStyles joins multiple css values with newlines`() {
        val jsonString = """{"styles": [{"css": "body { color: red; }", "isGlobalStyles": true}, {"css": "h1 { font-size: 2em; }", "isGlobalStyles": false}]}"""
        val settings = EditorSettings.fromData(jsonString)
        assertEquals("body { color: red; }\nh1 { font-size: 2em; }", settings.themeStyles)
    }

    @Test
    fun `themeStyles skips styles with null css`() {
        val jsonString = """{"styles": [{"css": null, "isGlobalStyles": true}, {"css": "h1 { font-size: 2em; }", "isGlobalStyles": false}]}"""
        val settings = EditorSettings.fromData(jsonString)
        assertEquals("h1 { font-size: 2em; }", settings.themeStyles)
    }

    @Test
    fun `themeStyles skips styles without css key`() {
        val jsonString = """{"styles": [{"isGlobalStyles": true}, {"css": "h1 { font-size: 2em; }", "isGlobalStyles": false}]}"""
        val settings = EditorSettings.fromData(jsonString)
        assertEquals("h1 { font-size: 2em; }", settings.themeStyles)
    }

    @Test
    fun `themeStyles is empty when styles key is missing`() {
        val jsonString = """{"otherKey": "value"}"""
        val settings = EditorSettings.fromData(jsonString)
        assertTrue(settings.themeStyles.isEmpty())
    }

    // MARK: - Codable Tests

    @Test
    fun `EditorSettings can be encoded and decoded`() {
        val jsonString = """{"styles": [{"css": "body { color: red; }", "isGlobalStyles": true}]}"""
        val original = EditorSettings.fromData(jsonString)

        val encoded = json.encodeToString(original)
        val decoded = json.decodeFromString<EditorSettings>(encoded)

        assertEquals(original.stringValue, decoded.stringValue)
        assertEquals(original.themeStyles, decoded.themeStyles)
    }

    @Test
    fun `EditorSettings preserves themeStyles through encoding round-trip`() {
        val jsonString = """{"styles": [{"css": ".theme-class { background: blue; }", "isGlobalStyles": true}, {"css": ".another { margin: 10px; }", "isGlobalStyles": false}]}"""
        val original = EditorSettings.fromData(jsonString)

        val encoded = json.encodeToString(original)
        val decoded = json.decodeFromString<EditorSettings>(encoded)

        assertEquals(".theme-class { background: blue; }\n.another { margin: 10px; }", decoded.themeStyles)
    }

    // MARK: - Edge Cases

    @Test
    fun `themeStyles handles empty css string`() {
        val jsonString = """{"styles": [{"css": "", "isGlobalStyles": true}]}"""
        val settings = EditorSettings.fromData(jsonString)
        assertEquals("", settings.themeStyles)
    }

    @Test
    fun `themeStyles handles css with special characters`() {
        val jsonString = """{"styles": [{"css": ".class::before { content: '\u003C'; }", "isGlobalStyles": true}]}"""
        val settings = EditorSettings.fromData(jsonString)
        assertTrue(settings.themeStyles.contains("::before"))
    }

    @Test
    fun `themeStyles handles multiline css`() {
        val jsonString = """{"styles": [{"css": "body {\n  color: red;\n  background: blue;\n}", "isGlobalStyles": true}]}"""
        val settings = EditorSettings.fromData(jsonString)
        assertTrue(settings.themeStyles.contains("color: red"))
        assertTrue(settings.themeStyles.contains("background: blue"))
    }
}

// MARK: - InternalEditorSettings Tests

class InternalEditorSettingsTest {

    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun `decodes styles array correctly`() {
        val jsonString = """{"styles": [{"css": "body { color: red; }", "isGlobalStyles": true}]}"""
        val settings = json.decodeFromString<InternalEditorSettings>(jsonString)
        assertEquals(1, settings.styles.size)
        assertEquals("body { color: red; }", settings.styles[0].css)
        assertEquals(true, settings.styles[0].isGlobalStyles)
    }

    @Test
    fun `decodes multiple styles`() {
        val jsonString = """{"styles": [{"css": "a", "isGlobalStyles": true}, {"css": "b", "isGlobalStyles": false}]}"""
        val settings = json.decodeFromString<InternalEditorSettings>(jsonString)
        assertEquals(2, settings.styles.size)
        assertEquals("a", settings.styles[0].css)
        assertEquals("b", settings.styles[1].css)
        assertEquals(true, settings.styles[0].isGlobalStyles)
        assertEquals(false, settings.styles[1].isGlobalStyles)
    }

    @Test
    fun `decodes null css value`() {
        val jsonString = """{"styles": [{"css": null, "isGlobalStyles": true}]}"""
        val settings = json.decodeFromString<InternalEditorSettings>(jsonString)
        assertEquals(1, settings.styles.size)
        assertNull(settings.styles[0].css)
    }

    @Test
    fun `decodes empty styles array`() {
        val jsonString = """{"styles": []}"""
        val settings = json.decodeFromString<InternalEditorSettings>(jsonString)
        assertTrue(settings.styles.isEmpty())
    }

    @Test
    fun `parses real editor settings test case`() {
        val data = TestResources.loadResource("editor-settings-test-case-1.json")
        val settings = json.decodeFromString<InternalEditorSettings>(data)

        // The test file should have multiple styles
        assertTrue(settings.styles.isNotEmpty())

        // At least one style should have CSS content
        val stylesWithCSS = settings.styles.filter { !it.css.isNullOrEmpty() }
        assertTrue(stylesWithCSS.isNotEmpty())

        // Verify isGlobalStyles is parsed
        val globalStyles = settings.styles.filter { it.isGlobalStyles }
        assertTrue(globalStyles.isNotEmpty())
    }
}
