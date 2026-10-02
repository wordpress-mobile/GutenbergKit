import Foundation
import Testing

@testable import GutenbergKit

struct EditorAssetLibraryTests {

    // MARK: - Test Fixtures

    static var testConfiguration: EditorConfiguration {
        EditorConfigurationBuilder(
            postType: .post,
            siteURL: URL(string: "https://example.com")!,
            siteApiRoot: URL(string: "https://example.com/wp-json")!,
        )
        .setShouldUsePlugins(true)
        .setShouldUseThemeStyles(true)
        .build()
    }

    static var minimalConfiguration: EditorConfiguration {
        EditorConfigurationBuilder(
            postType: .post,
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

        let result = await library.existingBundle(forManifestChecksum: "nonexistent-checksum-12345")
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

    @Test("fetchManifest requests the manifest on every call")
    func fetchManifestRequestsOnEveryCall() async throws {
        let manifestJSON = """
      {
          "scripts": "",
          "styles": "",
          "allowed_block_types": ["core/paragraph"]
      }
      """

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(manifestJSON.utf8) }

        let library = makeLibrary(httpClient: mockClient)

        _ = try await library.fetchManifest()
        _ = try await library.fetchManifest()

        #expect(mockClient.getCallCount == 2)
    }

    @Test("fetchManifest returns the manifest of a matching bundle on disk, even under .ignore")
    func fetchManifestReturnsMatchingBundleManifest() async throws {
        let manifestJSON = uniqueManifestJSON(identifier: "test-cached-manifest-\(UUID().uuidString)")

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(manifestJSON.utf8) }

        // The policy decides whether to check the manifest at all, not what to make of the answer
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)

        // First, fetch the manifest and create a bundle on disk
        let originalManifest = try await library.fetchManifest()

        let bundle = try await library.buildBundle(for: originalManifest)

        // Mark the copy on disk, so that it can be told apart from the response parsed again
        let manifestPath = await library.bundleManifestPath(for: bundle)
        var stored = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: manifestPath)) as? [String: Any])
        var storedManifest = try #require(stored["manifest"] as? [String: Any])
        storedManifest["allowedBlockTypes"] = ["only/on-disk"]
        stored["manifest"] = storedManifest
        try JSONSerialization.data(withJSONObject: stored).write(to: manifestPath, options: .atomic)

        // Now fetch again - should return the on-disk manifest
        let cachedManifest = try await library.fetchManifest()

        #expect(cachedManifest.checksum == originalManifest.checksum)
        #expect(cachedManifest.allowedBlockTypes == ["only/on-disk"])

        // Verify we made 2 HTTP calls (one for each fetchManifest)
        // but the second one used the cached bundle's manifest
        #expect(mockClient.getCallCount == 2)
    }

    @Test("fetchManifest parses a new manifest when no bundle matches")
    func fetchManifestParsesWhenNoBundleMatches() async throws {
        let manifestJSON = uniqueManifestJSON(identifier: "test-no-cache-fallback-\(UUID().uuidString)")

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(manifestJSON.utf8) }

        let library = makeLibrary(httpClient: mockClient)

        // Fetch when no bundle exists on disk
        let manifest = try await library.fetchManifest()

        // Should still return a valid manifest (created from remote data)
        #expect(!manifest.checksum.isEmpty)
        #expect(mockClient.getCallCount == 1)
    }

    @Test("fetchManifest avoids expensive LocalEditorAssetManifest creation when a bundle matches")
    func fetchManifestAvoidsExpensiveCreationWhenBundleMatches() async throws {
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

        let library = makeLibrary(httpClient: mockClient)

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

    // MARK: - Cache Policy Tests

    @Test("readLatestAssetBundle returns nil when there are no bundles")
    func readLatestAssetBundleReturnsNilWithoutBundles() async throws {
        let library = makeLibrary(cachePolicy: .always)

        #expect(try await library.readLatestAssetBundle() == nil)
    }

    @Test("readLatestAssetBundle returns the newest bundle, however old, under .always")
    func readLatestAssetBundleIgnoresAgeUnderAlways() async throws {
        let (library, _) = try await makeLibraryWithBundle(cachePolicy: .always)
        let bundle = try #require(try await library.readAssetBundles().first)
        try backdate(bundle, by: 365 * 86_400)

        #expect(try await library.readLatestAssetBundle()?.id == bundle.id)
    }

    @Test("readLatestAssetBundle returns nil under .ignore, even for a new bundle")
    func readLatestAssetBundleReturnsNilUnderIgnore() async throws {
        let (library, _) = try await makeLibraryWithBundle(cachePolicy: .ignore)

        #expect(try await library.readAssetBundles().count == 1)
        #expect(try await library.readLatestAssetBundle() == nil)
    }

    @Test("readLatestAssetBundle returns a bundle younger than .maxAge")
    func readLatestAssetBundleReturnsBundleWithinMaxAge() async throws {
        let (library, _) = try await makeLibraryWithBundle(cachePolicy: .maxAge(3600))
        let bundle = try #require(try await library.readAssetBundles().first)
        try backdate(bundle, by: 1800)

        #expect(try await library.readLatestAssetBundle()?.id == bundle.id)
    }

    @Test("readLatestAssetBundle returns nil for a bundle older than .maxAge")
    func readLatestAssetBundleReturnsNilPastMaxAge() async throws {
        let (library, _) = try await makeLibraryWithBundle(cachePolicy: .maxAge(3600))
        let bundle = try #require(try await library.readAssetBundles().first)
        try backdate(bundle, by: 7200)

        #expect(try await library.readLatestAssetBundle() == nil)
    }

    @Test("downloadAssetBundle keeps a bundle whose manifest hasn't changed, and marks it current")
    func downloadAssetBundleKeepsUnchangedBundle() async throws {
        let (library, mockClient) = try await makeLibraryWithBundle(cachePolicy: .maxAge(3600))
        let bundle = try #require(try await library.readAssetBundles().first)
        try backdate(bundle, by: 7200)
        #expect(mockClient.downloadCallCount == 1)

        let checked = try await library.downloadAssetBundle()

        #expect(checked.id == bundle.id)
        #expect(mockClient.getCallCount == 2)  // The manifest, checked again
        #expect(mockClient.downloadCallCount == 1)  // Its asset, not downloaded again
        #expect(try await library.readAssetBundles().count == 1)
        #expect(try await library.readLatestAssetBundle()?.id == bundle.id)
    }

    @Test("downloadAssetBundle builds a new bundle when the manifest has changed")
    func downloadAssetBundleBuildsChangedBundle() async throws {
        let (library, mockClient) = try await makeLibraryWithBundle(cachePolicy: .ignore)
        let original = try #require(try await library.readAssetBundles().first)

        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "2"))
        let changed = try await library.downloadAssetBundle()

        #expect(changed.id != original.id)
        #expect(mockClient.downloadCallCount == 2)
        #expect(try await library.readAssetBundles().map(\.id) == [changed.id, original.id])
    }

    @Test("downloadAssetBundle makes the bundle for a manifest the site went back to the newest again")
    func downloadAssetBundleRestoresReturningBundle() async throws {
        let (library, mockClient) = try await makeLibraryWithBundle(cachePolicy: .ignore)
        let original = try #require(try await library.readAssetBundles().first)
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "2"))
        let changed = try await library.downloadAssetBundle()

        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        let restored = try await library.downloadAssetBundle()

        #expect(restored.id == original.id)
        #expect(mockClient.downloadCallCount == 2)
        #expect(try await library.readAssetBundles().map(\.id) == [original.id, changed.id])
    }

    @Test("downloadAssetBundle leaves a bundle whose manifest hasn't changed exactly as it was")
    func downloadAssetBundleLeavesUnchangedBundleAsItWas() async throws {
        let (library, _) = try await makeLibraryWithBundle(cachePolicy: .ignore)
        let bundle = try #require(try await library.readAssetBundles().first)

        let checked = try await library.downloadAssetBundle()

        // A host comparing dependencies sees no change, and the date still says when it was downloaded
        #expect(checked == bundle)
        #expect(checked.downloadDate == bundle.downloadDate)
        #expect(try await library.readAssetBundles() == [bundle])
    }

    @Test("downloadAssetBundle downloads an asset that an earlier build of the bundle failed to")
    func downloadAssetBundleRepairsMissingAsset() async throws {
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { url in
            guard url.path.contains("editor-assets") else { throw URLError(.timedOut) }
            return Data(Self.manifestJSON(scriptVersion: "1").utf8)
        }
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)
        let gapped = try await library.downloadAssetBundle()
        #expect(!gapped.hasAssetData(for: Self.scriptURL))

        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        let repaired = try await library.downloadAssetBundle()

        #expect(repaired.id == gapped.id)
        #expect(repaired.hasAssetData(for: Self.scriptURL))
        #expect(mockClient.downloadCallCount == 2)
    }

    @Test(
        "a manifest check asks the site afresh, rather than taking a stored response or a request in flight",
        arguments: [EditorCachePolicy.ignore, .maxAge(3600)]
    )
    func manifestCheckAsksAfresh(cachePolicy: EditorCachePolicy) async throws {
        let (library, mockClient) = try await makeLibraryWithBundle(cachePolicy: cachePolicy)

        _ = try await library.downloadAssetBundle()

        #expect(mockClient.requests.last?.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test("under .always, a manifest request can still be shared with one in flight")
    func manifestRequestIsSharableUnderAlways() async throws {
        let (_, mockClient) = try await makeLibraryWithBundle(cachePolicy: .always)

        #expect(mockClient.requests.last?.cachePolicy == .useProtocolCachePolicy)
    }

    @Test("downloadAssetBundle builds a bundle again if another service's cleanup deletes it mid-check")
    func downloadAssetBundleRebuildsBundleCleanedUpDuringCheck() async throws {
        let storageRoot = URL.randomTemporaryDirectory
        let planted = try await plantBundles(
            forManifests: [Self.manifestJSON(scriptVersion: "1"), Self.manifestJSON(scriptVersion: "2")],
            in: storageRoot
        )
        let mockClient = EditorAssetLibraryMockHTTPClient()
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore, storageRoot: storageRoot)
        let other = makeLibrary(storageRoot: storageRoot)

        // The site is back on the older manifest. Another service's cleanup removes that manifest's
        // bundle — not yet the latest — after the check has found it on disk.
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        let restored = try await library.downloadAssetBundle { _ in try? await other.cleanup() }

        #expect(restored.id == planted[0].id)
        #expect((try? restored.getEditorRepresentation() as EditorAssetBundle.EditorRepresentation) != nil)
        #expect(restored.hasAssetData(for: Self.scriptURL))
        #expect(try await library.readAssetBundles().first?.id == restored.id)
    }

    @Test("downloadAssetBundle builds a bundle again if a purge deletes it mid-check")
    func downloadAssetBundleRebuildsBundlePurgedDuringCheck() async throws {
        let (library, _) = try await makeLibraryWithBundle(cachePolicy: .ignore)
        let bundle = try #require(try await library.readAssetBundles().first)

        let checked = try await library.downloadAssetBundle { _ in try? await library.purge() }

        #expect(checked.id == bundle.id)
        #expect((try? checked.getEditorRepresentation() as EditorAssetBundle.EditorRepresentation) != nil)
        #expect(checked.hasAssetData(for: Self.scriptURL))
        #expect(try await library.readAssetBundles().map(\.id) == [bundle.id])
    }

    @Test("a bundle stored before checks were recorded is as old as its download")
    func bundleWithoutLastCheckedDateUsesDownloadDate() async throws {
        let (library, _) = try await makeLibraryWithBundle(cachePolicy: .maxAge(3600))
        let bundle = try #require(try await library.readAssetBundles().first)
        let manifestPath = await library.bundleManifestPath(for: bundle)

        // What an earlier version wrote: the manifest and a download date, and nothing else
        func store(downloadedAgo interval: TimeInterval) throws {
            let stored: [String: Any] = [
                "manifest": try JSONSerialization.jsonObject(with: JSONEncoder().encode(bundle.manifest)),
                "downloadDate": Date(timeIntervalSinceNow: -interval).timeIntervalSinceReferenceDate
            ]
            try JSONSerialization.data(withJSONObject: stored).write(to: manifestPath, options: .atomic)
        }

        try store(downloadedAgo: 1800)
        #expect(try await library.readLatestAssetBundle()?.id == bundle.id)

        try store(downloadedAgo: 7200)
        #expect(try await library.readAssetBundles().first?.lastCheckedDate == nil)
        #expect(try await library.readLatestAssetBundle() == nil)
    }

    // MARK: - cleanup Tests

    @Test("cleanup removes the bundles an earlier launch left behind, except the newest")
    func cleanupRemovesBundlesFromEarlierLaunch() async throws {
        let storageRoot = URL.randomTemporaryDirectory
        let planted = try await plantBundles(
            forManifests: ["1", "2", "3"].map(Self.manifestJSON(scriptVersion:)),
            in: storageRoot
        )
        let library = makeLibrary(storageRoot: storageRoot)

        try await library.cleanup()

        #expect(try await library.readAssetBundles().map(\.id) == [planted[2].id])
    }

    @Test("cleanup keeps the bundle the site's manifest last matched, though another was downloaded later")
    func cleanupKeepsLatestBundleWhateverItsDownloadDate() async throws {
        let storageRoot = URL.randomTemporaryDirectory
        let planted = try await plantBundles(
            forManifests: [Self.manifestJSON(scriptVersion: "1"), Self.manifestJSON(scriptVersion: "2")],
            in: storageRoot
        )
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore, storageRoot: storageRoot)

        _ = try await library.downloadAssetBundle()
        try await library.cleanup()

        #expect(try await library.readAssetBundles().map(\.id) == [planted[0].id])
    }

    @Test("cleanup keeps a bundle handed out since launch, and purge removes it anyway")
    func cleanupKeepsHandedOutBundles() async throws {
        let (library, mockClient) = try await makeLibraryWithBundle(cachePolicy: .ignore)
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "2"))
        _ = try await library.downloadAssetBundle()

        try await library.cleanup()
        #expect(try await library.readAssetBundles().count == 2)

        try await library.purge()
        #expect(try await library.readAssetBundles().isEmpty)
    }

    /// A library whose storage holds one bundle, built from ``manifestJSON(scriptVersion:)`` with version `1`.
    private func makeLibraryWithBundle(
        cachePolicy: EditorCachePolicy
    ) async throws -> (EditorAssetLibrary, EditorAssetLibraryMockHTTPClient) {
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        let library = makeLibrary(httpClient: mockClient, cachePolicy: cachePolicy)
        _ = try await library.downloadAssetBundle()
        return (library, mockClient)
    }

    /// A manifest with one script, whose URL carries `scriptVersion` the way WordPress versions its assets.
    private static func manifestJSON(scriptVersion: String) -> String {
        """
        {
            "scripts": "<script src=\\"https://example.com/plugin.js?ver=\(scriptVersion)\\"></script>",
            "styles": "",
            "allowed_block_types": ["core/paragraph"]
        }
        """
    }

    private static func responses(forManifest manifestJSON: String) -> (URL) throws -> Data {
        { url in url.path.contains("editor-assets") ? Data(manifestJSON.utf8) : Data("mock content".utf8) }
    }

    /// The script in ``manifestJSON(scriptVersion:)`` with version `1`.
    private static let scriptURL = URL(string: "https://example.com/plugin.js?ver=1")!

    /// Makes it `interval` seconds since the site's manifest was last found to match `bundle`.
    private func backdate(_ bundle: EditorAssetBundle, by interval: TimeInterval) throws {
        try EditorAssetBundle(
            manifest: bundle.manifest,
            downloadDate: bundle.downloadDate,
            lastCheckedDate: Date(timeIntervalSinceNow: -interval),
            bundleRoot: bundle.bundleRoot
        ).writeManifest()
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

    @Test("buildBundle publishes nothing when it is cancelled mid-download")
    func buildBundlePublishesNothingWhenCancelled() async throws {
        let manifestJSON = """
      {
          "scripts": "<script src=\\"https://example.com/script.js\\"></script>",
          "styles": "",
          "allowed_block_types": ["core/paragraph"]
      }
      """
        let manifest = try LocalEditorAssetManifest(
            remoteManifest: RemoteEditorAssetManifest(data: Data(manifestJSON.utf8))
        )

        let session = ParkedURLSession()
        defer { session.release() }
        let library = makeLibrary(httpClient: EditorHTTPClient(urlSession: session, authHeader: "Bearer test-token"))
        let destination = await library.bundleRoot(for: manifest.checksum).standardizedFileURL

        let build = Task { try await library.buildBundle(for: manifest) }
        try await session.waitUntilStarted()
        let abandoned = try #require(EditorAssetLibrary.inFlightBuilds.task(for: destination))
        build.cancel()

        // The cancelled download is swallowed like any failed asset; the build must
        // still refuse to publish, or every later launch serves the gap.
        await #expect(throws: CancellationError.self) { try await build.value }
        // The caller's wait ends before the build it abandoned is cancelled, so wait for the
        // build itself: checked any sooner, a build about to publish hasn't yet.
        await abandoned.value
        #expect(try await library.readAssetBundles().isEmpty)
    }

    @Test("builds of one bundle share one build, whichever library runs them")
    func buildsOfOneBundleShareOneBuild() async throws {
        let manifestJSON = """
      {
          "scripts": "<script src=\\"https://example.com/script.js\\"></script>",
          "styles": "",
          "allowed_block_types": ["core/paragraph"]
      }
      """
        let manifest = try LocalEditorAssetManifest(
            remoteManifest: RemoteEditorAssetManifest(data: Data(manifestJSON.utf8))
        )

        let session = ParkedURLSession()
        defer { session.release() }
        let storageRoot = URL.randomTemporaryDirectory
        let libraries = [
            makeLibrary(httpClient: EditorHTTPClient(urlSession: session, authHeader: "Bearer test-token"), storageRoot: storageRoot),
            makeLibrary(httpClient: EditorHTTPClient(urlSession: session, authHeader: "Bearer test-token"), storageRoot: storageRoot),
        ]
        let destination = await libraries[0].bundleRoot(for: manifest.checksum).standardizedFileURL

        let builds = libraries.map { library in Task { try await library.buildBundle(for: manifest) } }
        try await waitUntil { EditorAssetLibrary.inFlightBuilds.waiterCount(for: destination) == 2 }

        session.release()  // fails the parked download, which a build tolerates
        #expect(try await builds[0].value == builds[1].value)
        #expect(session.requestCount == 1)
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

    /// Requests made via `perform(_:)`, in order.
    private var _requests: [URLRequest] = []
    var requests: [URLRequest] {
        lock.withLock { _requests }
    }

    /// URLs requested via `perform(_:)`. Use this to verify which endpoints were called.
    var requestedURLs: [URL] {
        requests.compactMap(\.url)
    }

    /// Handler for generating response data based on request URL.
    /// Can throw to simulate failures for specific URLs.
    /// Used by both `perform()` and `download()` methods.
    var urlResponseHandler: ((URL) throws -> Data) = { _ in Data() }

    func perform(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = try #require(urlRequest.url)

        lock.withLock {
            getCallCount += 1
            _requests.append(urlRequest)
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
