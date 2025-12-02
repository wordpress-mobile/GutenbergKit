import Foundation
import Testing
@testable import GutenbergKit

@Suite("Editor Configuration Builder Tests")
struct EditorConfigurationBuilderTests {

    @Test("Editor Configuration Defaults Are Correct")
    func testThatEditorConfigurationBuilderDefaultsAreCorrect() throws {
        let builder = EditorConfigurationBuilder().build()
        #expect(builder.title == "")
        #expect(builder.content == "")
        #expect(builder.postID == nil)
        #expect(builder.postType == nil)
        #expect(builder.shouldUseThemeStyles == false)
        #expect(builder.shouldUsePlugins == false)
        #expect(builder.shouldHideTitle == false)
        #expect(builder.siteURL == "")
        #expect(builder.siteApiRoot == "")
        #expect(builder.siteApiNamespace == [])
        #expect(builder.namespaceExcludedPaths == [])
        #expect(builder.authHeader == "")
        #expect(builder.locale == "en")
        #expect(builder.editorAssetsEndpoint == nil)
        #expect(builder.isNativeInserterEnabled == false)
        #expect(builder.logLevel == .error)
        #expect(builder.enableNetworkLogging == false)
    }

    @Test("Editor Configuration to Builder")
    func testThatEditorConfigurationToBuilder() throws {
        let configuration = EditorConfigurationBuilder()
            .setTitle("Title")
            .setContent("Content")
            .setPostID(123)
            .setPostType("Post")
            .setShouldUseThemeStyles(true)
            .setShouldUsePlugins(true)
            .setShouldHideTitle(true)
            .setSiteUrl("https://example.com")
            .setSiteApiRoot("/wp-json")
            .setSiteApiNamespace(["wp", "v2"])
            .setNamespaceExcludedPaths(["jetpack"])
            .setAuthHeader("Bearer Token")
            .setLocale("fr")
            .setEditorAssetsEndpoint(URL(string: "https://example.com/wp-content/plugins/gutenberg/build/"))
            .setNativeInserterEnabled(true)
            .setLogLevel(.debug)
            .setEnableNetworkLogging(true)
            .build()        // Convert to a configuration
            .toBuilder()    // Then back to a builder (to test the configuration->builder logic)
            .build()        // Then back to a configuration to examine the results

        #expect(configuration.title == "Title")
        #expect(configuration.content == "Content")
        #expect(configuration.postID == 123)
        #expect(configuration.postType == "Post")
        #expect(configuration.shouldUseThemeStyles == true)
        #expect(configuration.shouldUsePlugins == true)
        #expect(configuration.shouldHideTitle == true)
        #expect(configuration.siteURL == "https://example.com")
        #expect(configuration.siteApiRoot == "/wp-json")
        #expect(configuration.siteApiNamespace == ["wp", "v2"])
        #expect(configuration.namespaceExcludedPaths == ["jetpack"])
        #expect(configuration.authHeader == "Bearer Token")
        #expect(configuration.locale == "fr")
        #expect(configuration.editorAssetsEndpoint == URL(string: "https://example.com/wp-content/plugins/gutenberg/build/"))
        #expect(configuration.isNativeInserterEnabled == true)
        #expect(configuration.logLevel == .debug)
        #expect(configuration.enableNetworkLogging == true)
    }

    @Test("Sets Title Correctly")
    func editorConfigurationBuilderSetsTitleCorrectly() throws {
        #expect(EditorConfigurationBuilder().setTitle("Title").build().title == "Title")
    }

    @Test("Sets Content Correctly")
    func editorConfigurationBuilderSetsContentCorrectly() throws {
        #expect(EditorConfigurationBuilder().setContent("Content").build().content == "Content")
    }

    @Test("Sets PostID Correctly")
    func editorConfigurationBuilderSetsPostIDCorrectly() throws {
        #expect(EditorConfigurationBuilder().setPostID(nil).build().postID == nil)
        #expect(EditorConfigurationBuilder().setPostID(123).build().postID == 123)
    }

    @Test("Sets Post Type Correctly")
    func editorConfigurationBuilderSetsPostTypeCorrectly() throws {
        #expect(EditorConfigurationBuilder().setPostType(nil).build().postType == nil)
        #expect(EditorConfigurationBuilder().setPostType("post").build().postType == "post")
    }

    @Test("Sets shouldUseThemeStyles Correctly")
    func editorConfigurationBuilderSetsShouldUseThemeStylesCorrectly() throws {
        #expect(EditorConfigurationBuilder().setShouldUseThemeStyles(true).build().shouldUseThemeStyles)
        #expect(!EditorConfigurationBuilder().setShouldUseThemeStyles(false).build().shouldUseThemeStyles)
    }

    @Test("Sets shouldUsePlugins Correctly")
    func editorConfigurationBuilderSetsShouldUsePluginsCorrectly() throws {
        #expect(EditorConfigurationBuilder().setShouldUsePlugins(true).build().shouldUsePlugins)
        #expect(!EditorConfigurationBuilder().setShouldUsePlugins(false).build().shouldUsePlugins)
    }

    @Test("Sets shouldHideTitle Correctly")
    func editorConfigurationBuilderSetsShouldHideTitleCorrectly() throws {
        #expect(EditorConfigurationBuilder().setShouldHideTitle(true).build().shouldHideTitle)
        #expect(!EditorConfigurationBuilder().setShouldHideTitle(false).build().shouldHideTitle)
    }

    @Test("Sets siteUrl Correctly")
    func editorConfigurationBuilderSetsSiteUrlCorrectly() throws {
        #expect(EditorConfigurationBuilder().setSiteUrl("https://example.com").build().siteURL == "https://example.com")
    }

    @Test("Sets siteApiRoot Correctly")
    func editorConfigurationBuilderSetsSiteApiRootCorrectly() throws {
        #expect(EditorConfigurationBuilder().setSiteApiRoot("https://example.com/wp-json").build().siteApiRoot == "https://example.com/wp-json")
    }

    @Test("Sets siteApiNamespace Correctly")
    func editorConfigurationBuilderSetsApiNamespaceCorrectly() throws {
        #expect(EditorConfigurationBuilder().setSiteApiNamespace(["wp/v2"]).build().siteApiNamespace == ["wp/v2"])
    }

    @Test("Sets namespaceExcludedPaths Correctly")
    func editorConfigurationBuilderSetsNamespaceExcludedPathsCorrectly() throws {
        #expect(
            EditorConfigurationBuilder()
                .setNamespaceExcludedPaths(["/wp-admin", "/wp-login.php"])
                .build()
                .namespaceExcludedPaths
            == ["/wp-admin", "/wp-login.php"]
        )
    }

    @Test("Sets authHeader Correctly")
    func editorConfigurationBuilderSetsAuthHeaderCorrectly() throws {
        #expect(EditorConfigurationBuilder().setAuthHeader("Bearer token").build().authHeader == "Bearer token")
    }

    @Test("Sets locale Correctly")
    func editorConfigurationBuilderSetsLocaleCorrectly() throws {
        #expect(EditorConfigurationBuilder().setLocale("en").build().locale == "en")
    }

    @Test("Sets editorAssetsEndpoint Correctly")
    func editorConfigurationBuilderSetsEditorAssetsEndpointCorrectly() throws {
        #expect(EditorConfigurationBuilder().setEditorAssetsEndpoint(URL(string: "https://example.com/wp-content/plugins/gutenberg/build/")).build().editorAssetsEndpoint == URL(string: "https://example.com/wp-content/plugins/gutenberg/build/"))
    }

    @Test("Sets isNativeInserterEnabled Correctly")
    func editorConfigurationBuilderSetsNativeInserterEnabledCorrectly() throws {
        #expect(EditorConfigurationBuilder().setNativeInserterEnabled(true).build().isNativeInserterEnabled)
        #expect(!EditorConfigurationBuilder().setNativeInserterEnabled(false).build().isNativeInserterEnabled)
    }

    @Test("Sets logLevel Correctly")
    func editorConfigurationBuilderSetsLogLevelCorrectly() throws {
        #expect(EditorConfigurationBuilder().setLogLevel(.debug).build().logLevel == .debug)
        #expect(EditorConfigurationBuilder().setLogLevel(.info).build().logLevel == .info)
        #expect(EditorConfigurationBuilder().setLogLevel(.warn).build().logLevel == .warn)
        #expect(EditorConfigurationBuilder().setLogLevel(.error).build().logLevel == .error)
    }

    @Test("Sets enableNetworkLogging Correctly")
    func editorConfigurationBuilderSetsEnableNetworkLoggingCorrectly() throws {
        #expect(EditorConfigurationBuilder().setEnableNetworkLogging(true).build().enableNetworkLogging)
        #expect(!EditorConfigurationBuilder().setEnableNetworkLogging(false).build().enableNetworkLogging)
    }

    @Test("Applies values correctly")
    func editorConfigurationBuilderAppliesValuesCorrectly() throws {
        let string = "test"
        let nilString: String? = nil

        let int = 1
        let nilInt: Int? = nil

        #expect(EditorConfigurationBuilder().apply(string, { $0.setTitle($1) }).build().title == string)
        #expect(EditorConfigurationBuilder().apply(nilString, { $0.setTitle($1)}).build().title == "")

        #expect(EditorConfigurationBuilder().apply(int, { $0.setPostID($1) }).build().postID == int)
        #expect(EditorConfigurationBuilder().apply(nilInt, { $0.setPostID($1)}).build().postID == nil)
    }

    @Test("apply never calls the closure if the value is nil")
    func editorConfigurationBuilderApplyDoesNotCallClosureWithNilValue() throws {
        let string: String? = nil

        _ = EditorConfigurationBuilder().apply(string, { builder, value in
            Issue.record("Closure was called")
            return builder
        })
    }
}
