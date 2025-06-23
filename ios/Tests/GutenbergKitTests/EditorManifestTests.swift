import Foundation
import Testing
@testable import GutenbergKit

@Suite("Manifest Tests")
struct EditorManifestTests {

    @Test
    func parseAssetLinks() throws {
        let json = try json(named: "manifest-test-case-1")
        let manifest = try JSONDecoder().decode(EditorAssetsMainifest.self, from: json)

        let links = try manifest.parseAssetLinks(defaultScheme: nil)
        let scripts = links.filter { $0.contains(".js") }
        let styles = links.filter { $0.contains(".css") }

        #expect(scripts.count == 79)
        #expect(styles.count == 22)
    }

    @Test
    func editorWebViewGetsCachedLinks() throws {
        let json = try json(named: "manifest-test-case-1")
        let original = try JSONDecoder().decode(EditorAssetsMainifest.self, from: json)
        let forEditor = try JSONDecoder().decode(EditorAssetsMainifest.self, from: original.renderForEditor(defaultScheme: nil))

        #expect(try original.parseAssetLinks(defaultScheme: nil).count == forEditor.parseAssetLinks(defaultScheme: nil).count)

        for link in try original.parseAssetLinks(defaultScheme: nil) {
            #expect(link.hasPrefix("http://"))
        }

        for link in try forEditor.parseAssetLinks(defaultScheme: nil) {
            #expect(link.hasPrefix("gbk-cache-http://"))
        }
    }

    @Test
    func useDefaultScheme() throws {
        let scriptHTML = #"<script src="//w.org/lib.js"></script>"#
        let manifest = EditorAssetsMainifest(scripts: scriptHTML, styles: "", allowedBlockTypes: [])
        #expect(try manifest.parseAssetLinks(defaultScheme: "http") == ["http://w.org/lib.js"])
        #expect(try manifest.parseAssetLinks(defaultScheme: "https") == ["https://w.org/lib.js"])
    }

    private func json(named name: String) throws -> Data {
        let json = Bundle.module.url(forResource: name, withExtension: "json")!
        return try Data(contentsOf: json)
    }
}
