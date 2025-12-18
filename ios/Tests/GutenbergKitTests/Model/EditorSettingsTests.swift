import Foundation
import Testing

@testable import GutenbergKit

@Suite
struct EditorSettingsTests {

    @Test("Throws for invalid JSON")
    func forInvalidJSON() throws{
        let invalidJSON = "not valid json"

        #expect(throws: DecodingError.self) {
            try EditorSettings(data: Data(invalidJSON.utf8))
        }
    }

    // MARK: - themeStyles Tests

    @Test("themeStyles is empty when styles array is empty")
    func themeStylesEmptyWhenNoStyles() throws {
        let json = #"{"styles": []}"#
        let settings = try EditorSettings(data: Data(json.utf8))
        #expect(settings.themeStyles.isEmpty)
    }

    @Test("themeStyles extracts single css value")
    func themeStylesExtractsSingleCSS() throws{
        let json = #"{"styles": [{"css": "body { color: red; }", "isGlobalStyles": true}]}"#
        let settings = try EditorSettings(data: Data(json.utf8))
        #expect(settings.themeStyles == "body { color: red; }")
    }

    @Test("themeStyles joins multiple css values with newlines")
    func themeStylesJoinsMultipleCSS() throws{
        let json = """
      {"styles": [{"css": "body { color: red; }", "isGlobalStyles": true}, {"css": "h1 { font-size: 2em; }", "isGlobalStyles": false}]}
      """
        let settings = try EditorSettings(data: Data(json.utf8))
        #expect(settings.themeStyles == "body { color: red; }\nh1 { font-size: 2em; }")
    }

    @Test("themeStyles skips styles with null css")
    func themeStylesSkipsNullCSS() throws{
        let json = """
      {"styles": [{"css": null, "isGlobalStyles": true}, {"css": "h1 { font-size: 2em; }", "isGlobalStyles": false}]}
      """
        let settings = try EditorSettings(data: Data(json.utf8))
        #expect(settings.themeStyles == "h1 { font-size: 2em; }")
    }

    @Test("themeStyles skips styles without css key")
    func themeStylesSkipsMissingCSS() throws{
        let json = """
      {"styles": [{"isGlobalStyles": true}, {"css": "h1 { font-size: 2em; }", "isGlobalStyles": false}]}
      """
        let settings = try EditorSettings(data: Data(json.utf8))
        #expect(settings.themeStyles == "h1 { font-size: 2em; }")
    }

    @Test("themeStyles is empty when styles key is missing")
    func themeStylesEmptyWhenStylesKeyMissing() throws{
        let json = """
      {"otherKey": "value"}
      """
        let settings = try EditorSettings(data: Data(json.utf8))
        #expect(settings.themeStyles.isEmpty)
    }

    // MARK: - Codable Tests

    @Test("EditorSettings can be encoded and decoded")
    func encodableAndDecodable() throws {
        let json = """
      {"styles": [{"css": "body { color: red; }", "isGlobalStyles": true}]}
      """
        let original = try EditorSettings(data: Data(json.utf8))

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EditorSettings.self, from: encoded)

        #expect(decoded.stringValue == original.stringValue)
        #expect(decoded.themeStyles == original.themeStyles)
    }

    @Test("EditorSettings preserves themeStyles through encoding round-trip")
    func themeStylesPreservedThroughRoundTrip() throws {
        let json = """
      {"styles": [{"css": ".theme-class { background: blue; }", "isGlobalStyles": true}, {"css": ".another { margin: 10px; }", "isGlobalStyles": false}]}
      """
        let original = try EditorSettings(data: Data(json.utf8))

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EditorSettings.self, from: encoded)

        #expect(decoded.themeStyles == ".theme-class { background: blue; }\n.another { margin: 10px; }")
    }

    // MARK: - Edge Cases

    @Test("themeStyles handles empty css string")
    func themeStylesHandlesEmptyCSS() throws {
        let json = """
      {"styles": [{"css": "", "isGlobalStyles": true}]}
      """
        let settings = try EditorSettings(data: Data(json.utf8))
        #expect(settings.themeStyles == "")
    }

    @Test("themeStyles handles css with special characters")
    func themeStylesHandlesSpecialCharacters() throws {
        let json = """
      {"styles": [{"css": ".class::before { content: '\\u003C'; }", "isGlobalStyles": true}]}
      """
        let settings = try EditorSettings(data: Data(json.utf8))
        #expect(settings.themeStyles.contains("::before"))
    }

    @Test("themeStyles handles multiline css")
    func themeStylesHandlesMultilineCSS() throws {
        let json = """
      {"styles": [{"css": "body {\\n  color: red;\\n  background: blue;\\n}", "isGlobalStyles": true}]}
      """
        let settings = try EditorSettings(data: Data(json.utf8))
        #expect(settings.themeStyles.contains("color: red"))
        #expect(settings.themeStyles.contains("background: blue"))
    }
}

// MARK: - InternalEditorSettings Tests

@Suite
struct InternalEditorSettingsTests {

    @Test("decodes styles array correctly")
    func decodesStylesArray() throws {
        let json = """
      {"styles": [{"css": "body { color: red; }", "isGlobalStyles": true}]}
      """
        let styles = try #require(JSONDecoder().decode(InternalEditorSettings.self, from: Data(json.utf8)).styles)
        #expect(styles.count == 1)
        #expect(styles[0].css == "body { color: red; }")
        #expect(styles[0].isGlobalStyles == true)
    }

    @Test("decodes multiple styles")
    func decodesMultipleStyles() throws {
        let json = """
      {"styles": [{"css": "a", "isGlobalStyles": true}, {"css": "b", "isGlobalStyles": false}]}
      """
        let styles = try #require(JSONDecoder().decode(InternalEditorSettings.self, from: Data(json.utf8)).styles)
        #expect(styles.count == 2)
        #expect(styles[0].css == "a")
        #expect(styles[1].css == "b")
        #expect(styles[0].isGlobalStyles == true)
        #expect(styles[1].isGlobalStyles == false)
    }

    @Test("decodes null css value")
    func decodesNullCSS() throws {
        let json = """
      {"styles": [{"css": null, "isGlobalStyles": true}]}
      """
        let styles = try #require(JSONDecoder().decode(InternalEditorSettings.self, from: Data(json.utf8)).styles)
        #expect(styles.count == 1)
        #expect(styles[0].css == nil)
    }

    @Test("decodes empty styles array")
    func decodesEmptyStylesArray() throws {
        let json = """
      {"styles": []}
      """
        let styles = try #require(JSONDecoder().decode(InternalEditorSettings.self, from: Data(json.utf8)).styles)
        #expect(styles.isEmpty)
    }

    @Test("parses real editor settings test case")
    func parsesRealEditorSettingsTestCase() throws {
        let data = try Data.forResource(named: "editor-settings-test-case-1")
        let styles = try #require(JSONDecoder().decode(InternalEditorSettings.self, from: data).styles)

        // The test file should have multiple styles
        #expect(!styles.isEmpty)

        // At least one style should have CSS content
        let stylesWithCSS = styles.filter { $0.css != nil && !$0.css!.isEmpty }
        #expect(!stylesWithCSS.isEmpty)

        // Verify isGlobalStyles is parsed
        let globalStyles = styles.filter { $0.isGlobalStyles }
        #expect(!globalStyles.isEmpty)
    }
}
