import Foundation
import Testing

@testable import GutenbergKit

@Suite
struct RemoteEditorAssetManifestTests {

  // MARK: - Decoding
  @Test("decodes from valid JSON")
  func decodesFromValidJSON() throws {
    let json = """
      {
          "scripts": "<script src=\\"https://example.com/script.js\\"></script>",
          "styles": "<link rel=\\"stylesheet\\" href=\\"https://example.com/style.css\\">",
          "allowed_block_types": ["core/paragraph", "core/heading"]
      }
      """
    let data = Data(json.utf8)
    let manifest = try RemoteEditorAssetManifest(data: data)
    #expect(manifest.scripts.contains("script.js"))
    #expect(manifest.styles.contains("style.css"))
    #expect(manifest.allowedBlockTypes == ["core/paragraph", "core/heading"])
  }

  @Test("decodes empty allowed block types")
  func decodesEmptyAllowedBlockTypes() throws {
    let json = """
      {
          "scripts": "",
          "styles": "",
          "allowed_block_types": []
      }
      """
    let data = Data(json.utf8)
    let manifest = try RemoteEditorAssetManifest(data: data)
    #expect(manifest.allowedBlockTypes.isEmpty)
  }

  // MARK: - Decoding
  @Test(
    "Successfully decodes test cases",
    arguments: [
      "editor-asset-manifest-test-case-1"
    ])
  func testCases(name: String) async throws {
    _ = try RemoteEditorAssetManifest(data: Data.forResource(named: name))
  }
}
