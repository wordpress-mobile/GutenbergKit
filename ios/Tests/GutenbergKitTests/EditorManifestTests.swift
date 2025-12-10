import Foundation
import Testing
@testable import GutenbergKit

@Suite("Manifest Tests")
struct EditorManifestTests {

    @Test
    func parseAssetLinks() throws {
        let json = try json(named: "manifest-test-case-1")
        let manifest = try JSONDecoder().decode(EditorAssetsManifest.self, from: json)

        let links = manifest.parseAssetLinks(defaultScheme: nil)
        let scripts = links.filter { $0.contains(".js") }
        let styles = links.filter { $0.contains(".css") }

        #expect(scripts.count == 3)
        #expect(styles.count == 2)
    }

    @Test
    func editorWebViewGetsCachedLinks() throws {
        let json = try json(named: "manifest-test-case-1")
        let original = try JSONDecoder().decode(EditorAssetsManifest.self, from: json)
        let forEditor = try JSONDecoder().decode(EditorAssetsManifest.self, from: original.renderForEditor(defaultScheme: nil))

        #expect(original.parseAssetLinks(defaultScheme: nil).count == forEditor.parseAssetLinks(defaultScheme: nil).count)

        for link in original.parseAssetLinks(defaultScheme: nil) {
            #expect(link.hasPrefix("http://"))
        }

        #if canImport(UIKit)
        for link in forEditor.parseAssetLinks(defaultScheme: nil) {
            #expect(link.hasPrefix("gbk-cache-http://"))
        }
        #else
        for link in forEditor.parseAssetLinks(defaultScheme: nil) {
            #expect(link.hasPrefix("http://"))
        }
        #endif
    }

    @Test
    func useDefaultScheme() throws {
        let json = """
        {
            "scripts": {
                "test-script": {
                    "src": "//w.org/lib.js",
                    "deps": [],
                    "version": "1.0.0"
                }
            },
            "styles": {},
            "inline_scripts": { "before": {}, "after": {} },
            "inline_styles": { "before": {}, "after": {} }
        }
        """.data(using: .utf8)!

        let manifestHTTP = try JSONDecoder().decode(EditorAssetsManifest.self, from: json)
        #expect(manifestHTTP.parseAssetLinks(defaultScheme: "http") == ["http://w.org/lib.js?ver=1.0.0"])

        let manifestHTTPS = try JSONDecoder().decode(EditorAssetsManifest.self, from: json)
        #expect(manifestHTTPS.parseAssetLinks(defaultScheme: "https") == ["https://w.org/lib.js?ver=1.0.0"])
    }

    @Test
    func decodesInlineAssets() throws {
        let json = try json(named: "manifest-test-case-1")
        let manifest = try JSONDecoder().decode(EditorAssetsManifest.self, from: json)

        // Check inline scripts
        #expect(manifest.inlineScripts.before?["jetpack-forms-blocks"] != nil)
        #expect(manifest.inlineScripts.after?["jetpack-contact-form"] != nil)

        // Check inline styles
        #expect(manifest.inlineStyles.before?["jetpack-forms-blocks-css"] != nil)
    }

    @Test
    func decodesScriptAssetProperties() throws {
        let json = try json(named: "manifest-test-case-1")
        let manifest = try JSONDecoder().decode(EditorAssetsManifest.self, from: json)

        let script = manifest.scripts["jetpack-forms-blocks"]
        #expect(script?.src?.urlString == "http://localhost/wp-content/plugins/jetpack/forms/dist/blocks/view.js")
        #expect(script?.deps == ["wp-element", "wp-blocks"])
        #expect(script?.version?.stringValue == "1.0.0")
        #expect(script?.inFooter == true)
    }

    @Test
    func decodesStyleAssetProperties() throws {
        let json = try json(named: "manifest-test-case-1")
        let manifest = try JSONDecoder().decode(EditorAssetsManifest.self, from: json)

        let style = manifest.styles["jetpack-contact-form-css"]
        #expect(style?.src?.urlString == "http://localhost/wp-content/plugins/jetpack/modules/contact-form/css/editor.css")
        #expect(style?.deps == ["jetpack-forms-blocks-css"])
        #expect(style?.version?.stringValue == "2.0.0")
        #expect(style?.media == "screen")
    }

    private func json(named name: String) throws -> Data {
        let json = Bundle.module.url(forResource: name, withExtension: "json")!
        return try Data(contentsOf: json)
    }
}
