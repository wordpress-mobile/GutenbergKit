import Foundation
import Testing

@testable import GutenbergKit

struct LocalEditorAssetManifestTests {

  // MARK: - assetUrls
  @Test("parses script src attributes")
  func parsesScriptSrc() throws {
    let json = """
      {
          "scripts": "<script src=\\"https://example.com/app.js\\"></script><script src=\\"https://example.com/vendor.js\\"></script>",
          "styles": "",
          "allowed_block_types": []
      }
      """
    let manifest = try LocalEditorAssetManifest.from(data: Data(json.utf8))
    let links = manifest.assetUrls
    #expect(links.contains(URL(string: "https://example.com/app.js")!))
    #expect(links.contains(URL(string: "https://example.com/vendor.js")!))
  }

  @Test("parses stylesheet href attributes")
  func parsesStylesheetHref() throws {
    let json = """
      {
          "scripts": "",
          "styles": "<link rel=\\"stylesheet\\" href=\\"https://example.com/main.css\\"><link rel=\\"stylesheet\\" href=\\"https://example.com/theme.css\\">",
          "allowed_block_types": []
      }
      """
    let manifest = try LocalEditorAssetManifest.from(data: Data(json.utf8))
    let links = manifest.assetUrls
    #expect(links.contains(URL(string: "https://example.com/main.css")!))
    #expect(links.contains(URL(string: "https://example.com/theme.css")!))
  }

  @Test("parses both scripts and styles")
  func parsesBothScriptsAndStyles() throws {
    let json = """
      {
          "scripts": "<script src=\\"https://example.com/app.js\\"></script>",
          "styles": "<link rel=\\"stylesheet\\" href=\\"https://example.com/style.css\\">",
          "allowed_block_types": []
      }
      """
    let manifest = try LocalEditorAssetManifest.from(data: Data(json.utf8))
    let links = manifest.assetUrls
    #expect(links.count == 2)
    #expect(links.contains(URL(string: "https://example.com/app.js")!))
    #expect(links.contains(URL(string: "https://example.com/style.css")!))
  }

  @Test("resolves protocol-relative URLs with default scheme")
  func resolvesProtocolRelativeURLs() throws {
    let json = """
      {
          "scripts": "<script src=\\"//cdn.example.com/script.js\\"></script>",
          "styles": "<link rel=\\"stylesheet\\" href=\\"//cdn.example.com/style.css\\">",
          "allowed_block_types": []
      }
      """
    let manifest = try LocalEditorAssetManifest.from(data: Data(json.utf8))

    let linksWithHttps = manifest.assetUrls
    #expect(linksWithHttps.contains(URL(string: "https://cdn.example.com/script.js")!))
    #expect(linksWithHttps.contains(URL(string: "https://cdn.example.com/style.css")!))
  }

  @Test("uses https as default scheme when none specified")
  func usesHttpsAsDefaultScheme() throws {
    let json = """
      {
          "scripts": "<script src=\\"//cdn.example.com/script.js\\"></script>",
          "styles": "",
          "allowed_block_types": []
      }
      """
    let manifest = try LocalEditorAssetManifest.from(data: Data(json.utf8))
    let links = manifest.assetUrls
    #expect(links.contains(URL(string: "https://cdn.example.com/script.js")!))
  }

  @Test("ignores inline scripts without src")
  func ignoresInlineScripts() throws {
    let json = """
      {
          "scripts": "<script>console.log('inline');</script><script src=\\"https://example.com/app.js\\"></script>",
          "styles": "",
          "allowed_block_types": []
      }
      """
    let manifest = try LocalEditorAssetManifest.from(data: Data(json.utf8))
    let links = manifest.assetUrls
    #expect(links.count == 1)
    #expect(links.contains(URL(string: "https://example.com/app.js")!))
  }

  @Test("ignores link tags without stylesheet rel")
  func ignoresNonStylesheetLinks() throws {
    let json = """
      {
          "scripts": "",
          "styles": "<link rel=\\"preload\\" href=\\"https://example.com/font.woff2\\"><link rel=\\"stylesheet\\" href=\\"https://example.com/style.css\\">",
          "allowed_block_types": []
      }
      """
    let manifest = try LocalEditorAssetManifest.from(data: Data(json.utf8))
    let links = manifest.assetUrls
    #expect(links.count == 1)
    #expect(links.contains(URL(string: "https://example.com/style.css")!))
  }

  @Test("returns empty array for empty scripts and styles")
  func returnsEmptyForEmptyContent() throws {
    let json = """
      {
          "scripts": "",
          "styles": "",
          "allowed_block_types": []
      }
      """
    let manifest = try LocalEditorAssetManifest.from(data: Data(json.utf8))
    let links = manifest.assetUrls
    #expect(links.isEmpty)
  }

  @Test("Empty Manifest is Empty")
  func emptyManifestIsEmpty() throws {
    #expect(LocalEditorAssetManifest.empty.scripts.isEmpty)
    #expect(LocalEditorAssetManifest.empty.styles.isEmpty)
    #expect(LocalEditorAssetManifest.empty.allowedBlockTypes.isEmpty)
    #expect(LocalEditorAssetManifest.empty.rawStyles.isEmpty)
    #expect(LocalEditorAssetManifest.empty.rawScripts.isEmpty)
    #expect(LocalEditorAssetManifest.empty.assetUrls.isEmpty)
  }
}

extension LocalEditorAssetManifest {
  fileprivate static func from(data: Data) throws -> LocalEditorAssetManifest {
    let remote = try RemoteEditorAssetManifest(data: data)
    return try LocalEditorAssetManifest(remoteManifest: remote)
  }
}
