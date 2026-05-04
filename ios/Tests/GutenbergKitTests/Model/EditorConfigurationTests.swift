import Foundation
import Testing

@testable import GutenbergKit

@Suite
struct EditorConfigurationBuilderTests: MakesTestFixtures {
  // MARK: - Test Fixtures

  static let testSiteURL = URL(string: "https://example.com")!
  static let testApiRoot = URL(string: "https://example.com/wp-json")!

  // MARK: - Default Values Tests

  @Test("Builder uses correct default values")
  func builderDefaultValues() {
    let config = makeConfigurationBuilder().build()

    #expect(config.title == "")
    #expect(config.content == "")
    #expect(config.postID == nil)
    #expect(config.postType == .post)
    #expect(config.postStatus == "draft")
    #expect(config.shouldUseThemeStyles == false)
    #expect(config.shouldUsePlugins == false)
    #expect(config.shouldHideTitle == false)
    #expect(config.siteURL == Self.testSiteURL)
    #expect(config.siteApiRoot == Self.testApiRoot)
    #expect(config.siteApiNamespace == [])
    #expect(config.namespaceExcludedPaths == [])
    #expect(config.authHeader == "")
    #expect(config.editorSettings == "undefined")
    #expect(config.locale == "en")
    #expect(config.isNativeInserterEnabled == false)
    #expect(config.logLevel == .error)
    #expect(config.enableNetworkLogging == false)
  }

  // MARK: - Individual Setter Tests

  @Test("setTitle updates title")
  func setTitleUpdatesTitle() {
    let config = makeConfigurationBuilder()
      .setTitle("My Post Title")
      .build()

    #expect(config.title == "My Post Title")
  }

  @Test("setContent updates content")
  func setContentUpdatesContent() {
    let config = makeConfigurationBuilder()
      .setContent("<p>Hello world</p>")
      .build()

    #expect(config.content == "<p>Hello world</p>")
  }

  @Test("setPostID updates postID")
  func setPostIDUpdatesPostID() {
    let config = makeConfigurationBuilder()
      .setPostID(123)
      .build()

    #expect(config.postID == 123)
  }

  @Test("setPostID with zero results in nil")
  func setPostIDWithZeroResultsInNil() {
    let config = makeConfigurationBuilder()
      .setPostID(0)
      .build()

    #expect(config.postID == nil)
  }

  @Test("setPostID with nil clears postID")
  func setPostIDWithNilClearsPostID() {
    let config = makeConfigurationBuilder()
      .setPostID(123)
      .setPostID(nil)
      .build()

    #expect(config.postID == nil)
  }

  @Test("setPostType updates postType")
  func setPostTypeUpdatesPostType() {
    let config = makeConfigurationBuilder()
      .setPostType(.page)
      .build()

    #expect(config.postType == .page)
  }

  @Test("setShouldUseThemeStyles updates shouldUseThemeStyles")
  func setShouldUseThemeStylesUpdates() {
    let config = makeConfigurationBuilder()
      .setShouldUseThemeStyles(true)
      .build()

    #expect(config.shouldUseThemeStyles == true)
  }

  @Test("setShouldUsePlugins updates shouldUsePlugins")
  func setShouldUsePluginsUpdates() {
    let config = makeConfigurationBuilder()
      .setShouldUsePlugins(true)
      .build()

    #expect(config.shouldUsePlugins == true)
  }

  @Test("setShouldHideTitle updates shouldHideTitle")
  func setShouldHideTitleUpdates() {
    let config = makeConfigurationBuilder()
      .setShouldHideTitle(true)
      .build()

    #expect(config.shouldHideTitle == true)
  }

  @Test("setSiteUrl updates siteURL")
  func setSiteUrlUpdatesSiteURL() {
    let newURL = URL(string: "https://other.com")!
    let config = makeConfigurationBuilder()
      .setSiteUrl(newURL)
      .build()

    #expect(config.siteURL == newURL)
  }

  @Test("setSiteApiRoot updates siteApiRoot")
  func setSiteApiRootUpdatesSiteApiRoot() {
    let newURL = URL(string: "https://other.com/wp-json/v2")!
    let config = makeConfigurationBuilder()
      .setSiteApiRoot(newURL)
      .build()

    #expect(config.siteApiRoot == newURL)
  }

  @Test("setSiteApiNamespace updates siteApiNamespace")
  func setSiteApiNamespaceUpdates() {
    let namespaces = ["wp/v2", "wp/v3"]
    let config = makeConfigurationBuilder()
      .setSiteApiNamespace(namespaces)
      .build()

    #expect(config.siteApiNamespace == namespaces)
  }

  @Test("setNamespaceExcludedPaths updates namespaceExcludedPaths")
  func setNamespaceExcludedPathsUpdates() {
    let paths = ["/oembed", "/batch"]
    let config = makeConfigurationBuilder()
      .setNamespaceExcludedPaths(paths)
      .build()

    #expect(config.namespaceExcludedPaths == paths)
  }

  @Test("setAuthHeader updates authHeader")
  func setAuthHeaderUpdatesAuthHeader() {
    let config = makeConfigurationBuilder()
      .setAuthHeader("Bearer token123")
      .build()

    #expect(config.authHeader == "Bearer token123")
  }

  @Test("setEditorSettings updates editorSettings")
  func setEditorSettingsUpdatesEditorSettings() {
    let settings = #"{"colors":[]}"#
    let config = makeConfigurationBuilder()
      .setEditorSettings(settings)
      .build()

    #expect(config.editorSettings == settings)
  }

  @Test("setLocale updates locale")
  func setLocaleUpdatesLocale() {
    let config = makeConfigurationBuilder()
      .setLocale("fr_FR")
      .build()

    #expect(config.locale == "fr_FR")
  }

  @Test("setLocale(Locale) resolves against the shipped translation bundles")
  func setLocaleResolvesPlatformLocale() {
    // Smoke test against the real bundle. We can only assert robust
    // post-conditions because the manifest depends on `make build`
    // having run, but the resolver always lands on either a shipped
    // tag or the `en` fallback — never an unresolved regional tag.
    let config = makeConfigurationBuilder()
      .setLocale(Locale(identifier: "pt_BR"))
      .build()

    let lower = config.locale.lowercased()
    #expect(lower == "pt-br" || lower == "pt" || lower == "en")
  }

  @Test("setNativeInserterEnabled updates isNativeInserterEnabled")
  func setNativeInserterEnabledUpdates() {
    let config = makeConfigurationBuilder()
      .setNativeInserterEnabled(true)
      .build()

    #expect(config.isNativeInserterEnabled == true)
  }

  @Test("setNativeInserterEnabled defaults to true")
  func setNativeInserterEnabledDefaultsToTrue() {
    let config = makeConfigurationBuilder()
      .setNativeInserterEnabled()
      .build()

    #expect(config.isNativeInserterEnabled == true)
  }

  @Test("setLogLevel updates logLevel")
  func setLogLevelUpdatesLogLevel() {
    let config = makeConfigurationBuilder()
      .setLogLevel(.debug)
      .build()

    #expect(config.logLevel == .debug)
  }

  @Test("setEnableNetworkLogging updates enableNetworkLogging")
  func setEnableNetworkLoggingUpdates() {
    let config = makeConfigurationBuilder()
      .setEnableNetworkLogging(true)
      .build()

    #expect(config.enableNetworkLogging == true)
  }

  @Test("Builder uses draft as default postStatus")
  func builderDefaultPostStatus() {
    let config = makeConfigurationBuilder().build()

    #expect(config.postStatus == "draft")
  }

  @Test("setPostStatus updates postStatus")
  func setPostStatusUpdatesPostStatus() {
    let config = makeConfigurationBuilder()
      .setPostStatus("publish")
      .build()

    #expect(config.postStatus == "publish")
  }

  // MARK: - Method Chaining Tests

  @Test("Builder supports method chaining")
  func builderMethodChaining() {
    let config = makeConfigurationBuilder()
      .setTitle("Chained Title")
      .setContent("<p>Chained content</p>")
      .setPostID(456)
      .setShouldUsePlugins(true)
      .setShouldUseThemeStyles(true)
      .setLocale("de_DE")
      .setLogLevel(.info)
      .build()

    #expect(config.title == "Chained Title")
    #expect(config.content == "<p>Chained content</p>")
    #expect(config.postID == 456)
    #expect(config.shouldUsePlugins == true)
    #expect(config.shouldUseThemeStyles == true)
    #expect(config.locale == "de_DE")
    #expect(config.logLevel == .info)
  }

  // MARK: - Builder Immutability Tests
  @Test("Builder setters return new instance without modifying original")
  func builderSettersReturnNewInstance() {
    let builder1 = makeConfigurationBuilder()
    let builder2 = builder1.setTitle("New Title")

    let config1 = builder1.build()
    let config2 = builder2.build()

    #expect(config1.title == "")
    #expect(config2.title == "New Title")
  }

  @Test("Multiple builds from same builder produce equal configs")
  func multipleBuildsSameBuilder() {
    let builder = makeConfigurationBuilder().setTitle("Test")

    let config1 = builder.build()
    let config2 = builder.build()

    #expect(config1 == config2)
  }

  // MARK: - apply() Conditional Method Tests
  @Test("apply with non-nil value applies closure")
  func applyWithNonNilValue() {
    let postID: Int? = 123
    let config = makeConfigurationBuilder()
      .apply(postID) { builder, value in builder.setPostID(value) }
      .build()

    #expect(config.postID == 123)
  }

  @Test("apply with nil value skips closure")
  func applyWithNilValue() {
    let postID: Int? = nil
    let config = makeConfigurationBuilder()
      .apply(postID) {
        #expect(Bool(false), "This callback should never be invoked")
        return $0.setPostID($1)
      }
      .build()

    #expect(config.postID == nil)
  }

  @Test("apply can be chained multiple times")
  func applyChainedMultipleTimes() {
    let postID: Int? = 42
    let title: String? = "Applied Title"
    let content: String? = nil

    let config = makeConfigurationBuilder()
      .apply(postID) { $0.setPostID($1) }
      .apply(title) { $0.setTitle($1) }
      .apply(content) { $0.setContent($1) }
      .build()

    #expect(config.postID == 42)
    #expect(config.title == "Applied Title")
    #expect(config.content == "")
  }

  // MARK: - toBuilder Round-Trip Tests
  @Test("toBuilder preserves all configuration values")
  func toBuilderRoundTrip() {
    let original = makeConfigurationBuilder()
      .setTitle("Round Trip Title")
      .setContent("<p>Round trip content</p>")
      .setPostID(789)
      .setPostStatus("publish")
      .setShouldUseThemeStyles(true)
      .setShouldUsePlugins(true)
      .setShouldHideTitle(true)
      .setSiteApiNamespace(["wp/v2"])
      .setNamespaceExcludedPaths(["/oembed"])
      .setAuthHeader("Bearer abc")
      .setEditorSettings("{}")
      .setLocale("ja_JP")
      .setNativeInserterEnabled(true)
      .setLogLevel(.debug)
      .setEnableNetworkLogging(true)
      .build()

    #expect(original.toBuilder().build() == original)
  }

  @Test("toBuilder allows modification of existing config")
  func toBuilderAllowsModification() {
    let original = makeConfigurationBuilder()
      .setTitle("Original Title")
      .setPostID(100)
      .build()

    let modified = original.toBuilder()
      .setTitle("Modified Title")
      .build()

    #expect(original.title == "Original Title")
    #expect(modified.title == "Modified Title")
    #expect(modified.postID == 100)
  }
}

@Suite
struct EditorConfigurationTests: MakesTestFixtures {

  // MARK: - Test Fixtures
  static let testSiteURL = URL(string: "https://example.com")!
  static let testApiRoot = URL(string: "https://example.com/wp-json")!

  // MARK: - siteId Derivation Tests
  @Test("siteId extracts host from siteURL")
  func siteIdExtractsHost() {
    #expect(
      makeConfiguration(siteURL: URL(string: "https://example.com/path/to/site")!).siteId
        == "example.com")
  }

  @Test("siteId handles subdomain")
  func siteIdHandlesSubdomain() {
    #expect(
      makeConfiguration(siteURL: URL(string: "https://blog.example.com")!).siteId
        == "blog.example.com")
  }

  @Test("siteId handles deep subdomain")
  func siteIdHandlesDeepSubdomain() {
    #expect(
      makeConfiguration(siteURL: URL(string: "https://dev.blog.example.com")!).siteId
        == "dev.blog.example.com")
  }

  @Test("siteId handles internationalized domain")
  func siteIdHandlesInternationalizedDomain() {
    // URL converts IDN to punycode
    #expect(makeConfiguration(siteURL: URL(string: "https://例え.jp")!).siteId == "xn--r8jz45g.jp")
  }

  @Test("siteId handles localhost")
  func siteIdHandlesLocalhost() {
    #expect(
      makeConfiguration(siteURL: URL(string: "http://localhost:8080/wordpress")!).siteId
        == "localhost")
  }

  @Test("siteId handles IP address")
  func siteIdHandlesIPAddress() {
    #expect(
      makeConfiguration(siteURL: URL(string: "http://192.168.1.1/wordpress")!).siteId
        == "192.168.1.1")
  }

  // MARK: - escapedTitle Tests

  @Test("escapedTitle percent-encodes spaces")
  func escapedTitleEncodesSpaces() {
    #expect(makeConfiguration(title: "Hello World").escapedTitle == "Hello%20World")
  }

  @Test("escapedTitle percent-encodes special characters")
  func escapedTitleEncodesSpecialChars() {
    #expect(
      makeConfiguration(title: "Title with & and ?").escapedTitle
        == "Title%20with%20%26%20and%20%3F")
  }

  @Test("escapedTitle percent-encodes unicode")
  func escapedTitleEncodesUnicode() {
    #expect(
      makeConfiguration(title: "こんにちは").escapedTitle
        == "%E3%81%93%E3%82%93%E3%81%AB%E3%81%A1%E3%81%AF")
  }

  @Test("escapedTitle handles empty string")
  func escapedTitleHandlesEmpty() {
    #expect(makeConfiguration(title: "").escapedTitle == "")
  }

  @Test("escapedTitle preserves alphanumeric characters")
  func escapedTitlePreservesAlphanumeric() {
    #expect(makeConfiguration(title: "Title123").escapedTitle == "Title123")
  }

  // MARK: - escapedContent Tests
  @Test("escapedContent percent-encodes HTML")
  func escapedContentEncodesHTML() {
    #expect(makeConfiguration(content: "<p>Test</p>").escapedContent == "%3Cp%3ETest%3C%2Fp%3E")
  }

  @Test("escapedContent percent-encodes complex HTML")
  func escapedContentEncodesComplexHTML() {
    #expect(
      makeConfiguration(content: #"<div class="test">Content</div>"#).escapedContent
        == "%3Cdiv%20class%3D%22test%22%3EContent%3C%2Fdiv%3E")
  }

  @Test("escapedContent handles empty string")
  func escapedContentHandlesEmpty() {
    #expect(makeConfiguration(content: "").escapedContent == "")
  }

  @Test("escapedContent handles plain text")
  func escapedContentHandlesPlainText() {
    #expect(makeConfiguration(content: "Just plain text").escapedContent == "Just%20plain%20text")
  }

  // MARK: - Equatable Tests

  @Test("Configurations with same values are equal")
  func equalConfigurationsAreEqual() {
    let config1 = makeConfiguration(title: "Test", content: "<p>Content</p>")
    let config2 = makeConfiguration(title: "Test", content: "<p>Content</p>")

    #expect(config1 == config2)
  }

  @Test("Configurations with different title are not equal")
  func differentTitleNotEqual() {
    let config1 = makeConfiguration(title: "Title 1")
    let config2 = makeConfiguration(title: "Title 2")

    #expect(config1 != config2)
  }

  @Test("Configurations with different content are not equal")
  func differentContentNotEqual() {
    let config1 = makeConfiguration(content: "Content 1")
    let config2 = makeConfiguration(content: "Content 2")

    #expect(config1 != config2)
  }

  @Test("Configurations with different postID are not equal")
  func differentPostIDNotEqual() {
    let config1 = EditorConfigurationBuilder(
      postType: .post,
      siteURL: Self.testSiteURL,
      siteApiRoot: Self.testApiRoot
    ).setPostID(1).build()

    let config2 = EditorConfigurationBuilder(
      postType: .post,
      siteURL: Self.testSiteURL,
      siteApiRoot: Self.testApiRoot
    ).setPostID(2).build()

    #expect(config1 != config2)
  }

  @Test("Configurations with different siteURL are not equal")
  func differentSiteURLNotEqual() {
    let config1 = makeConfiguration(siteURL: URL(string: "https://site1.com")!)
    let config2 = makeConfiguration(siteURL: URL(string: "https://site2.com")!)

    #expect(config1 != config2)
  }

  // MARK: - Hashable Tests

  @Test("Identical configurations have same hash")
  func identicalConfigsHaveSameHash() {
    let config1 = makeConfiguration(title: "Test", content: "Content")
    let config2 = makeConfiguration(title: "Test", content: "Content")

    #expect(config1.hashValue == config2.hashValue)
  }

  @Test("Configurations can be used in Set")
  func configurationsCanBeUsedInSet() {
    let config1 = EditorConfigurationBuilder(
      postType: .post,
      siteURL: Self.testSiteURL,
      siteApiRoot: Self.testApiRoot
    ).setPostID(1).build()

    let config2 = EditorConfigurationBuilder(
      postType: .post,
      siteURL: Self.testSiteURL,
      siteApiRoot: Self.testApiRoot
    ).setPostID(2).build()

    let config3 = EditorConfigurationBuilder(
      postType: .post,
      siteURL: Self.testSiteURL,
      siteApiRoot: Self.testApiRoot
    ).setPostID(1).build()

    let set: Set<EditorConfiguration> = [config1, config2, config3]

    #expect(set.count == 2)
  }

  @Test("Configuration can be used as dictionary key")
  func configurationCanBeUsedAsDictionaryKey() {
    let config1 = makeConfiguration(title: "Key 1")
    let config2 = makeConfiguration(title: "Key 2")

    var dict: [EditorConfiguration: String] = [:]
    dict[config1] = "Value 1"
    dict[config2] = "Value 2"

    #expect(dict[config1] == "Value 1")
    #expect(dict[config2] == "Value 2")
  }
}
