import Foundation
import JavaScriptCore
import Testing

@testable import GutenbergKit

@Suite
struct GBKitGlobalTests: MakesTestFixtures {

  static let testSiteURL = URL(string: "https://example.com")!
  static let testApiRoot = URL(string: "https://example.com/wp-json")!

  private func makeDependencies() -> EditorDependencies {
    EditorDependencies(
      editorSettings: .undefined,
      assetBundle: .empty,
      preloadList: makePreloadList()
    )
  }

  private func makePreloadList() -> EditorPreloadList {
    EditorPreloadList(
      postType: .post,
      postTypeData: EditorURLResponse(data: Data(), responseHeaders: [:]),
      postTypesData: EditorURLResponse(data: Data(), responseHeaders: [:]),
      activeThemeData: EditorURLResponse(data: Data(), responseHeaders: [:]),
      settingsOptionsData: EditorURLResponse(data: Data(), responseHeaders: [:])
    )
  }

  // MARK: - Initialization

  @Test("initializes with configuration and dependencies")
  func initializesWithConfigurationAndDependencies() throws {
    let configuration = makeConfiguration()
    let dependencies = makeDependencies()
    let global = try GBKitGlobal(configuration: configuration, dependencies: dependencies)
    #expect(global.siteURL == Self.testSiteURL)
  }

  // MARK: - Property Mapping

  @Test("maps siteURL from configuration")
  func mapsSiteUrl() throws {
    let siteURL = URL(string: "https://my-wordpress-site.com")!
    let configuration = makeConfiguration(siteURL: siteURL)
    let global = try GBKitGlobal(configuration: configuration, dependencies: makeDependencies())
    #expect(global.siteURL == siteURL)
  }

  @Test("maps siteApiRoot from configuration")
  func mapsSiteApiRoot() throws {
    let configuration = makeConfiguration()
    let global = try GBKitGlobal(configuration: configuration, dependencies: makeDependencies())
    #expect(global.siteApiRoot == Self.testApiRoot)
  }

  @Test("maps themeStyles from configuration")
  func mapsThemeStyles() throws {
    let withThemeStyles = makeConfiguration(shouldUseThemeStyles: true)
    let withoutThemeStyles = makeConfiguration(shouldUseThemeStyles: false)

    let globalWith = try GBKitGlobal(
      configuration: withThemeStyles, dependencies: makeDependencies())
    let globalWithout = try GBKitGlobal(
      configuration: withoutThemeStyles, dependencies: makeDependencies())

    #expect(globalWith.themeStyles == true)
    #expect(globalWithout.themeStyles == false)
  }

  @Test("maps plugins from configuration")
  func mapsPlugins() throws {
    let withPlugins = makeConfiguration(shouldUsePlugins: true)
    let withoutPlugins = makeConfiguration(shouldUsePlugins: false)

    let globalWith = try GBKitGlobal(configuration: withPlugins, dependencies: makeDependencies())
    let globalWithout = try GBKitGlobal(
      configuration: withoutPlugins, dependencies: makeDependencies())

    #expect(globalWith.plugins == true)
    #expect(globalWithout.plugins == false)
  }

  @Test("maps postID to post.id")
  func mapsPostId() throws {
    let withPostID = makeConfiguration(postID: 42)
    let withoutPostID = makeConfiguration(postID: nil)

    let globalWith = try GBKitGlobal(configuration: withPostID, dependencies: makeDependencies())
    let globalWithout = try GBKitGlobal(
      configuration: withoutPostID, dependencies: makeDependencies())

    #expect(globalWith.post.id == 42)
    #expect(globalWithout.post.id == -1)
  }

  @Test("maps postType to post.type")
  func mapsPostType() throws {
    let postConfig = makeConfiguration(postType: .post)
    let pageConfig = makeConfiguration(postType: .page)

    let postGlobal = try GBKitGlobal(configuration: postConfig, dependencies: makeDependencies())
    let pageGlobal = try GBKitGlobal(configuration: pageConfig, dependencies: makeDependencies())

    #expect(postGlobal.post.type == "post")
    #expect(pageGlobal.post.type == "page")
  }

  @Test("maps postStatus to post.status")
  func mapsPostStatus() throws {
    let draftConfig = makeConfigurationBuilder()
      .setPostStatus("draft")
      .build()
    let publishConfig = makeConfigurationBuilder()
      .setPostStatus("publish")
      .build()

    let draftGlobal = try GBKitGlobal(configuration: draftConfig, dependencies: makeDependencies())
    let publishGlobal = try GBKitGlobal(
      configuration: publishConfig, dependencies: makeDependencies())

    #expect(draftGlobal.post.status == "draft")
    #expect(publishGlobal.post.status == "publish")
  }

  @Test("maps title with percent encoding")
  func mapsTitleWithEncoding() throws {
    let configuration = makeConfiguration(title: "Hello World")
    let global = try GBKitGlobal(configuration: configuration, dependencies: makeDependencies())
    #expect(global.post.title == "Hello%20World")
  }

  @Test("maps content with percent encoding")
  func mapsContentWithEncoding() throws {
    let configuration = makeConfiguration(
      content: "<!-- wp:paragraph --><p>Test</p><!-- /wp:paragraph -->")
    let global = try GBKitGlobal(configuration: configuration, dependencies: makeDependencies())
    #expect(global.post.content.contains("%"))
    #expect(!global.post.content.contains("<"))
  }

  // MARK: - toString()

  @Test("toString produces valid JSON")
  func toStringProducesValidJson() throws {
    let configuration = makeConfiguration()
    let global = try GBKitGlobal(configuration: configuration, dependencies: makeDependencies())

    let jsonString = try global.toString()
    let data = Data(jsonString.utf8)
    let decoded = try JSONSerialization.jsonObject(with: data)

    #expect(decoded is [String: Any])
  }

  @Test("toString includes all required fields")
  func toStringIncludesAllFields() throws {
    let configuration = makeConfiguration(postID: 123, title: "Test", content: "Content")
    let global = try GBKitGlobal(configuration: configuration, dependencies: makeDependencies())

    let jsonString = try global.toString()

    #expect(jsonString.contains("siteURL"))
    #expect(jsonString.contains("siteApiRoot"))
    #expect(jsonString.contains("themeStyles"))
    #expect(jsonString.contains("plugins"))
    #expect(jsonString.contains("post"))
    #expect(jsonString.contains("\"type\""))
    #expect(jsonString.contains("\"status\""))
    #expect(jsonString.contains("locale"))
    #expect(jsonString.contains("logLevel"))
  }

  @Test("toString round-trips through Codable")
  func toStringRoundTrips() throws {
    let configuration = makeConfiguration(postID: 99, title: "Round Trip", content: "Test content")
    let original = try GBKitGlobal(configuration: configuration, dependencies: makeDependencies())

    let jsonString = try original.toString()
    let data = Data(jsonString.utf8)
    let decoded = try JSONDecoder().decode(GBKitGlobal.self, from: data)

    #expect(decoded.siteURL == original.siteURL)
    #expect(decoded.post.id == original.post.id)
    #expect(decoded.post.type == original.post.type)
    #expect(decoded.post.status == original.post.status)
    #expect(decoded.post.title == original.post.title)
    #expect(decoded.themeStyles == original.themeStyles)
    #expect(decoded.plugins == original.plugins)
  }

  // MARK: - Special Characters

  @Test("handles unicode in title")
  func handlesUnicodeInTitle() throws {
    let configuration = makeConfiguration(title: "日本語タイトル")
    let global = try GBKitGlobal(configuration: configuration, dependencies: makeDependencies())

    let jsonString = try global.toString()
    #expect(!jsonString.isEmpty)

    let data = Data(jsonString.utf8)
    let decoded = try JSONDecoder().decode(GBKitGlobal.self, from: data)
    #expect(decoded.post.title == global.post.title)
  }

  @Test("handles emoji in content")
  func handlesEmojiInContent() throws {
    let configuration = makeConfiguration(content: "Hello 👋 World 🌍")
    let global = try GBKitGlobal(configuration: configuration, dependencies: makeDependencies())

    let jsonString = try global.toString()
    #expect(!jsonString.isEmpty)

    let data = Data(jsonString.utf8)
    let decoded = try JSONDecoder().decode(GBKitGlobal.self, from: data)
    #expect(decoded.post.content == global.post.content)
  }

  @Test("handles special HTML characters in content")
  func handlesHtmlCharactersInContent() throws {
    let configuration = makeConfiguration(content: "<script>alert('xss')</script>")
    let global = try GBKitGlobal(configuration: configuration, dependencies: makeDependencies())

    let jsonString = try global.toString()
    // Should be percent-encoded, not raw HTML
    #expect(!jsonString.contains("<script>"))
  }

  // MARK: - Edge Cases

  @Test("handles empty title and content")
  func handlesEmptyTitleAndContent() throws {
    let configuration = makeConfiguration(title: "", content: "")
    let global = try GBKitGlobal(configuration: configuration, dependencies: makeDependencies())

    let jsonString = try global.toString()
    #expect(!jsonString.isEmpty)

    let data = Data(jsonString.utf8)
    let decoded = try JSONDecoder().decode(GBKitGlobal.self, from: data)
    #expect(decoded.post.title.isEmpty)
    #expect(decoded.post.content.isEmpty)
  }

  @Test("handles very long content")
  func handlesVeryLongContent() throws {
    let longContent = String(repeating: "Lorem ipsum dolor sit amet. ", count: 1000)
    let configuration = makeConfiguration(content: longContent)
    let global = try GBKitGlobal(configuration: configuration, dependencies: makeDependencies())

    let jsonString = try global.toString()
    #expect(!jsonString.isEmpty)

    let data = Data(jsonString.utf8)
    let decoded = try JSONDecoder().decode(GBKitGlobal.self, from: data)
    #expect(!decoded.post.content.isEmpty)
  }

  @Test("Can be parsed in JavaScript")
  func isValidJS() throws {
    let configuration = makeConfiguration(title: "Test", content: "Hello")
    let global = try GBKitGlobal(configuration: configuration, dependencies: makeDependencies())

    let context = JSContext()!
    context.evaluateScript("var globalConfig = \(try global.toString());")

    #expect(context.objectForKeyedSubscript("globalConfig").isObject)
  }
}
