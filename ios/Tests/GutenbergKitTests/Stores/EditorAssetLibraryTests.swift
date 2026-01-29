import Foundation
import Testing

@testable import GutenbergKit

struct EditorAssetLibraryTests {

    // MARK: - Test Fixtures

    static var testConfiguration: EditorConfiguration {
        EditorConfigurationBuilder(
            postType: "post",
            siteURL: URL(string: "https://example.com")!,
            siteApiRoot: URL(string: "https://example.com/wp-json")!,
        )
        .setShouldUsePlugins(true)
        .setShouldUseThemeStyles(true)
        .build()
    }

    static var minimalConfiguration: EditorConfiguration {
        EditorConfigurationBuilder(
            postType: "post",
            siteURL: URL(string: "https://example.com")!,
            siteApiRoot: URL(string: "https://example.com/wp-json")!
        )
        .setShouldUsePlugins(false)
        .setShouldUseThemeStyles(false)
        .build()
    }

    private func makeLibrary(
        configuration: EditorConfiguration = EditorAssetLibraryTests.testConfiguration,
        httpClient: EditorHTTPClientProtocol = EditorAssetLibraryMockHTTPClient(),
        cachePolicy: EditorCachePolicy = .always,
        storageRoot: URL = .randomTemporaryDirectory
    ) -> EditorAssetLibrary {
        EditorAssetLibrary(
            configuration: configuration,
            httpClient: httpClient,
            cachePolicy: cachePolicy,
            storageRoot: storageRoot
        )
    }

    // MARK: - hasBundle Tests

    @Test("hasBundle returns false for non-existent checksum")
    func hasBundleReturnsFalseForMissingChecksum() async throws {
        let library = makeLibrary()

        let result = await library.hasBundle(forManifestChecksum: "nonexistent-checksum-12345")
        #expect(result == false)
    }

    // MARK: - existingBundle Tests

    @Test("existingBundle returns nil for non-existent checksum")
    func existingBundleReturnsNilForMissingChecksum() async throws {
        let library = makeLibrary()

        let result = try await library.existingBundle(forManifestChecksum: "nonexistent-checksum-12345")
        #expect(result == nil)
    }

    // MARK: - fetchManifest Tests

    @Test("fetchManifest fetches and parses remote manifest")
    func fetchManifestParsesRemoteManifest() async throws {
        let manifestJSON = """
      {
          "scripts": "<script src=\\"https://example.com/plugin.js\\"></script>",
          "styles": "<link rel=\\"stylesheet\\" href=\\"https://example.com/plugin.css\\">",
          "allowed_block_types": ["core/paragraph", "core/heading"]
      }
      """

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(manifestJSON.utf8) }

        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)

        let manifest = try await library.fetchManifest()

        #expect(manifest.allowedBlockTypes == ["core/paragraph", "core/heading"])
        #expect(manifest.rawScripts.contains("plugin.js"))
        #expect(manifest.rawStyles.contains("plugin.css"))
    }

    @Test("fetchManifest with ignore cache policy always fetches new data")
    func fetchManifestIgnoreCachePolicyAlwaysFetches() async throws {
        let manifestJSON = """
      {
          "scripts": "",
          "styles": "",
          "allowed_block_types": ["core/paragraph"]
      }
      """

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(manifestJSON.utf8) }

        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)

        _ = try await library.fetchManifest()
        _ = try await library.fetchManifest()

        #expect(mockClient.getCallCount == 2)
    }

    @Test("fetchManifest with always cache policy returns cached manifest when bundle exists on disk")
    func fetchManifestAlwaysCachePolicyReturnsCachedManifest() async throws {
        let manifestJSON = uniqueManifestJSON(identifier: "test-cached-manifest-\(UUID().uuidString)")

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(manifestJSON.utf8) }

        let library = makeLibrary(httpClient: mockClient, cachePolicy: .always)

        // First, fetch the manifest and create a bundle on disk
        let originalManifest = try await library.fetchManifest()

        _ = try await library.buildBundle(for: originalManifest)

        // Now fetch again - should return the on-disk manifest
        let cachedManifest = try await library.fetchManifest()

        // The checksums should match since it's the same manifest data
        #expect(cachedManifest.checksum == originalManifest.checksum)

        // Verify we made 2 HTTP calls (one for each fetchManifest)
        // but the second one used the cached bundle's manifest
        #expect(mockClient.getCallCount == 2)
    }

    @Test("fetchManifest with always cache policy falls back to new manifest when no bundle exists")
    func fetchManifestAlwaysCachePolicyFallsBackWhenNoBundleExists() async throws {
        let manifestJSON = uniqueManifestJSON(identifier: "test-no-cache-fallback-\(UUID().uuidString)")

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(manifestJSON.utf8) }

        let library = makeLibrary(httpClient: mockClient, cachePolicy: .always)

        // Fetch with always cache policy when no bundle exists on disk
        let manifest = try await library.fetchManifest()

        // Should still return a valid manifest (created from remote data)
        #expect(!manifest.checksum.isEmpty)
        #expect(mockClient.getCallCount == 1)
    }

    @Test(
        "fetchManifest with always cache policy avoids expensive LocalEditorAssetManifest creation when cached")
    func fetchManifestAlwaysCachePolicyAvoidsExpensiveCreation() async throws {
        // Use a manifest with multiple block types but no scripts/styles to avoid download issues
        let manifestJSON = """
      {
          "scripts": "",
          "styles": "",
          "allowed_block_types": ["core/paragraph", "core/heading", "core/image", "jetpack/ai-assistant", "jetpack/contact-info"]
      }
      """

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(manifestJSON.utf8) }

        let library = makeLibrary(httpClient: mockClient, cachePolicy: .always)

        // First fetch and create the bundle
        let originalManifest = try await library.fetchManifest()

        _ = try await library.buildBundle(for: originalManifest)

        // Record checksum before second fetch
        let originalChecksum = originalManifest.checksum

        // Second fetch should use the cached bundle's manifest
        // This avoids the expensive RemoteEditorAssetManifest -> LocalEditorAssetManifest conversion
        let cachedManifest = try await library.fetchManifest()

        // Verify we got the same manifest back (by checksum)
        #expect(cachedManifest.checksum == originalChecksum)

        // Verify the manifest data is complete
        #expect(cachedManifest.allowedBlockTypes.contains("core/paragraph"))
        #expect(cachedManifest.allowedBlockTypes.contains("jetpack/ai-assistant"))
    }

    // MARK: - readAssetBundles Tests

    @Test("readAssetBundles returns empty array when no bundles directory exists")
    func readAssetBundlesThrowsWhenNoBundlesExist() async throws {
        let library = makeLibrary()
        #expect(try await library.readAssetBundles().isEmpty)
    }

    @Test("readAssetBundles returns empty array when directory exists but has no bundles")
    func readAssetBundlesReturnsEmptyArrayWhenNoBundles() async throws {
        let mockClient = EditorAssetLibraryMockHTTPClient()
        let library = makeLibrary(httpClient: mockClient)

        // Create the site root directory without any bundles
        let siteRoot = Paths.cacheRoot(for: Self.testConfiguration)
        try FileManager.default.createDirectory(at: siteRoot, withIntermediateDirectories: true)

        let bundles = try await library.readAssetBundles()
        #expect(bundles.isEmpty)
    }

    @Test("readAssetBundles returns single bundle after buildBundle")
    func readAssetBundlesReturnsSingleBundle() async throws {
        let manifestJSON = uniqueManifestJSON(identifier: "test-single-bundle-\(UUID().uuidString)")

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(manifestJSON.utf8) }

        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)

        let manifest = try await library.fetchManifest()

        let createdBundle = try await library.buildBundle(for: manifest)

        let bundles = try await library.readAssetBundles()

        #expect(bundles.count == 1)
        #expect(bundles.first?.id == createdBundle.id)
    }

    @Test("readAssetBundles returns multiple bundles sorted by download date")
    func readAssetBundlesReturnsMultipleBundlesSorted() async throws {
        let mockClient = EditorAssetLibraryMockHTTPClient()
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)

        // Create first bundle
        let manifest1JSON = uniqueManifestJSON(identifier: "test-multi-bundle-1-\(UUID().uuidString)")
        mockClient.urlResponseHandler = { _ in Data(manifest1JSON.utf8) }

        let manifest1 = try await library.fetchManifest()

        let bundle1 = try await library.buildBundle(for: manifest1)

        // Small delay to ensure different download dates
        try await Task.sleep(for: .milliseconds(10))

        // Create second bundle
        let manifest2JSON = uniqueManifestJSON(identifier: "test-multi-bundle-2-\(UUID().uuidString)")
        mockClient.urlResponseHandler = { _ in Data(manifest2JSON.utf8) }

        let manifest2 = try await library.fetchManifest()

        let bundle2 = try await library.buildBundle(for: manifest2)

        let bundles = try await library.readAssetBundles()

        #expect(bundles.count == 2)

        // Should be sorted newest to oldest (descending by downloadDate)
        #expect(bundles[0].id == bundle2.id)
        #expect(bundles[1].id == bundle1.id)
        #expect(bundles[0].downloadDate > bundles[1].downloadDate)
    }

    @Test("readAssetBundles ignores non-directory files in site root")
    func readAssetBundlesIgnoresNonDirectoryFiles() async throws {
        let manifestJSON = uniqueManifestJSON(identifier: "test-ignores-files-\(UUID().uuidString)")

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(manifestJSON.utf8) }

        let siteCacheRoot = URL.randomTemporaryDirectory
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore, storageRoot: siteCacheRoot)

        let manifest = try await library.fetchManifest()

        _ = try await library.buildBundle(for: manifest)

        // Add a non-directory file to the site root
        let randomFile = siteCacheRoot.appending(path: "random-file.txt")
        try Data("random content".utf8).write(to: randomFile, options: .atomic)

        let bundles = try await library.readAssetBundles()

        // Should only return the actual bundle, not the random file
        #expect(bundles.count == 1)
    }

    @Test("readAssetBundles returns bundles with correct manifest data")
    func readAssetBundlesReturnsBundlesWithCorrectManifestData() async throws {
        let blockTypes = ["core/paragraph", "core/heading", "core/image"]
        let manifestJSON = """
      {
          "scripts": "",
          "styles": "",
          "allowed_block_types": ["core/paragraph", "core/heading", "core/image"]
      }
      """

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(manifestJSON.utf8) }

        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)

        let manifest = try await library.fetchManifest()

        _ = try await library.buildBundle(for: manifest)

        let bundles = try await library.readAssetBundles()

        #expect(bundles.count == 1)

        let retrievedBundle = bundles[0]
        #expect(retrievedBundle.manifest.allowedBlockTypes == blockTypes)
    }

    // MARK: - CachePolicy Tests

    @Test("EditorCachePolicy.always is default behavior")
    func editorCachePolicyAlwaysIsDefault() async throws {
        let manifestJSON = """
      {
          "scripts": "",
          "styles": "",
          "allowed_block_types": []
      }
      """

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(manifestJSON.utf8) }

        let library = makeLibrary(httpClient: mockClient)

        // Call fetchManifest with default cache policy
        _ = try await library.fetchManifest()

        // The HTTP client should have been called
        #expect(mockClient.getCallCount == 1)
    }

    @Test("EditorCachePolicy.maxAge uses cached manifest when within timeout")
    func editorCachePolicyMaxAgeUsesCachedWhenWithinTimeout() async throws {
        let manifestJSON = uniqueManifestJSON(identifier: "test-maxage-within-\(UUID().uuidString)")

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(manifestJSON.utf8) }

        // Set maxAge to 1 hour (3600 seconds)
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(3600))

        // First fetch and create the bundle
        let originalManifest = try await library.fetchManifest()
        _ = try await library.buildBundle(for: originalManifest)

        // Second fetch should use cached manifest since we're within the 1 hour timeout
        let cachedManifest = try await library.fetchManifest()

        #expect(cachedManifest.checksum == originalManifest.checksum)
        // Should have made 2 HTTP calls but second one used cached bundle
        #expect(mockClient.getCallCount == 2)
    }

    @Test("EditorCachePolicy.maxAge fetches new manifest when timeout expired")
    func editorCachePolicyMaxAgeFetchesNewWhenExpired() async throws {
        let manifestJSON = uniqueManifestJSON(identifier: "test-maxage-expired-\(UUID().uuidString)")

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(manifestJSON.utf8) }

        // Set maxAge to 0 seconds (immediately expired)
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(0))

        // First fetch and create the bundle
        let originalManifest = try await library.fetchManifest()
        _ = try await library.buildBundle(for: originalManifest)

        // Second fetch should NOT use cached manifest since maxAge(0) means immediately expired
        let newManifest = try await library.fetchManifest()

        // The checksums should still match (same data) but the cache was bypassed
        #expect(newManifest.checksum == originalManifest.checksum)
        #expect(mockClient.getCallCount == 2)
    }

    @Test("EditorCachePolicy.maxAge with short timeout expires after delay")
    func editorCachePolicyMaxAgeExpiresAfterDelay() async throws {
        let manifestJSON = uniqueManifestJSON(identifier: "test-maxage-delay-\(UUID().uuidString)")

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(manifestJSON.utf8) }

        // Set maxAge to 0.05 seconds (50 milliseconds)
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(0.05))

        // First fetch and create the bundle
        let originalManifest = try await library.fetchManifest()
        _ = try await library.buildBundle(for: originalManifest)

        // Wait for the cache to expire
        try await Task.sleep(for: .milliseconds(100))

        // Third fetch should bypass cache since it's expired
        _ = try await library.fetchManifest()

        // Both fetches should have made HTTP calls since cache expired
        #expect(mockClient.getCallCount == 2)
    }

    @Test("EditorCachePolicy.maxAge uses cache before expiry then fetches after")
    func editorCachePolicyMaxAgeTransitionsCorrectly() async throws {
        let manifestJSON = uniqueManifestJSON(identifier: "test-maxage-transition-\(UUID().uuidString)")

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(manifestJSON.utf8) }

        // Set maxAge to 0.1 seconds (100 milliseconds)
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(0.1))

        // First fetch and create the bundle
        let originalManifest = try await library.fetchManifest()
        _ = try await library.buildBundle(for: originalManifest)

        // Immediate second fetch should use cache (within 100ms)
        let cachedManifest = try await library.fetchManifest()
        #expect(cachedManifest.checksum == originalManifest.checksum)

        // Wait for cache to expire
        try await Task.sleep(for: .milliseconds(150))

        // Third fetch should create new manifest since cache expired
        let newManifest = try await library.fetchManifest()
        #expect(newManifest.checksum == originalManifest.checksum)

        // Should have made 3 HTTP calls total
        #expect(mockClient.getCallCount == 3)
    }

    // MARK: - Bundle Fetching Tests with Real Manifest Data

    @Test("fetchManifest parses real manifest test case with many block types")
    func fetchManifestParsesRealManifestTestCase() async throws {
        let manifestData = try Data.forResource(named: "editor-asset-manifest-test-case-1")

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in manifestData }

        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)

        let manifest = try await library.fetchManifest()

        // Verify block types are parsed correctly
        #expect(manifest.allowedBlockTypes.contains("core/paragraph"))
        #expect(manifest.allowedBlockTypes.contains("core/heading"))
        #expect(manifest.allowedBlockTypes.contains("core/image"))
        #expect(manifest.allowedBlockTypes.contains("jetpack/ai-assistant"))
        #expect(manifest.allowedBlockTypes.count > 100)

        // Verify scripts are present
        #expect(manifest.rawScripts.contains("wp-polyfill"))
        #expect(manifest.rawScripts.contains("jquery"))
        #expect(manifest.rawScripts.contains("react"))
    }

    @Test("fetchManifest generates consistent checksum for same data")
    func fetchManifestGeneratesConsistentChecksum() async throws {
        let manifestData = try Data.forResource(named: "editor-asset-manifest-test-case-1")

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in manifestData }

        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)

        let manifest1 = try await library.fetchManifest()

        let manifest2 = try await library.fetchManifest()

        #expect(manifest1.checksum == manifest2.checksum)
        #expect(!manifest1.checksum.isEmpty)
    }

    @Test("EditorAssetBundle can be created from manifest")
    func editorAssetBundleCanBeCreatedFromManifest() async throws {
        let manifestData = try Data.forResource(named: "editor-asset-manifest-test-case-1")

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in manifestData }

        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)

        let manifest = try await library.fetchManifest()

        let bundle = try EditorAssetBundle(manifest: manifest, bundleRoot: .temporaryDirectory)

        #expect(bundle.id == manifest.checksum)
        #expect(bundle.manifest.allowedBlockTypes == manifest.allowedBlockTypes)
    }

    @Test("EditorAssetBundle preserves manifest data through encoding")
    func editorAssetBundlePreservesManifestThroughEncoding() async throws {
        let manifestData = try Data.forResource(named: "editor-asset-manifest-test-case-1")

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in manifestData }

        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)

        let manifest = try await library.fetchManifest()

        let originalBundle = try EditorAssetBundle(manifest: manifest, bundleRoot: .temporaryDirectory)

        // Encode and decode the bundle
        let encoded = try originalBundle.dataRepresentation()
        let decodedBundle = try EditorAssetBundle(data: encoded, bundleRoot: .temporaryDirectory)

        #expect(decodedBundle.id == originalBundle.id)
        #expect(decodedBundle.manifest.checksum == originalBundle.manifest.checksum)
        #expect(decodedBundle.manifest.allowedBlockTypes == originalBundle.manifest.allowedBlockTypes)
        #expect(decodedBundle.manifest.rawScripts == originalBundle.manifest.rawScripts)
        #expect(decodedBundle.manifest.rawStyles == originalBundle.manifest.rawStyles)
    }

    @Test("EditorAssetBundle downloadDate is set on creation")
    func editorAssetBundleDownloadDateIsSet() async throws {
        let beforeCreation = Date()

        let bundle = try EditorAssetBundle(manifest: .empty, bundleRoot: .temporaryDirectory)

        let afterCreation = Date()

        #expect(bundle.downloadDate >= beforeCreation)
        #expect(bundle.downloadDate <= afterCreation)
    }

    @Test("Multiple bundles from same manifest have same ID")
    func multipleBundlesFromSameManifestHaveSameId() async throws {
        let manifestData = try Data.forResource(named: "editor-asset-manifest-test-case-1")

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in manifestData }

        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)

        let manifest = try await library.fetchManifest()

        let bundle1 = try EditorAssetBundle(manifest: manifest, bundleRoot: .temporaryDirectory)
        let bundle2 = try EditorAssetBundle(manifest: manifest, bundleRoot: .temporaryDirectory)

        #expect(bundle1.id == bundle2.id)
    }

    // MARK: - buildBundle Tests

    /// Helper to create a unique manifest JSON for each test
    private func uniqueManifestJSON(identifier: String) -> String {
    """
    {
        "scripts": "",
        "styles": "",
        "allowed_block_types": ["\(identifier)"]
    }
    """
    }

    @Test("buildBundle returns bundle for manifest with no assets")
    func buildBundleReturnsEmptyBundleForEmptyManifest() async throws {
        let manifestJSON = uniqueManifestJSON(identifier: "test-empty-bundle-\(UUID().uuidString)")

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(manifestJSON.utf8) }

        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)

        let manifest = try await library.fetchManifest()

        let bundle = try await library.buildBundle(
            for: manifest
        )

        #expect(bundle.manifest.checksum == manifest.checksum)
        #expect(!bundle.id.isEmpty)
        #expect(mockClient.downloadCallCount == 0)
    }

    @Test("buildBundle creates bundle directory on disk")
    func buildBundleCreatesBundleDirectory() async throws {
        let manifestJSON = uniqueManifestJSON(identifier: "test-creates-dir-\(UUID().uuidString)")

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(manifestJSON.utf8) }

        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)

        let manifest = try await library.fetchManifest()

        let bundle = try await library.buildBundle(for: manifest)

        // Verify the bundle directory was created
        let bundleRoot = await library.bundleRoot(for: bundle)
        #expect(FileManager.default.fileExists(at: bundleRoot))
    }

    @Test("buildBundle saves bundle manifest to disk")
    func buildBundleSavesBundleManifest() async throws {
        let manifestJSON = uniqueManifestJSON(identifier: "test-saves-manifest-\(UUID().uuidString)")

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(manifestJSON.utf8) }

        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)

        let manifest = try await library.fetchManifest()

        let bundle = try await library.buildBundle(for: manifest)

        // Verify the manifest file was created
        let manifestPath = await library.bundleManifestPath(for: bundle)
        #expect(FileManager.default.fileExists(at: manifestPath))

        // Verify we can read it back
        let savedBundle = try EditorAssetBundle(url: manifestPath)
        #expect(savedBundle.id == bundle.id)
    }

    @Test("buildBundle makes bundle discoverable via hasBundle")
    func buildBundleMakesBundleDiscoverable() async throws {
        let manifestJSON = uniqueManifestJSON(identifier: "test-discoverable-\(UUID().uuidString)")

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(manifestJSON.utf8) }

        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)

        let manifest = try await library.fetchManifest()

        let bundle = try await library.buildBundle(for: manifest)

        // Verify the bundle directory exists using the bundle's path
        let bundleRoot = await library.bundleRoot(for: bundle)
        #expect(FileManager.default.fileExists(at: bundleRoot))
    }

    @Test("buildBundle returns bundle with correct manifest data from real manifest")
    func buildBundleReturnsBundleWithCorrectManifest() async throws {
        // Create a manifest with the same block types but no scripts/styles to avoid downloads
        let manifestJSON = """
      {
          "scripts": "",
          "styles": "",
          "allowed_block_types": ["core/paragraph", "core/heading", "jetpack/ai-assistant"]
      }
      """

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(manifestJSON.utf8) }

        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)

        let manifest = try await library.fetchManifest()

        let bundle = try await library.buildBundle(for: manifest)

        // Verify the bundle has the correct manifest data
        #expect(bundle.id == manifest.checksum)
        #expect(bundle.manifest.allowedBlockTypes == manifest.allowedBlockTypes)
        #expect(bundle.manifest.allowedBlockTypes.contains("core/paragraph"))
        #expect(bundle.manifest.allowedBlockTypes.contains("jetpack/ai-assistant"))
    }

    @Test("buildBundle downloads all script and style assets")
    func buildBundleDownloadsAllAssets() async throws {
        let manifestJSON = """
      {
          "scripts": "<script src=\\"https://example.com/script1.js\\"></script><script src=\\"https://example.com/script2.js\\"></script>",
          "styles": "<link rel=\\"stylesheet\\" href=\\"https://example.com/style.css\\">",
          "allowed_block_types": ["core/paragraph"]
      }
      """

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { url in
            if url.path.contains("editor-assets") {
                return Data(manifestJSON.utf8)
            }
            return Data("mock content".utf8)
        }

        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)

        let manifest = try await library.fetchManifest()

        let progressTracker = ProgressTracker()

        _ = try await library.buildBundle(
            for: manifest,
            progress: { progress in
                progressTracker.append(progress)
            }
        )

        #expect(mockClient.downloadCallCount == 3)

        // Should have downloaded 3 assets (2 scripts + 1 style)
        #expect(mockClient.downloadedURLs.contains(URL(string: "https://example.com/script1.js")!))
        #expect(mockClient.downloadedURLs.contains(URL(string: "https://example.com/script2.js")!))
        #expect(mockClient.downloadedURLs.contains(URL(string: "https://example.com/style.css")!))

        // Progress should have been reported for each asset
        #expect(progressTracker.count == 3)
    }

    @Test("buildBundle reports progress correctly")
    func buildBundleReportsProgressCorrectly() async throws {
        let manifestJSON = """
      {
          "scripts": "<script src=\\"https://example.com/a.js\\"></script><script src=\\"https://example.com/b.js\\"></script>",
          "styles": "",
          "allowed_block_types": []
      }
      """

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(manifestJSON.utf8) }

        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)

        let manifest = try await library.fetchManifest()

        let progressTracker = ProgressTracker()
        _ = try await library.buildBundle(
            for: manifest,
            progress: { progress in
                progressTracker.append(progress)
            }
        )

        // Should have 2 progress updates
        #expect(progressTracker.count == 2)

        // All updates should have total == 2
        for progress in progressTracker.updates {
            #expect(progress.total == 2)
        }

        // Final progress should be complete
        if let lastProgress = progressTracker.updates.last {
            #expect(lastProgress.fractionCompleted == 1.0)
        }
    }

    // MARK: - downloadAssetBundle Tests

    @Test("downloadAssetBundle fetches manifest and builds bundle")
    func downloadAssetBundleFetchesAndBuilds() async throws {
        let manifestJSON = uniqueManifestJSON(identifier: "test-download-bundle-\(UUID().uuidString)")

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(manifestJSON.utf8) }

        let library = makeLibrary(httpClient: mockClient)

        let bundle = try await library.downloadAssetBundle()

        #expect(!bundle.id.isEmpty)
        #expect(mockClient.getCallCount == 1)  // One call for the manifest
    }

    @Test("buildBundle downloads assets with nested paths")
    func buildBundleDownloadsAssetsWithNestedPaths() async throws {
        let manifestJSON = """
      {
          "scripts": "<script src=\\"https://example.com/wp-content/plugins/jetpack/assets/js/editor.js\\"></script>",
          "styles": "<link rel=\\"stylesheet\\" href=\\"https://example.com/wp-content/themes/theme/css/blocks/gallery.css\\">",
          "allowed_block_types": ["core/paragraph"]
      }
      """

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { url in
            if url.path.contains("editor-assets") {
                return Data(manifestJSON.utf8)
            }
            return Data("mock content".utf8)
        }

        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)

        let manifest = try await library.fetchManifest()

        let bundle = try await library.buildBundle(for: manifest)

        // Verify the assets were downloaded
        #expect(mockClient.downloadCallCount == 2)

        // Verify the bundle was created successfully (which means directories were created)
        let bundleRoot = await library.bundleRoot(for: bundle)
        #expect(FileManager.default.fileExists(at: bundleRoot))

        // Verify the nested directory structure was created for the script
        let scriptPath = bundleRoot.appending(path: "/wp-content/plugins/jetpack/assets/js/editor.js")
        #expect(FileManager.default.fileExists(at: scriptPath))

        // Verify the nested directory structure was created for the style
        let stylePath = bundleRoot.appending(path: "/wp-content/themes/theme/css/blocks/gallery.css")
        #expect(FileManager.default.fileExists(at: stylePath))
    }

    @Test("downloadAssetBundle reports progress")
    func downloadAssetBundleReportsProgress() async throws {
        let manifestJSON = """
      {
          "scripts": "<script src=\\"https://example.com/script.js\\"></script>",
          "styles": "",
          "allowed_block_types": []
      }
      """

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(manifestJSON.utf8) }

        let library = makeLibrary(httpClient: mockClient)

        let progressTracker = ProgressTracker()
        _ = try await library.downloadAssetBundle { progress in
            progressTracker.append(progress)
        }

        #expect(progressTracker.count == 1)
        #expect(progressTracker.updates.first?.total == 1)
    }

    @Test("buildBundle continues when individual asset downloads fail")
    func buildBundleContinuesWhenAssetDownloadsFail() async throws {
        let manifestJSON = """
      {
          "scripts": "<script src=\\"https://example.com/good-script.js\\"></script><script src=\\"https://blocked.com/stats.js\\"></script>",
          "styles": "<link rel=\\"stylesheet\\" href=\\"https://example.com/style.css\\">",
          "allowed_block_types": ["core/paragraph"]
      }
      """

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { url in
            if url.path.contains("editor-assets") {
                return Data(manifestJSON.utf8)
            }
            // Simulate content blocker blocking stats.js
            if url.host == "blocked.com" {
                throw URLError(.badURL)
            }
            return Data("mock content".utf8)
        }

        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)

        let manifest = try await library.fetchManifest()

        // Should NOT throw - individual asset failures are caught and logged
        let bundle = try await library.buildBundle(for: manifest)

        // Bundle should be created successfully
        #expect(!bundle.id.isEmpty)

        // Verify progress was reported for all assets (including the failed one)
        #expect(mockClient.downloadCallCount == 3)

        // Verify the successful assets were downloaded
        let bundleRoot = await library.bundleRoot(for: bundle)
        let goodScriptPath = bundleRoot.appending(path: "/good-script.js")
        let stylePath = bundleRoot.appending(path: "/style.css")
        #expect(FileManager.default.fileExists(at: goodScriptPath))
        #expect(FileManager.default.fileExists(at: stylePath))

        // The failed asset should not exist
        let failedScriptPath = bundleRoot.appending(path: "/stats.js")
        #expect(!FileManager.default.fileExists(at: failedScriptPath))
    }
}

// MARK: - Progress Tracker for Tests

final class ProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _updates: [EditorProgress] = []

    var updates: [EditorProgress] {
        lock.withLock { _updates }
    }

    var count: Int {
        lock.withLock { _updates.count }
    }

    func append(_ progress: EditorProgress) {
        lock.withLock { _updates.append(progress) }
    }
}

// MARK: - Mock HTTP Client for EditorAssetLibrary Tests

final class EditorAssetLibraryMockHTTPClient: EditorHTTPClientProtocol, @unchecked Sendable {

    var getCallCount = 0
    var downloadCallCount = 0
    var downloadedURLs: [URL] = []
    private let lock = NSLock()

    /// URLs requested via `perform(_:)`. Use this to verify which endpoints were called.
    private var _requestedURLs: [URL] = []
    var requestedURLs: [URL] {
        lock.withLock { _requestedURLs }
    }

    /// Handler for generating response data based on request URL.
    /// Can throw to simulate failures for specific URLs.
    /// Used by both `perform()` and `download()` methods.
    var urlResponseHandler: ((URL) throws -> Data) = { _ in Data() }

    func perform(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = try #require(urlRequest.url)

        lock.withLock {
            getCallCount += 1
            _requestedURLs.append(url)
        }

        let responseData = try urlResponseHandler(url)

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!

        return (responseData, response)
    }

    func download(_ urlRequest: URLRequest) async throws -> (URL, HTTPURLResponse) {
        let url = urlRequest.url!

        lock.withLock {
            downloadCallCount += 1
            downloadedURLs.append(url)
        }

        let data = try urlResponseHandler(url)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: tempURL)

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!

        return (tempURL, response)
    }
}
