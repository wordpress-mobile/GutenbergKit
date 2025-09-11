import Foundation
import Testing
@testable import GutenbergKit

@Suite("Manifest Tests")
struct EditorManifestTests {

    let parser: EditorAssetManifestParser = AssetManifestParserProvider.default

    @Test
    func parseAssetLinks() throws {
        let json = try json(named: "manifest-test-case-1")
        let manifest = try EditorAssetManifest(data: json)

        let scripts = try manifest.getScriptUrls(using: parser)
        let styles = try manifest.getStyleUrls(using: parser)

        #expect(scripts.count == 80)
        #expect(styles.count == 22)
    }

    @Test
    func editorWebViewGetsCachedLinks() throws {
        let json = try json(named: "manifest-test-case-1")
        let original = try EditorAssetManifest(data: json)
        let forEditor = try original.resolvingCachedUrls(using: parser)

        let originalAssetUrls = try original.getAllAssetUrls(using: parser)
        let editorAssetUrls = try forEditor.getAllAssetUrls(using: parser)

        #expect(originalAssetUrls.count == editorAssetUrls.count)

        for link in originalAssetUrls {
            #expect(link.scheme == "http")
        }

        for link in editorAssetUrls {
            #expect(link.scheme == "gbk-cache-http")
        }
    }

    @Test
    func useDefaultScheme() throws {
        let scriptHTML = #"<script src="//w.org/lib.js"></script>"#
        let defaultManifest = EditorAssetManifest(scripts: scriptHTML, styles: "", allowedBlockTypes: [])
        let httpManifest = try defaultManifest.applyingUrlScheme("http", using: parser)
        let httpsManifest = try defaultManifest.applyingUrlScheme("https", using: parser)

        #expect(try httpManifest.getScriptUrlStrings(using: parser) == ["http://w.org/lib.js"])
        #expect(try httpsManifest.getScriptUrlStrings(using: parser) == ["https://w.org/lib.js"])
    }

    private func json(named name: String) throws -> Data {
        let json = Bundle.module.url(forResource: name, withExtension: "json")!
        return try Data(contentsOf: json)
    }
}
