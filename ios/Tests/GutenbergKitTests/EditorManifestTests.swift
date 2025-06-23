import Foundation
import Testing
@testable import GutenbergKit

@Suite("Manifest Tests")
struct EditorManifestTests {

    @Test
    func parseAssetLinks() async throws {
        let json = try json(named: "manifest-test-case-1")
        let manifest = try JSONDecoder().decode(EditorAssetsMainifest.self, from: json)

        let links = try manifest.parseAssetLinks()
        let scripts = links.filter { $0.contains(".js") }
        let styles = links.filter { $0.contains(".css") }

        #expect(scripts.count == 79)
        #expect(styles.count == 22)
    }

    @Test
    func editorWebViewGetsCachedLinks() async throws {
        let json = try json(named: "manifest-test-case-1")
        let original = try JSONDecoder().decode(EditorAssetsMainifest.self, from: json)
        let forEditor = try JSONDecoder().decode(EditorAssetsMainifest.self, from: original.renderForEditor())

        #expect(try original.parseAssetLinks().count == forEditor.parseAssetLinks().count)

        for link in try original.parseAssetLinks() {
            #expect(link.hasPrefix("http://"))
        }

        for link in try forEditor.parseAssetLinks() {
            #expect(link.hasPrefix("gbk-cache-http://"))
        }
    }

    private func json(named name: String) throws -> Data {
        let json = Bundle.module.url(forResource: name, withExtension: "json")!
        return try Data(contentsOf: json)
    }
}
