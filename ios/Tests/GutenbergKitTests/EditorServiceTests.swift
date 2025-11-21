import Foundation
import Testing
@testable import GutenbergKit

@Suite("Editor Service Tests")
struct EditorServiceTests {

    @Test("Successfully loads editor dependencies")
    func successfullyLoadsDependencies() async throws {
        let context = try TestContext(manifestResource: "manifest-test-case-2")
        context.session.mockSettings()
        context.session.mockManifest(context.manifestData)
        context.session.mockAllAssets(context.assetURLs)

        let service = context.createService()
        let configuration = context.createConfiguration()

        // WHEN
        let dependencies = await service.dependencies(for: configuration)

        // THEN dependencies are loaded and editor settings are returned as is
        #expect(dependencies.editorSettings == #"{"alignWide": true}"#)

        // THEN processed manifest contains links pointing to files on disk (`gbk-cache-https://`)
        let manifest = try #require(dependencies.manifest)
        #expect(manifest.contains(#"link rel=\"stylesheet\" id=\"jp-forms-blocks-css\" href=\"gbk-cache-https:\/\/example.com\/wp-content\/plugins\/jetpack\/jetpack_vendor\/automattic\/jetpack-forms\/dist\/blocks\/editor.css?ver=13.9\"#))

        // THEN assets are available on disk and can be loaded
        for assetURL in context.assetURLs {
            let cachedURL = try #require(CachedAssetSchemeHandler.cachedURL(forWebLink: assetURL))
            let gbkURL = try #require(URL(string: cachedURL))
            let (response, data) = try await service.getCachedAsset(from: gbkURL)
            #expect(response.url == gbkURL)
            #expect(!data.isEmpty)
        }
    }

    @Test("Loads settings but not manifest when asset download fails")
    func loadsSettingsWhenAssetFails() async throws {
        let context = try TestContext(manifestResource: "manifest-test-case-2")
        context.session.mockSettings()
        context.session.mockManifest(context.manifestData)
        context.session.mockAllAssets(Array(context.assetURLs[0...1]))
        context.session.mockFailedAssets(Array(context.assetURLs[2...4]))

        let service = context.createService()
        let configuration = context.createConfiguration()

        let dependencies = await service.dependencies(for: configuration)

        // THEN settings are loaded but manifest is ignored – we cam't guarantee
        // it will work with missing resources
        #expect(dependencies.editorSettings == #"{"alignWide": true}"#)
        #expect(dependencies.manifest == nil)
    }

    @Test("Upgrades manifest and assets when version changes")
    func upgradesManifestOnVersionChange() async throws {
        let context = try TestContext(manifestResource: "manifest-test-case-2")
        context.session.mockSettings()
        context.session.mockManifest(context.manifestData)
        context.session.mockAllAssets(context.assetURLs)

        let service = context.createService()
        let configuration = context.createConfiguration()

        let initialDependencies = await service.dependencies(for: configuration)
        #expect(initialDependencies.manifest?.contains("ver=13.9") == true)

        // WHEN new manifest is returned with updated assets
        let upgradedContext = try TestContext(manifestResource: "manifest-test-case-3")
        context.session.mockManifest(upgradedContext.manifestData)
        context.session.mockAllAssets(upgradedContext.assetURLs)

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

        // THEN upgraded assets are available on disk
        for assetURL in upgradedContext.assetURLs {
            let cachedURL = try #require(CachedAssetSchemeHandler.cachedURL(forWebLink: assetURL))
            let gbkURL = try #require(URL(string: cachedURL))
            let (response, data) = try await service.getCachedAsset(from: gbkURL)
            #expect(response.url == gbkURL)
            #expect(!data.isEmpty)
        }
    }

    @Test("Cleans up orphaned assets after upgrade")
    func cleansUpOrphanedAssets() async throws {
        let context = try TestContext(manifestResource: "manifest-test-case-2")
        context.session.mockSettings()
        context.session.mockManifest(context.manifestData)
        context.session.mockAllAssets(context.assetURLs)

        let service = context.createService()
        let configuration = context.createConfiguration()

        // Load initial v13.9 dependencies
        _ = await service.dependencies(for: configuration)

        // Verify all v13.9 assets exist on disk
        let assetsDir = context.testDir.appendingPathComponent("assets")
        let initialFiles = try FileManager.default.contentsOfDirectory(atPath: assetsDir.path)
        #expect(initialFiles.count == 5) // All 5 v13.9 assets

        // Upgrade to v14.0 (which removes slideshow, upgrades forms, adds ai-assistant)
        let upgradedContext = try TestContext(manifestResource: "manifest-test-case-3")
        context.session.mockManifest(upgradedContext.manifestData)
        context.session.mockAllAssets(upgradedContext.assetURLs)
        context.makeStateFileOld()
        await service.refresh(configuration: configuration)

        // Run cleanup
        try await service.cleanupOrphanedAssets()

        // Verify orphaned assets (slideshow v13.9, old versions) are deleted
        let filesAfterCleanup = try FileManager.default.contentsOfDirectory(atPath: assetsDir.path)
        #expect(filesAfterCleanup.count == 4) // Only 4 v14.0 assets remain

        // Verify slideshow assets are gone
        let slideshowFilename = service.cachedFilename(for: "https://example.com/wp-content/plugins/jetpack/_inc/blocks/slideshow/editor.js?ver=13.9")
        #expect(!filesAfterCleanup.contains(slideshowFilename))

        // Verify v14.0 assets are retained
        for assetURL in upgradedContext.assetURLs {
            let filename = service.cachedFilename(for: assetURL)
            #expect(filesAfterCleanup.contains(filename))
        }
    }
}

// MARK: - Test Helpers

private struct TestContext {
    let session = MockURLSession()
    let testDir: URL
    let manifestData: Data
    let assetURLs: [String]

    init(manifestResource: String) throws {
        let manifestURL = Bundle.module.url(forResource: manifestResource, withExtension: "json")!
        self.manifestData = try Data(contentsOf: manifestURL)

        let manifest = try JSONDecoder().decode(EditorAssetsManifest.self, from: manifestData)
        self.assetURLs = try manifest.parseAssetLinks()

        self.testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
    }

    func createService() -> EditorService {
        EditorService(siteURL: "https://example.com", storeURL: testDir, networkSession: session)
    }

    func createConfiguration() -> EditorConfiguration {
        EditorConfigurationBuilder()
            .setSiteUrl("https://example.com")
            .setSiteApiRoot("https://example.com")
            .setAuthHeader("Bearer test-token")
            .build()
    }

    func makeStateFileOld() {
        let stateFileURL = testDir.appendingPathComponent("state.json")
        let oldDate = Date().addingTimeInterval(-31) // 31 seconds ago
        let state = EditorService.State(refreshDate: oldDate)
        try? JSONEncoder().encode(state).write(to: stateFileURL)
    }
}

private extension MockURLSession {
    func mockSettings() {
        mockResponse(
            for: "https://example.com/wp-block-editor/v1/settings",
            data: """
            {"alignWide": true}
            """.data(using: .utf8)!,
            statusCode: 200
        )
    }

    func mockManifest(_ data: Data) {
        mockResponse(
            for: "https://example.com/wpcom/v2/editor-assets?exclude=core,gutenberg",
            data: data,
            statusCode: 200
        )
    }

    func mockAllAssets(_ assetURLs: [String]) {
        for assetURL in assetURLs {
            mockResponse(
                for: assetURL,
                data: assetURL.data(using: .utf8)!,
                statusCode: 200
            )
        }
    }

    func mockFailedAssets(_ assetURLs: [String]) {
        for assetURL in assetURLs {
            mockResponse(for: assetURL, data: Data(), statusCode: 404)
        }
    }
}
