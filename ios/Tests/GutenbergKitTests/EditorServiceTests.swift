import Foundation
import Testing
@testable import GutenbergKit

@Suite("Editor Service Tests")
struct EditorServiceTests {

    let manifestData: Data = {
        let manifestURL = Bundle.module.url(forResource: "manifest-test-case-2", withExtension: "json")!
        return try! Data(contentsOf: manifestURL)
    }()

    let assetURLs: [String] = [
        "https://example.com/wp-content/plugins/jetpack/modules/videopress/js/videopress-token-bridge.js?ver=13.9",
        "https://example.com/wp-content/plugins/jetpack/_inc/blocks/contact-form/editor.js?ver=13.9",
        "https://example.com/wp-content/plugins/jetpack/_inc/blocks/slideshow/editor.js?ver=13.9",
        "https://example.com/wp-content/plugins/jetpack/jetpack_vendor/automattic/jetpack-forms/dist/blocks/editor.css?ver=13.9",
        "https://example.com/wp-content/plugins/jetpack/_inc/blocks/editor.css?ver=13.9"
    ]

    @Test("Successfully loads editor dependencies")
    func successfullyLoadsDependencies() async throws {
        let session = MockURLSession()

        session.mockResponse(
            for: "https://example.com/wp-block-editor/v1/settings",
            data: """
            {"alignWide": true}
            """.data(using: .utf8)!,
            statusCode: 200
        )

        session.mockResponse(
            for: "https://example.com/wpcom/v2/editor-assets?exclude=core,gutenberg",
            data: manifestData,
            statusCode: 200
        )

        for assetURL in assetURLs {
            session.mockSuccessfulResponse(forAssetURL: assetURL)
        }

        let testDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        let service = EditorService(siteURL: "https://example.com", storeURL: testDir, networkSession: session)
        let configuration = EditorConfigurationBuilder()
            .setSiteUrl("https://example.com")
            .setSiteApiRoot("https://example.com")
            .setAuthHeader("Bearer test-token")
            .build()

        // WHEN
        let dependencies = await service.dependencies(for: configuration)

        // THEN dependencies are loaded and editor settings are returned as is
        #expect(dependencies.editorSettings == #"{"alignWide": true}"#)

        // THEN processed manifest contains links pointing to files on disk (`gbk-cache-https://`)
        let manifest = try #require(dependencies.manifest)
        #expect(manifest.contains(#"link rel=\"stylesheet\" id=\"jp-forms-blocks-css\" href=\"gbk-cache-https:\/\/example.com\/wp-content\/plugins\/jetpack\/jetpack_vendor\/automattic\/jetpack-forms\/dist\/blocks\/editor.css?ver=13.9\"#))
    }

    @Test("Loads settings but not manifest when asset download fails")
    func loadsSettingsWhenAssetFails() async throws {

        // GIVEN one of the asset fails to load
        let session = MockURLSession()

        session.mockResponse(
            for: "https://example.com/wp-block-editor/v1/settings",
            data: """
            {"alignWide": true}
            """.data(using: .utf8)!,
            statusCode: 200
        )

        session.mockResponse(
            for: "https://example.com/wpcom/v2/editor-assets?exclude=core,gutenberg",
            data: manifestData,
            statusCode: 200
        )

        for assetURL in assetURLs[0...1] {
            session.mockSuccessfulResponse(forAssetURL: assetURL)
        }
        for assetURL in assetURLs[2...4] {
            session.mockResponse(for: assetURL, data: Data(), statusCode: 404)
        }

        let testDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        let service = EditorService(siteURL: "https://example.com", storeURL: testDir, networkSession: session)
        let configuration = EditorConfigurationBuilder()
            .setSiteUrl("https://example.com")
            .setSiteApiRoot("https://example.com")
            .setAuthHeader("Bearer test-token")
            .build()

        let dependencies = await service.dependencies(for: configuration)

        // THEN settings are loaded but manifest is ignored – we cam't guarantee
        // it will work with missing resources
        #expect(dependencies.editorSettings == #"{"alignWide": true}"#)
        #expect(dependencies.manifest == nil)
    }

    @Test("Upgrades manifest and assets when version changes")
    func upgradesManifestOnVersionChange() async throws {
        let session = MockURLSession()

        session.mockResponse(
            for: "https://example.com/wp-block-editor/v1/settings",
            data: """
            {"alignWide": true}
            """.data(using: .utf8)!,
            statusCode: 200
        )

        // GIVEN initial manifest is loaded with v13.9 assets
        session.mockResponse(
            for: "https://example.com/wpcom/v2/editor-assets?exclude=core,gutenberg",
            data: manifestData,
            statusCode: 200
        )

        for assetURL in assetURLs {
            session.mockSuccessfulResponse(forAssetURL: assetURL)
        }

        let testDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        let service = EditorService(siteURL: "https://example.com", storeURL: testDir, networkSession: session)
        let configuration = EditorConfigurationBuilder()
            .setSiteUrl("https://example.com")
            .setSiteApiRoot("https://example.com")
            .setAuthHeader("Bearer test-token")
            .build()

        let initialDependencies = await service.dependencies(for: configuration)
        #expect(initialDependencies.manifest?.contains("ver=13.9") == true)

        // WHEN new manifest is returned with updated assets
        let upgradedManifestURL = Bundle.module.url(forResource: "manifest-test-case-3", withExtension: "json")!
        let upgradedManifestData = try Data(contentsOf: upgradedManifestURL)

        session.mockResponse(
            for: "https://example.com/wpcom/v2/editor-assets?exclude=core,gutenberg",
            data: upgradedManifestData,
            statusCode: 200
        )

        // Mock new v14.0 assets (slideshow removed, forms upgraded, ai-assistant added)
        let upgradedAssetURLs = [
            "https://example.com/wp-content/plugins/jetpack/modules/videopress/js/videopress-token-bridge.js?ver=14.0",
            "https://example.com/wp-content/plugins/jetpack/_inc/blocks/contact-form/editor.js?ver=14.0",
            "https://example.com/wp-content/plugins/jetpack/jetpack_vendor/automattic/jetpack-forms/dist/blocks/editor.css?ver=14.0",
            "https://example.com/wp-content/plugins/jetpack/_inc/blocks/ai-assistant/editor.css?ver=14.0"
        ]

        for assetURL in upgradedAssetURLs {
            session.mockSuccessfulResponse(forAssetURL: assetURL)
        }

        // Make state file old enough to bypass 30s throttle
        let stateFileURL = testDir.appendingPathComponent("state.json")
        let oldState = EditorService.State(refreshDate: Date().addingTimeInterval(-31))
        try JSONEncoder().encode(oldState).write(to: stateFileURL)

        // Force refresh with new manifest
        await service.refresh(configuration: configuration)

        let upgradedDependencies = await service.dependencies(for: configuration, isWarmup: true)

        // THEN manifest is upgraded to v14.0
        let upgradedManifest = try #require(upgradedDependencies.manifest)
        #expect(upgradedManifest.contains("ver=14.0"))
        #expect(!upgradedManifest.contains("ver=13.9"))

        // THEN new asset is present (ai-assistant)
        #expect(upgradedManifest.contains("ai-assistant"))

        // THEN removed asset is not present (slideshow)
        #expect(!upgradedManifest.contains("slideshow"))

        // THEN upgraded asset has new version (contact-form)
        #expect(upgradedManifest.contains(#"jetpack\/_inc\/blocks\/contact-form\/editor.js?ver=14.0"#))
    }
}

private extension MockURLSession {
    func mockSuccessfulResponse(forAssetURL assetURL: String) {
        mockResponse(
            for: assetURL,
            data: assetURL.data(using: .utf8)!,
            statusCode: 200
        )
    }
}
