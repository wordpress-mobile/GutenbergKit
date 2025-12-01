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

        // THEN settings are loaded
        #expect(dependencies.editorSettings == #"{"alignWide": true}"#)
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
        #expect(initialDependencies.editorSettings == #"{"alignWide": true}"#)

        // WHEN new manifest is returned with updated assets
        let upgradedContext = try TestContext(manifestResource: "manifest-test-case-3")
        context.session.mockManifest(upgradedContext.manifestData)
        context.session.mockAllAssets(upgradedContext.assetURLs)

        // Force refresh with new manifest
        await service.refresh(configuration: configuration)

        let upgradedDependencies = await service.dependencies(for: configuration, isWarmup: true)

        // THEN settings are still available
        #expect(upgradedDependencies.editorSettings == #"{"alignWide": true}"#)

        // THEN upgraded assets are available on disk
        for assetURL in upgradedContext.assetURLs {
            let cachedURL = try #require(CachedAssetSchemeHandler.cachedURL(forWebLink: assetURL))
            let gbkURL = try #require(URL(string: cachedURL))
            let (response, data) = try await service.getCachedAsset(from: gbkURL)
            #expect(response.url == gbkURL)
            #expect(!data.isEmpty)
        }
    }

    @Test("Handles concurrent refresh requests correctly")
    func concurrentRefreshRequests() async throws {
        let context = try TestContext(manifestResource: "manifest-test-case-2")
        context.session.mockSettings()
        context.session.mockManifest(context.manifestData)
        context.session.mockAllAssets(context.assetURLs)

        let service = context.createService()
        let configuration = context.createConfiguration()

        // Trigger multiple refreshes concurrently
        async let refresh1: Void = service.refresh(configuration: configuration)
        async let refresh2: Void = service.refresh(configuration: configuration)
        async let refresh3: Void = service.refresh(configuration: configuration)

        _ = await (refresh1, refresh2, refresh3)

        // Verify network was only called once despite 3 refresh calls
        #expect(context.session.requestCount(for: "wp-block-editor/v1/settings") == 1)
        #expect(context.session.requestCount(for: "wpcom/v2/editor-assets") == 1)
    }

    @Test("Successfully loads cached asset from disk")
    func getCachedAssetSuccess() async throws {
        let context = try TestContext(manifestResource: "manifest-test-case-2")
        context.session.mockSettings()
        context.session.mockManifest(context.manifestData)
        context.session.mockAllAssets(context.assetURLs)

        let service = context.createService()
        let configuration = context.createConfiguration()

        // Load dependencies to cache assets
        _ = await service.dependencies(for: configuration)

        // Now try to load a cached asset
        let testAssetURL = context.assetURLs[0]
        let cachedURL = try #require(CachedAssetSchemeHandler.cachedURL(forWebLink: testAssetURL))
        let gbkURL = try #require(URL(string: cachedURL))

        let (response, data) = try await service.getCachedAsset(from: gbkURL)

        // Verify response
        #expect(response.url == gbkURL)
        #expect(!data.isEmpty)
        #expect(response.mimeType == "application/javascript")
    }

    @Test("Skips refresh when data is fresh (< 30s)")
    func refreshNotNeededWithin30Seconds() async throws {
        let context = try TestContext(manifestResource: "manifest-test-case-2")
        context.session.mockSettings()
        context.session.mockManifest(context.manifestData)
        context.session.mockAllAssets(context.assetURLs)

        let service = context.createService()
        let configuration = context.createConfiguration()

        // Initial load
        _ = await service.dependencies(for: configuration)

        // Wait briefly to allow background refresh task to start (but not complete 30s threshold)
        try await Task.sleep(for: .milliseconds(100))

        // Second load within 30 seconds with warmup flag - should not trigger refresh
        _ = await service.dependencies(for: configuration, isWarmup: true)

        // Wait to ensure background refresh logic has time to evaluate (but not execute)
        try await Task.sleep(for: .milliseconds(100))

        // Verify network was only called once
        #expect(context.session.requestCount(for: "wp-block-editor/v1/settings") == 1)
        #expect(context.session.requestCount(for: "wpcom/v2/editor-assets") == 1)
    }

    @Test("Handles invalid siteApiRoot URL gracefully")
    func invalidSiteApiRootURL() async throws {
        let context = try TestContext(manifestResource: "manifest-test-case-2")
        let service = context.createService()

        // Create configuration with invalid URL
        let configuration = EditorConfigurationBuilder()
            .setSiteUrl("https://example.com")
            .setSiteApiRoot("not a valid url!")
            .setAuthHeader("Bearer test-token")
            .build()

        // Should not crash, just log error and return empty dependencies
        let dependencies = await service.dependencies(for: configuration)

        // Dependencies should be empty since refresh failed
        #expect(dependencies.editorSettings == nil)
    }

    @Test("Returns error when cached asset doesn't exist")
    func getCachedAssetNotFound() async throws {
        let context = try TestContext(manifestResource: "manifest-test-case-2")
        let service = context.createService()

        // Try to load an asset that was never cached
        let fakeURL = URL(string: "gbk-cache-https://example.com/missing.js")!

        // Should throw file not found error
        await #expect(throws: URLError.self) {
            try await service.getCachedAsset(from: fakeURL)
        }
    }

    @Test("Successfully loads processed manifest")
    func getProcessedManifestSuccess() async throws {
        let context = try TestContext(manifestResource: "manifest-test-case-2")
        context.session.mockSettings()
        context.session.mockManifest(context.manifestData)
        context.session.mockAllAssets(context.assetURLs)

        let service = context.createService()
        let configuration = context.createConfiguration()

        // Load dependencies to create and cache the processed manifest
        _ = await service.dependencies(for: configuration)

        // Now get the processed manifest
        let manifest = try await service.getProcessedManifest()

        // Verify manifest is valid JSON string
        #expect(!manifest.isEmpty)

        // Verify it contains gbk-cache scheme URLs (processed format)
        #expect(manifest.contains("gbk-cache-https:"))

        // Verify it contains expected asset references
        #expect(manifest.contains("jetpack"))
    }

    @Test("Returns error when processed manifest doesn't exist")
    func getProcessedManifestNotFound() async throws {
        let context = try TestContext(manifestResource: "manifest-test-case-2")
        let service = context.createService()

        // Try to get manifest before it's been created
        await #expect(throws: Error.self) {
            try await service.getProcessedManifest()
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
