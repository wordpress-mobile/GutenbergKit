import Foundation
import Testing

@testable import GutenbergKit

/// Serialized because a library does its file I/O on the concurrency thread pool that every test in the
/// run shares, and holds a lock that every library shares while it changes storage. Run in parallel,
/// these tests tie up those threads long enough that a test timing something else, such as a server's
/// read timeout, sees a delay the server didn't cause.
@Suite(.serialized)
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

        // The cache policy decides whether to fetch the manifest, not how to use the response
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)

        // First, fetch the manifest and create a bundle on disk
        let originalManifest = try await library.fetchManifest()

        let bundle = try await library.buildBundle(for: originalManifest)

        // Change the stored copy, so the test can tell it apart from a freshly parsed response
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

    @Test("downloadAssetBundle makes a bundle the latest again when the site goes back to its manifest")
    func downloadAssetBundleRestoresReturningBundle() async throws {
        let (library, mockClient) = try await makeLibraryWithBundle(cachePolicy: .maxAge(0))
        let original = try #require(try await library.readAssetBundles().first)
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "2"))
        let changed = try await library.downloadAssetBundle()

        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        let restored = try await library.downloadAssetBundle()

        #expect(restored.id == original.id)
        #expect(mockClient.downloadCallCount == 2)
        #expect(try await library.readAssetBundles().map(\.id) == [original.id, changed.id])
    }

    @Test(
        "downloadAssetBundle returns the same bundle, and adds none, when its manifest and assets are unchanged",
        arguments: [EditorCachePolicy.maxAge(0), .ignore]
    )
    func downloadAssetBundleLeavesUnchangedBundleAsItWas(cachePolicy: EditorCachePolicy) async throws {
        let (library, _) = try await makeLibraryWithBundle(cachePolicy: cachePolicy)
        let bundle = try #require(try await library.readAssetBundles().first)

        let checked = try await library.downloadAssetBundle()

        // A host comparing dependencies sees no change, and `downloadDate` is still the first download's
        #expect(checked == bundle)
        #expect(checked.downloadDate == bundle.downloadDate)
        #expect(try await library.readAssetBundles() == [bundle])
    }

    @Test("under .ignore, changed assets go into a new bundle, and the bundle on disk is left untouched")
    func downloadAssetBundleBuildsNewBundleForChangedAssetsUnderIgnore() async throws {
        let (library, mockClient) = try await makeLibraryWithBundle(cachePolicy: .ignore)
        let bundle = try #require(try await library.readAssetBundles().first)

        mockClient.urlResponseHandler = Self.responses(
            forManifest: Self.manifestJSON(scriptVersion: "1"),
            assetContent: "new content"
        )
        let refreshed = try await library.downloadAssetBundle()

        #expect(mockClient.downloadCallCount == 2)
        #expect(try refreshed.assetData(for: Self.scriptURL) == Data("new content".utf8))
        // An editor may still be reading the bundle it was given
        #expect(try bundle.assetData(for: Self.scriptURL) == Data("mock content".utf8))
        // Two bundles for one manifest, and `!=` tells them apart for a host comparing dependencies
        #expect(refreshed.id == bundle.id)
        #expect(refreshed != bundle)
        #expect(try await library.readAssetBundles().map(\.bundleRoot) == [refreshed.bundleRoot, bundle.bundleRoot])
        #expect(await library.existingBundle(forManifestChecksum: bundle.id)?.bundleRoot == refreshed.bundleRoot)
    }

    @Test(
        "under .ignore, an unchanged asset shares disk space with the copy already on disk",
        .enabled(if: EditorAssetLibraryTests.storageSupportsClones)
    )
    func unchangedAssetSharesSpaceWithCopyOnDiskUnderIgnore() async throws {
        let style = URL(string: "https://example.com/plugin.css")!
        let manifest = Self.manifestJSON(scriptVersion: "1", style: style.absoluteString)
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(forManifest: manifest)
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)
        let bundle = try await library.downloadAssetBundle()

        // A fresh download isn't a clone, so it shares none of its space
        #expect(try Self.unsharedSize(of: bundle.assetDataPath(for: Self.scriptURL)) > 0)

        // The stylesheet changes, and the script doesn't
        mockClient.urlResponseHandler = { url in
            if url.path.contains("editor-assets") {
                return Data(manifest.utf8)
            }
            return Data(url.path == "/plugin.css" ? "new content".utf8 : "mock content".utf8)
        }
        let refreshed = try await library.downloadAssetBundle()

        #expect(mockClient.downloadCallCount == 4)
        #expect(refreshed != bundle)
        #expect(try refreshed.assetData(for: Self.scriptURL) == Data("mock content".utf8))
        #expect(try Self.unsharedSize(of: refreshed.assetDataPath(for: Self.scriptURL)) == 0)
        #expect(try refreshed.assetData(for: style) == Data("new content".utf8))
        #expect(try Self.unsharedSize(of: refreshed.assetDataPath(for: style)) > 0)
        // The bundle an editor may be reading is left as it was
        #expect(try bundle.assetData(for: style) == Data("mock content".utf8))
        // Swapping the download for a clone leaves no extra file behind
        let assets = refreshed.assetDataPath(for: style).deletingLastPathComponent()
        #expect(try FileManager.default.contentsOfDirectory(atPath: assets.path).count == 2)
    }

    @Test(
        "under .ignore, an unchanged asset of a changed manifest shares disk space with another bundle's copy",
        .enabled(if: EditorAssetLibraryTests.storageSupportsClones)
    )
    func unchangedAssetOfChangedManifestSharesSpaceUnderIgnore() async throws {
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)
        let bundle = try await library.downloadAssetBundle()

        // The site adds a stylesheet, and the script is the same
        let style = URL(string: "https://example.com/plugin.css")!
        let manifest = Self.manifestJSON(scriptVersion: "1", style: style.absoluteString)
        mockClient.urlResponseHandler = { url in
            if url.path.contains("editor-assets") {
                return Data(manifest.utf8)
            }
            return Data(url.path == "/plugin.css" ? "new content".utf8 : "mock content".utf8)
        }
        let changed = try await library.downloadAssetBundle()

        // The script is still downloaded: comparing the download is how the library knows it's unchanged
        #expect(mockClient.downloadCallCount == 3)
        #expect(changed.id != bundle.id)
        #expect(try changed.assetData(for: Self.scriptURL) == Data("mock content".utf8))
        #expect(try Self.unsharedSize(of: changed.assetDataPath(for: Self.scriptURL)) == 0)
        #expect(try Self.unsharedSize(of: changed.assetDataPath(for: style)) > 0)
    }

    @Test("under .ignore, an asset that fails to download is copied from the latest bundle")
    func newBundleUnderIgnoreKeepsAssetThatFailsToDownloadAgain() async throws {
        let style = "https://example.com/plugin.css"
        let manifest = Self.manifestJSON(scriptVersion: "1", style: style)
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(forManifest: manifest)
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)
        let bundle = try await library.downloadAssetBundle()

        mockClient.urlResponseHandler = { url in
            if url.path.contains("editor-assets") {
                return Data(manifest.utf8)
            }
            guard url.path != "/plugin.css" else { throw URLError(.timedOut) }
            return Data("new content".utf8)
        }
        let refreshed = try await library.downloadAssetBundle()

        #expect(refreshed != bundle)
        #expect(try refreshed.assetData(for: Self.scriptURL) == Data("new content".utf8))
        #expect(try refreshed.assetData(for: URL(string: style)!) == Data("mock content".utf8))
    }

    @Test("under .ignore, an asset that fails to download is copied from an earlier bundle when the latest lacks it")
    func assetThatFailsToDownloadComesFromBundleSiteWentBackTo() async throws {
        let mockClient = EditorAssetLibraryMockHTTPClient()
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        let earlier = try await library.downloadAssetBundle()
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "2"))
        _ = try await library.downloadAssetBundle()

        // The site goes back to the earlier manifest. Only the earlier bundle has its script, not the latest
        mockClient.urlResponseHandler = { url in
            guard url.path.contains("editor-assets") else { throw URLError(.timedOut) }
            return Data(Self.manifestJSON(scriptVersion: "1").utf8)
        }
        let refreshed = try await library.downloadAssetBundle()

        #expect(try refreshed.assetData(for: Self.scriptURL) == Data("mock content".utf8))
        #expect(refreshed == earlier)
    }

    @Test("under .ignore, assets that share a path and fail to download each keep their copy on disk")
    func assetsSharingAPathKeepTheirCopiesOnDiskWhenDownloadsFail() async throws {
        // The same path on two hosts. A bundle stores each under its full URL, so they're two assets
        let manifest = """
            {
                "scripts": "<script src=\\"https://example.com/plugin.js?ver=1\\"></script><script src=\\"https://cdn.example.com/plugin.js?ver=1\\"></script>",
                "styles": "",
                "allowed_block_types": ["core/paragraph"]
            }
            """
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(forManifest: manifest)
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)
        let bundle = try await library.downloadAssetBundle()

        mockClient.urlResponseHandler = { url in
            guard url.path.contains("editor-assets") else { throw URLError(.timedOut) }
            return Data(manifest.utf8)
        }
        let refreshed = try await library.downloadAssetBundle()

        #expect(try refreshed.assetData(for: Self.scriptURL) == Data("mock content".utf8))
        #expect(try refreshed.assetData(for: URL(string: "https://cdn.example.com/plugin.js?ver=1")!) == Data("mock content".utf8))
        #expect(refreshed == bundle)
    }

    @Test("under .ignore, downloadAssetBundle downloads the assets again even when they turn out the same")
    func downloadAssetBundleDownloadsIdenticalAssetsAgainUnderIgnore() async throws {
        let (library, mockClient) = try await makeLibraryWithBundle(cachePolicy: .ignore)

        _ = try await library.downloadAssetBundle()

        #expect(mockClient.downloadCallCount == 2)
    }

    @Test("under .ignore, an asset that fails to download again keeps the copy on disk")
    func downloadAssetBundleKeepsAssetThatFailsToDownloadAgain() async throws {
        let (library, mockClient) = try await makeLibraryWithBundle(cachePolicy: .ignore)
        let bundle = try #require(try await library.readAssetBundles().first)

        mockClient.urlResponseHandler = { url in
            guard url.path.contains("editor-assets") else { throw URLError(.timedOut) }
            return Data(Self.manifestJSON(scriptVersion: "1").utf8)
        }
        let refreshed = try await library.downloadAssetBundle()

        #expect(mockClient.downloadCallCount == 2)
        #expect(refreshed == bundle)
        #expect(try refreshed.assetData(for: Self.scriptURL) == Data("mock content".utf8))
    }

    /// The assets are unchanged, so the bundle on disk is kept. Its headers are still updated: an editor
    /// should be served each asset with the type the server sends now.
    @Test("under .ignore, a kept bundle records the headers its assets came back with")
    func unchangedBundleTakesNewHeadersUnderIgnore() async throws {
        let storageRoot = URL.randomTemporaryDirectory
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.assetResponseHeaders = { _ in ["Content-Type": "text/plain"] }
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore, storageRoot: storageRoot)
        let bundle = try await library.downloadAssetBundle()

        // The server now sends the right type: the same file, served as JavaScript
        mockClient.assetResponseHeaders = { _ in ["Content-Type": "application/javascript"] }
        let refreshed = try await library.downloadAssetBundle()

        // The same bundle directory, but `!=`, so a host comparing dependencies sees the change
        #expect(refreshed.bundleRoot == bundle.bundleRoot)
        #expect(refreshed != bundle)
        #expect(refreshed.contentType(forAssetAt: Self.scriptURL) == "application/javascript")
        #expect(
            try await library.readAssetBundles().first?.contentType(forAssetAt: Self.scriptURL)
                == "application/javascript"
        )
        #expect(try FileManager.default.contentsOfDirectory(atPath: storageRoot.path).count == 1)
    }

    /// Several links to one asset, over `http` or `https`, mean one file to download.
    @Test("an asset a manifest links more than once is downloaded once, and keeps its headers")
    func assetLinkedMoreThanOnceIsDownloadedOnce() async throws {
        let manifest = """
            {
                "scripts": "<script src=\\"https://example.com/plugin.js?ver=1\\"></script><script src=\\"https://example.com/plugin.js?ver=1\\"></script><script src=\\"http://example.com/plugin.js?ver=1\\"></script>",
                "styles": "",
                "allowed_block_types": ["core/paragraph"]
            }
            """
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.assetResponseHeaders = { _ in ["Content-Type": "application/javascript"] }
        mockClient.urlResponseHandler = Self.responses(forManifest: manifest)
        let library = makeLibrary(httpClient: mockClient)

        let bundle = try await library.downloadAssetBundle()

        #expect(mockClient.downloadCallCount == 1)
        #expect(bundle.contentType(forAssetAt: Self.scriptURL) == "application/javascript")
        #expect(await library.missingAssets(of: bundle).isEmpty)
    }

    /// An `http` request may not be allowed at all, so the library downloads the `https` link.
    @Test("an asset a manifest links over both http and https is downloaded over https")
    func assetLinkedOverBothSchemesIsAskedForOverHTTPS() async throws {
        let manifest = """
            {
                "scripts": "<script src=\\"http://example.com/plugin.js?ver=1\\"></script><script src=\\"https://example.com/plugin.js?ver=1\\"></script>",
                "styles": "",
                "allowed_block_types": ["core/paragraph"]
            }
            """
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(forManifest: manifest)
        let library = makeLibrary(httpClient: mockClient)

        let bundle = try await library.downloadAssetBundle()

        #expect(mockClient.downloadedURLs == [Self.scriptURL])
        #expect(await library.missingAssets(of: bundle).isEmpty)
    }

    /// A copy downloaded over `http` isn't reused for an `https` link, so the asset is downloaded again.
    @Test("a changed manifest's bundle doesn't reuse an asset the latest bundle downloaded over another scheme")
    func changedBundleAsksAgainForAssetLinkedByAnotherScheme() async throws {
        func manifest(scheme: String, blockType: String) -> String {
            """
            {
                "scripts": "<script src=\\"\(scheme)://example.com/plugin.js?ver=1\\"></script>",
                "styles": "",
                "allowed_block_types": ["\(blockType)"]
            }
            """
        }
        let mockClient = EditorAssetLibraryMockHTTPClient()
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(0))
        mockClient.urlResponseHandler = Self.responses(forManifest: manifest(scheme: "http", blockType: "one"))
        _ = try await library.downloadAssetBundle()

        mockClient.urlResponseHandler = Self.responses(
            forManifest: manifest(scheme: "https", blockType: "two"),
            assetContent: "new content"
        )
        let changed = try await library.downloadAssetBundle()

        #expect(mockClient.downloadedURLs.last == Self.scriptURL)
        #expect(try changed.assetData(for: Self.scriptURL) == Data("new content".utf8))
    }

    /// Another library can update a bundle's `manifest.json` after this library reads the bundle and before it
    /// marks it as the latest. Here, a refresh records a new type for the script. Marking must not overwrite that.
    @Test("a check that keeps a bundle preserves headers another library recorded in it meanwhile")
    func checkKeepsWhatAnotherLibraryRecordedInBundle() async throws {
        let (library, _) = try await makeLibraryWithBundle(cachePolicy: .maxAge(0))
        let bundle = try #require(try await library.readAssetBundles().first)
        let scriptKey = EditorAssetBundle.assetKey(for: Self.scriptURL)

        // Progress is reported after the check finds the bundle on disk, and before it marks it
        let checked = try await library.downloadAssetBundle { _ in
            try? EditorAssetBundle(
                manifest: bundle.manifest,
                downloadDate: bundle.downloadDate,
                lastCheckedDate: bundle.lastCheckedDate,
                assetHeaders: [scriptKey: EditorAssetBundle.AssetHeaders(contentType: "application/javascript")],
                bundleRoot: bundle.bundleRoot
            ).writeManifest()
        }

        #expect(checked.contentType(forAssetAt: Self.scriptURL) == "application/javascript")
        #expect(
            try await library.readAssetBundles().first?.contentType(forAssetAt: Self.scriptURL)
                == "application/javascript"
        )
    }

    /// The build copies the stylesheet from the bundle on disk without downloading it, so it learns nothing
    /// new about it. Headers another library records for the stylesheet during the build must survive,
    /// whether the build keeps that bundle or publishes a new one.
    @Test(
        "a build takes a copied asset's headers from the bundle on disk as they are when the build finishes",
        arguments: [true, false]
    )
    func buildRecordsKeptAssetsAsBundleOnDiskRecordsThem(scriptDownloads: Bool) async throws {
        let style = URL(string: "https://example.com/plugin.css")!
        let manifest = Self.manifestJSON(scriptVersion: "1", style: style.absoluteString)
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { url in
            if url.path.contains("editor-assets") {
                return Data(manifest.utf8)
            }
            guard url.path == style.path else { throw URLError(.timedOut) }
            return Data("mock content".utf8)
        }
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(0))
        let gapped = try await library.downloadAssetBundle()
        #expect(await library.missingAssets(of: gapped) == [Self.scriptURL])

        // While the check retries the script, another library's refresh records a new type for the
        // stylesheet
        mockClient.urlResponseHandler = { url in
            if url.path.contains("editor-assets") {
                return Data(manifest.utf8)
            }
            try EditorAssetBundle(
                manifest: gapped.manifest,
                downloadDate: gapped.downloadDate,
                lastCheckedDate: gapped.lastCheckedDate,
                assetHeaders: [
                    EditorAssetBundle.assetKey(for: style): EditorAssetBundle.AssetHeaders(contentType: "text/css")
                ],
                bundleRoot: gapped.bundleRoot
            ).writeManifest()
            guard scriptDownloads else { throw URLError(.timedOut) }
            return Data("mock content".utf8)
        }
        let checked = try await library.downloadAssetBundle()

        #expect((checked.bundleRoot == gapped.bundleRoot) == !scriptDownloads)
        #expect(checked.contentType(forAssetAt: style) == "text/css")
    }

    /// Reading a bundle doesn't hand it out. `readLatestAssetBundle()` skips one that's missing an asset,
    /// and `cleanup()` can still remove it.
    @Test("cleanup removes a bundle that was read but skipped for missing an asset")
    func cleanupRemovesBundlePassedOverForMissingAsset() async throws {
        let storageRoot = URL.randomTemporaryDirectory
        let planted = try await plantBundles(forManifests: [Self.manifestJSON(scriptVersion: "1")], in: storageRoot)
        try FileManager.default.removeItem(at: planted[0].assetDataPath(for: Self.scriptURL))
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        let library = makeLibrary(httpClient: mockClient, storageRoot: storageRoot)

        #expect(try await library.readLatestAssetBundle() == nil)
        let repaired = try await library.downloadAssetBundle()
        try await library.cleanup()

        #expect(try await library.readAssetBundles().map(\.bundleRoot) == [repaired.bundleRoot])
    }

    @Test("downloadAssetBundle retries an asset that an earlier build of the bundle failed to download")
    func downloadAssetBundleRepairsMissingAsset() async throws {
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { url in
            guard url.path.contains("editor-assets") else { throw URLError(.timedOut) }
            return Data(Self.manifestJSON(scriptVersion: "1").utf8)
        }
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(0))
        let gapped = try await library.downloadAssetBundle()
        #expect(!gapped.hasAssetData(for: Self.scriptURL))

        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        let repaired = try await library.downloadAssetBundle()

        #expect(repaired.id == gapped.id)
        #expect(repaired.hasAssetData(for: Self.scriptURL))
        #expect(mockClient.downloadCallCount == 2)
        #expect(try await library.readAssetBundles().first?.bundleRoot == repaired.bundleRoot)
    }

    /// A bundle as the previous release stored it. Its `manifest.json` holds only the manifest and a download
    /// date, and its assets are at their URLs' paths, where bundles no longer look. So it reads as missing
    /// every asset, and is repaired like any such bundle: the assets are downloaded once more, into a new
    /// bundle beside it.
    @Test("a bundle stored by the previous release reads as missing its assets, which are downloaded again once")
    func bundleAsLastReleaseStoredItIsDownloadedAgain() async throws {
        let storageRoot = URL.randomTemporaryDirectory
        let script = URL(string: "https://example.com/wp-content/plugins/a-plugin/build/index.js?ver=1.2")!
        let style = URL(string: "https://example.com/wp-content/plugins/a-plugin/build/style.css?ver=1.2")!
        let concatenated = URL(string: "https://s0.example.com/_static/??/a.js,/b.js")!
        let manifestJSON = """
            {
                "scripts": "<script src=\\"\(script.absoluteString)\\"></script><script src=\\"\(concatenated.absoluteString)\\"></script>",
                "styles": "<link rel=\\"stylesheet\\" href=\\"\(style.absoluteString)\\">",
                "allowed_block_types": ["a-plugin/block"]
            }
            """
        let manifest = try LocalEditorAssetManifest(
            remoteManifest: RemoteEditorAssetManifest(data: Data(manifestJSON.utf8))
        )
        let bundleRoot = storageRoot.appending(path: manifest.checksum)
        let downloadDate = Date(timeIntervalSinceReferenceDate: 780_000_000)
        try FileManager.default.createDirectory(
            at: bundleRoot.appending(path: "wp-content/plugins/a-plugin/build"),
            withIntermediateDirectories: true
        )
        try JSONSerialization.data(withJSONObject: [
            "manifest": try JSONSerialization.jsonObject(with: JSONEncoder().encode(manifest)),
            "downloadDate": downloadDate.timeIntervalSinceReferenceDate,
        ]).write(to: bundleRoot.appending(path: "manifest.json"))
        try JSONEncoder()
            .encode(manifest.buildEditorRepresentation(for: Self.testConfiguration))
            .write(to: bundleRoot.appending(path: "editor-representation.json"))
        try Data("script".utf8).write(to: bundleRoot.appending(path: "wp-content/plugins/a-plugin/build/index.js"))
        try Data("style".utf8).write(to: bundleRoot.appending(path: "wp-content/plugins/a-plugin/build/style.css"))

        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in throw URLError(.notConnectedToInternet) }
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .always, storageRoot: storageRoot)

        // It still reads as the site's bundle, with its original download date
        let onDisk = try #require(try await library.readAssetBundles().first)

        #expect(onDisk.id == manifest.checksum)
        #expect(onDisk.downloadDate == downloadDate)
        #expect(onDisk.lastCheckedDate == nil)
        #expect(await library.missingAssets(of: onDisk) == [script, concatenated, style])
        // It's missing assets, so `readLatestAssetBundle()` doesn't return it
        #expect(try await library.readLatestAssetBundle() == nil)

        // Once the site is reachable, every asset is downloaded
        mockClient.urlResponseHandler = Self.responses(forManifest: manifestJSON, assetContent: "new content")
        let repaired = try await library.downloadAssetBundle()

        #expect(Set(mockClient.downloadedURLs) == [script, style, concatenated])
        #expect(repaired.id == onDisk.id)
        #expect(repaired.bundleRoot != onDisk.bundleRoot)
        #expect(try repaired.assetData(for: script) == Data("new content".utf8))
        #expect(await library.missingAssets(of: repaired).isEmpty)

        // The repaired bundle is complete, so it's returned without downloading anything again
        #expect(try await library.readLatestAssetBundle() == repaired)
        #expect(mockClient.downloadCallCount == 3)
    }

    /// A refresh whose assets change publishes a new bundle. A check of the same manifest that was already
    /// running doesn't know about it. What that check found or built is older, so it must not be put back
    /// in front of the refresh's bundle.
    @Test("a check that's overtaken by a refresh returns the refresh's bundle instead of its own")
    func checkOvertakenByRefreshGivesRefreshedBundle() async throws {
        let storageRoot = URL.randomTemporaryDirectory
        let manifest = Self.manifestJSON(scriptVersion: "1")
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { url in
            guard url.path.contains("editor-assets") else { throw URLError(.timedOut) }
            return Data(manifest.utf8)
        }
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(0), storageRoot: storageRoot)
        let refreshing = makeLibrary(httpClient: mockClient, cachePolicy: .ignore, storageRoot: storageRoot)
        let gapped = try await library.downloadAssetBundle()
        #expect(!gapped.hasAssetData(for: Self.scriptURL))

        // Progress is reported once the check's retry of the script has failed again. Before the check
        // finishes, a refresh downloads the script and publishes a bundle that has it.
        let refresh = OnceOnlyAsync {
            mockClient.urlResponseHandler = Self.responses(forManifest: manifest)
            _ = try? await refreshing.downloadAssetBundle()
        }
        let checked = try await library.downloadAssetBundle { _ in await refresh.run() }

        #expect(checked.bundleRoot != gapped.bundleRoot)
        #expect(checked.hasAssetData(for: Self.scriptURL))
        #expect(try await library.readAssetBundles().first?.bundleRoot == checked.bundleRoot)
    }

    /// A bundle's date is when its manifest was fetched, not when the bundle finished building, which can
    /// be much later. The cache policy measures the bundle's age from that date, and the bundle with the
    /// newest date is the site's latest.
    @Test("a bundle is dated by when its manifest was fetched, whether it's built or kept")
    func bundleIsDatedByManifestFetch() async throws {
        let assetRequested = RecordedDate()
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { url in
            if url.path.contains("editor-assets") {
                return Data(Self.manifestJSON(scriptVersion: "1").utf8)
            }
            assetRequested.recordNow()
            return Data("mock content".utf8)
        }
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(0))

        let built = try await library.downloadAssetBundle()

        #expect(try #require(built.lastCheckedDate) <= #require(assetRequested.date))

        // A check that keeps the bundle reports its progress before it marks it
        let progressReported = RecordedDate()
        let checked = try await library.downloadAssetBundle { _ in progressReported.recordNow() }

        #expect(checked == built)
        #expect(try #require(checked.lastCheckedDate) > #require(built.lastCheckedDate))
        #expect(try #require(checked.lastCheckedDate) <= #require(progressReported.date))
    }

    /// The site's manifest changes while the earlier manifest's bundle is still building, and a refresh
    /// builds the new manifest's bundle first. The slower build is of the older manifest, so it stays behind.
    @Test("a bundle whose manifest was fetched before another's stays behind it, however late it's built")
    func bundleOfEarlierManifestStaysBehindLaterOne() async throws {
        let storageRoot = URL.randomTemporaryDirectory
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(0), storageRoot: storageRoot)
        let refreshing = makeLibrary(httpClient: mockClient, cachePolicy: .ignore, storageRoot: storageRoot)

        let refresh = OnceOnlyAsync {
            mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "2"))
            _ = try? await refreshing.downloadAssetBundle()
        }
        let built = try await library.downloadAssetBundle { _ in await refresh.run() }

        let bundles = try await library.readAssetBundles()
        #expect(bundles.count == 2)
        #expect(bundles.first?.id != built.id)
        #expect(bundles.last?.bundleRoot == built.bundleRoot)
    }

    /// While a refresh downloads, another library checks the manifest and finds the bundle on disk still
    /// matches it. That match is more recent than the refresh's own fetch, but the refresh's bundle still
    /// replaces the bundle on disk, so it must come ahead of it.
    @Test("a replacement bundle comes ahead of the one it replaces, even if that one was matched during the build")
    func bundleThatReplacesAnotherComesAheadOfIt() async throws {
        let (library, mockClient) = try await makeLibraryWithBundle(cachePolicy: .ignore)
        let bundle = try #require(try await library.readAssetBundles().first)

        let rematch = OnceOnly { try? self.backdate(bundle, by: 0) }
        mockClient.urlResponseHandler = { url in
            if url.path.contains("editor-assets") {
                return Data(Self.manifestJSON(scriptVersion: "1").utf8)
            }
            rematch.run()
            return Data("new content".utf8)
        }
        let refreshed = try await library.downloadAssetBundle()

        #expect(refreshed.bundleRoot != bundle.bundleRoot)
        #expect(try await library.readAssetBundles().first?.bundleRoot == refreshed.bundleRoot)
        #expect(await library.existingBundle(forManifestChecksum: bundle.id)?.bundleRoot == refreshed.bundleRoot)
    }

    /// Another library may record a more recent match for the bundle than this check's. Here it does so after
    /// this check fetches the manifest, and before it marks the bundle.
    @Test("a check never moves a bundle's last-matched date backwards")
    func checkDoesNotMoveBundleBackInTime() async throws {
        let (library, _) = try await makeLibraryWithBundle(cachePolicy: .maxAge(0))
        let bundle = try #require(try await library.readAssetBundles().first)

        let otherMatch = RecordedDate()

        let checked = try await library.downloadAssetBundle { _ in
            otherMatch.recordNow()
            try? EditorAssetBundle(
                manifest: bundle.manifest,
                downloadDate: bundle.downloadDate,
                lastCheckedDate: otherMatch.date,
                bundleRoot: bundle.bundleRoot
            ).writeManifest()
        }

        #expect(checked.lastCheckedDate == otherMatch.date)
        #expect(try await library.readAssetBundles().first?.lastCheckedDate == otherMatch.date)
    }

    /// The caller still gets the headers a refresh found, even when they can't be written to disk.
    @Test("a bundle kept after a refresh has its assets' new headers even when they can't be saved")
    func keptBundleHasNewHeadersWhenTheyCannotBeRecorded() async throws {
        let (library, mockClient) = try await makeLibraryWithBundle(cachePolicy: .ignore)
        let bundle = try #require(try await library.readAssetBundles().first)
        mockClient.assetResponseHeaders = { _ in ["Content-Type": "application/javascript"] }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: bundle.bundleRoot.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundle.bundleRoot.path)
        }

        let refreshed = try await library.downloadAssetBundle()

        #expect(refreshed.bundleRoot == bundle.bundleRoot)
        #expect(refreshed.contentType(forAssetAt: Self.scriptURL) == "application/javascript")
    }

    /// An editor may be reading the bundle that's missing the asset, so the retry doesn't write into it.
    @Test("a check that retries a missing asset builds a new bundle and leaves the old one untouched")
    func repairLeavesBundleOnDiskAsItWas() async throws {
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { url in
            guard url.path.contains("editor-assets") else { throw URLError(.timedOut) }
            return Data(Self.manifestJSON(scriptVersion: "1").utf8)
        }
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(0))
        let gapped = try await library.downloadAssetBundle()

        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        let repaired = try await library.downloadAssetBundle()

        #expect(repaired.bundleRoot != gapped.bundleRoot)
        #expect(!gapped.hasAssetData(for: Self.scriptURL))
        #expect((try? gapped.getEditorRepresentation() as EditorAssetBundle.EditorRepresentation) != nil)
    }

    @Test("a check whose retry of a missing asset fails again keeps the bundle, and adds no other")
    func repairThatGainsNothingKeepsBundle() async throws {
        let storageRoot = URL.randomTemporaryDirectory
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { url in
            guard url.path.contains("editor-assets") else { throw URLError(.timedOut) }
            return Data(Self.manifestJSON(scriptVersion: "1").utf8)
        }
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(0), storageRoot: storageRoot)
        let gapped = try await library.downloadAssetBundle()

        let checked = try await library.downloadAssetBundle()

        #expect(checked == gapped)
        #expect(mockClient.downloadCallCount == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: storageRoot.path).count == 1)
    }

    /// Assets are downloaded into a temporary directory, never into the library's storage, so a deleted
    /// bundle stays deleted.
    @Test("a bundle deleted while a check downloads what it's missing doesn't come back as loose files")
    func deletedBundleIsNotRecreatedByDownload() async throws {
        let manifest = Self.manifestJSON(scriptVersion: "1")
        let storageRoot = URL.randomTemporaryDirectory
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { url in
            guard url.path.contains("editor-assets") else { throw URLError(.timedOut) }
            return Data(manifest.utf8)
        }
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(0), storageRoot: storageRoot)
        let gapped = try await library.downloadAssetBundle()

        // Move the bundle to a directory that a new build of the manifest wouldn't write to
        let moved = storageRoot.appending(path: "\(gapped.id)-moved")
        try FileManager.default.moveItem(at: gapped.bundleRoot, to: moved)

        // Delete the bundle during the first download of its missing script
        let deletion = OnceOnly { try? FileManager.default.removeItem(at: moved) }
        mockClient.urlResponseHandler = { url in
            if url.path.contains("editor-assets") {
                return Data(manifest.utf8)
            }
            deletion.run()
            return Data("mock content".utf8)
        }
        let rebuilt = try await library.downloadAssetBundle()

        #expect(rebuilt.hasAssetData(for: Self.scriptURL))
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: storageRoot.path)
                == [rebuilt.bundleRoot.lastPathComponent]
        )
    }

    @Test("a missing asset that a check downloads keeps the headers it came with")
    func repairedAssetKeepsItsHeaders() async throws {
        let style = URL(string: "https://example.com/plugin.css")!
        let manifest = Self.manifestJSON(scriptVersion: "1", style: style.absoluteString)
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.assetResponseHeaders = { $0.path == style.path ? ["Content-Type": "text/css"] : [:] }
        mockClient.urlResponseHandler = { url in
            if url.path.contains("editor-assets") {
                return Data(manifest.utf8)
            }
            guard url.path != style.path else { throw URLError(.timedOut) }
            return Data("mock content".utf8)
        }
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(0))
        let gapped = try await library.downloadAssetBundle()
        #expect(!gapped.hasAssetData(for: style))

        mockClient.urlResponseHandler = Self.responses(forManifest: manifest)
        let repaired = try await library.downloadAssetBundle()

        #expect(repaired.id == gapped.id)
        #expect(repaired.contentType(forAssetAt: style) == "text/css")
        #expect(try await library.readAssetBundles().first?.contentType(forAssetAt: style) == "text/css")
    }

    @Test(
        "a changed manifest's bundle copies the assets whose URL hasn't changed from the latest bundle",
        arguments: [EditorCachePolicy.always, .maxAge(60)]
    )
    func changedBundleCarriesUnchangedAssetsForward(cachePolicy: EditorCachePolicy) async throws {
        let style = "https://example.com/plugin.css?ver=1"
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1", style: style))
        let library = makeLibrary(httpClient: mockClient, cachePolicy: cachePolicy)
        _ = try await library.downloadAssetBundle()

        mockClient.urlResponseHandler = Self.responses(
            forManifest: Self.manifestJSON(scriptVersion: "2", style: style),
            assetContent: "new content"
        )
        let changed = try await library.downloadAssetBundle()

        let changedScript = URL(string: "https://example.com/plugin.js?ver=2")!
        #expect(mockClient.downloadedURLs.filter { $0.path == "/plugin.css" }.count == 1)
        #expect(mockClient.downloadedURLs.contains(changedScript))
        #expect(try changed.assetData(for: URL(string: style)!) == Data("mock content".utf8))
        #expect(try changed.assetData(for: changedScript) == Data("new content".utf8))
    }

    @Test("under .ignore, a changed manifest's bundle downloads every asset, even one whose URL hasn't changed")
    func changedBundleDownloadsEveryAssetUnderIgnore() async throws {
        let style = "https://example.com/plugin.css?ver=1"
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1", style: style))
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)
        _ = try await library.downloadAssetBundle()

        mockClient.urlResponseHandler = Self.responses(
            forManifest: Self.manifestJSON(scriptVersion: "2", style: style),
            assetContent: "new content"
        )
        let changed = try await library.downloadAssetBundle()

        #expect(mockClient.downloadedURLs.filter { $0.path == "/plugin.css" }.count == 2)
        #expect(try changed.assetData(for: URL(string: style)!) == Data("new content".utf8))
    }

    @Test(
        "a changed manifest's bundle downloads an asset again when its URL has no version",
        arguments: [
            "https://example.com/plugin.css",
            "https://example.com/plugin.css?ver=",
            "https://example.com/plugin.css?minify=false",
        ]
    )
    func changedBundleDownloadsUnversionedAssetsAgain(style: String) async throws {
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1", style: style))
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(60))
        _ = try await library.downloadAssetBundle()

        mockClient.urlResponseHandler = Self.responses(
            forManifest: Self.manifestJSON(scriptVersion: "2", style: style),
            assetContent: "new content"
        )
        let changed = try await library.downloadAssetBundle()

        #expect(mockClient.downloadedURLs.filter { $0.path == "/plugin.css" }.count == 2)
        #expect(try changed.assetData(for: URL(string: style)!) == Data("new content".utf8))
    }

    /// The editor is served each asset with the `Content-Type` its server sent, so the type must stay with the
    /// file whether it was downloaded or copied for an unchanged URL.
    @Test("an asset's Content-Type is kept with it, from one bundle to the next")
    func assetContentTypeIsKeptWithAsset() async throws {
        let style = URL(string: "https://example.com/plugin.css")!
        let script = URL(string: "https://example.com/plugin.js?ver=1")!
        let secondScript = URL(string: "https://example.com/second.js?ver=1")!
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.assetResponseHeaders = { url in
            switch url.path {
            case style.path: ["Content-Type": "text/css; charset=utf-8"]
            case script.path: ["Content-Type": "application/javascript"]
            default: [:]
            }
        }
        func manifest(extraScript: Bool) -> String {
            let scripts = [script] + (extraScript ? [secondScript] : [])
            let tags = scripts.map { "<script src=\\\"\($0.absoluteString)\\\"></script>" }.joined()
            return """
                {
                    "scripts": "\(tags)",
                    "styles": "<link rel=\\"stylesheet\\" href=\\"\(style.absoluteString)\\">",
                    "allowed_block_types": ["content-type-test"]
                }
                """
        }
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(60))
        mockClient.urlResponseHandler = Self.responses(forManifest: manifest(extraScript: false))
        let first = try await library.downloadAssetBundle()

        // A changed manifest: the script is copied for its unchanged URL, and the unversioned stylesheet is
        // downloaded again
        mockClient.urlResponseHandler = Self.responses(forManifest: manifest(extraScript: true))
        let second = try await library.downloadAssetBundle()

        #expect(second.id != first.id)
        for bundle in [first, second] {
            #expect(bundle.contentType(forAssetAt: style) == "text/css; charset=utf-8")
            #expect(bundle.contentType(forAssetAt: script) == "application/javascript")
        }
        // Its server sent no `Content-Type`, so none is recorded
        #expect(second.contentType(forAssetAt: secondScript) == nil)
    }

    @Test("a changed manifest's bundle keeps the earlier copy of an unversioned asset that fails to download")
    func changedBundleKeepsUnversionedAssetThatFailsToDownload() async throws {
        let style = URL(string: "https://example.com/plugin.css")!
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.assetResponseHeaders = { $0.path == style.path ? ["Content-Type": "text/css"] : [:] }
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(60))
        mockClient.urlResponseHandler = Self.responses(
            forManifest: Self.manifestJSON(scriptVersion: "1", style: style.absoluteString)
        )
        _ = try await library.downloadAssetBundle()

        // The server now sends the stylesheet with another type, but the download fails
        mockClient.assetResponseHeaders = { $0.path == style.path ? ["Content-Type": "text/plain"] : [:] }
        mockClient.urlResponseHandler = { url in
            if url.path.contains("editor-assets") {
                return Data(Self.manifestJSON(scriptVersion: "2", style: style.absoluteString).utf8)
            }
            guard url.path != style.path else { throw URLError(.timedOut) }
            return Data("new content".utf8)
        }
        let changed = try await library.downloadAssetBundle()

        #expect(try changed.assetData(for: style) == Data("mock content".utf8))
        // It's the earlier copy, so it keeps the earlier copy's headers
        #expect(changed.contentType(forAssetAt: style) == "text/css")
        #expect(await library.missingAssets(of: changed).isEmpty)
        // It has everything an editor loads, so it's used until the manifest is next checked
        #expect(try await library.readLatestAssetBundle() == changed)
    }

    @Test("a changed manifest's bundle downloads an unchanged asset that the latest bundle is missing")
    func changedBundleDownloadsAssetMissingFromLatestBundle() async throws {
        let style = "https://example.com/plugin.css?ver=1"
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { url in
            if url.path.contains("editor-assets") {
                return Data(Self.manifestJSON(scriptVersion: "1", style: style).utf8)
            }
            guard url.path != "/plugin.css" else { throw URLError(.timedOut) }
            return Data("mock content".utf8)
        }
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(60))
        let gapped = try await library.downloadAssetBundle()
        #expect(!gapped.hasAssetData(for: URL(string: style)!))

        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "2", style: style))
        let changed = try await library.downloadAssetBundle()

        #expect(changed.hasAssetData(for: URL(string: style)!))
    }

    @Test("a changed manifest's bundle still reports completion when every asset is copied from disk")
    func changedBundleReportsProgressWhenNothingIsDownloaded() async throws {
        let (library, mockClient) = try await makeLibraryWithBundle(cachePolicy: .maxAge(60))
        let changedManifest = Self.manifestJSON(scriptVersion: "1").replacing("core/paragraph", with: "core/heading")
        mockClient.urlResponseHandler = Self.responses(forManifest: changedManifest)
        let progressTracker = ProgressTracker()

        let changed = try await library.downloadAssetBundle { progressTracker.append($0) }

        #expect(mockClient.downloadCallCount == 1)
        #expect(changed.hasAssetData(for: Self.scriptURL))
        #expect(progressTracker.count == 1)
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

    /// A download task reads `URLCache` even though it never writes to it, and the editor's live requests for
    /// assets a bundle doesn't have do write to it.
    @Test(
        "an asset is downloaded afresh rather than taken from a stored response, under every policy",
        arguments: [EditorCachePolicy.always, .maxAge(3600), .ignore]
    )
    func assetDownloadAsksAfresh(cachePolicy: EditorCachePolicy) async throws {
        let (_, mockClient) = try await makeLibraryWithBundle(cachePolicy: cachePolicy)

        #expect(mockClient.downloadRequests.map(\.cachePolicy) == [.reloadIgnoringLocalCacheData])
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
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(0), storageRoot: storageRoot)
        let other = makeLibrary(storageRoot: storageRoot)

        // The site goes back to the older manifest. After the check finds that manifest's bundle on disk,
        // and before the bundle is the latest again, another service's cleanup removes it.
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        let restored = try await library.downloadAssetBundle { _ in try? await other.cleanup() }

        #expect(restored.id == planted[0].id)
        #expect((try? restored.getEditorRepresentation() as EditorAssetBundle.EditorRepresentation) != nil)
        #expect(restored.hasAssetData(for: Self.scriptURL))
        #expect(try await library.readAssetBundles().first?.id == restored.id)
    }

    @Test("downloadAssetBundle builds a bundle again if a purge deletes it mid-check")
    func downloadAssetBundleRebuildsBundlePurgedDuringCheck() async throws {
        let (library, _) = try await makeLibraryWithBundle(cachePolicy: .maxAge(0))
        let bundle = try #require(try await library.readAssetBundles().first)

        let checked = try await library.downloadAssetBundle { _ in try? await library.purge() }

        #expect(checked.id == bundle.id)
        #expect((try? checked.getEditorRepresentation() as EditorAssetBundle.EditorRepresentation) != nil)
        #expect(checked.hasAssetData(for: Self.scriptURL))
        #expect(try await library.readAssetBundles().map(\.id) == [bundle.id])
    }

    @Test("a bundle stored without a lastCheckedDate is aged from its download date")
    func bundleWithoutLastCheckedDateUsesDownloadDate() async throws {
        let (library, _) = try await makeLibraryWithBundle(cachePolicy: .maxAge(3600))
        let bundle = try #require(try await library.readAssetBundles().first)
        let manifestPath = await library.bundleManifestPath(for: bundle)

        // Writes what an earlier version stored: only the manifest and a download date
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

    @Test("cleanup keeps the bundle the site's manifest last matched, even if another was downloaded later")
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

    /// The manifest from ``manifestJSON(scriptVersion:)``, with the stylesheet at `style` as well.
    private static func manifestJSON(scriptVersion: String, style: String) -> String {
        """
        {
            "scripts": "<script src=\\"https://example.com/plugin.js?ver=\(scriptVersion)\\"></script>",
            "styles": "<link rel=\\"stylesheet\\" href=\\"\(style)\\">",
            "allowed_block_types": ["core/paragraph"]
        }
        """
    }

    private static func responses(
        forManifest manifestJSON: String,
        assetContent: String = "mock content"
    ) -> (URL) throws -> Data {
        { url in url.path.contains("editor-assets") ? Data(manifestJSON.utf8) : Data(assetContent.utf8) }
    }

    /// The script in ``manifestJSON(scriptVersion:)`` with version `1`.
    private static let scriptURL = URL(string: "https://example.com/plugin.js?ver=1")!

    /// Whether the volume that holds the tests' bundles supports file clones. APFS, which every Apple
    /// platform uses, does.
    static var storageSupportsClones: Bool {
        let values = try? URL.temporaryDirectory.resourceValues(forKeys: [.volumeSupportsFileCloningKey])
        return values?.volumeSupportsFileCloning == true
    }

    /// The disk space of the file at `url` that no other file shares. A clone shares all of its space with
    /// the original until either changes, so this is zero for both.
    private static func unsharedSize(of url: URL) throws -> Int64 {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE)

        // `getattrlist` writes the returned length as a `UInt32`, then the size as an `off_t`
        var buffer = [UInt8](repeating: 0, count: MemoryLayout<UInt32>.size + MemoryLayout<off_t>.size)
        let result = buffer.withUnsafeMutableBytes { buffer in
            getattrlist(
                url.path,
                &request,
                buffer.baseAddress,
                buffer.count,
                UInt32(FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW)
            )
        }

        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        return buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: MemoryLayout<UInt32>.size, as: off_t.self) }
    }

    /// Sets `bundle`'s `lastCheckedDate` on disk to `interval` seconds ago.
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

    /// Helper to create a unique manifest JSON for each test, with the script at `script` if given
    private func uniqueManifestJSON(identifier: String, script: String? = nil) -> String {
    """
    {
        "scripts": "\(script.map { #"<script src=\"\#($0)\"></script>"# } ?? "")",
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

        // Verify both assets are in the bundle
        #expect(bundle.hasAssetData(for: URL(string: "https://example.com/wp-content/plugins/jetpack/assets/js/editor.js")!))
        #expect(bundle.hasAssetData(for: URL(string: "https://example.com/wp-content/themes/theme/css/blocks/gallery.css")!))
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
        #expect(bundle.hasAssetData(for: URL(string: "https://example.com/good-script.js")!))
        #expect(bundle.hasAssetData(for: URL(string: "https://example.com/style.css")!))

        // The failed asset should not exist
        #expect(!bundle.hasAssetData(for: URL(string: "https://blocked.com/stats.js")!))
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

    @Test("linksLeftOut(of:) returns only the manifest's links that aren't HTTP or HTTPS")
    func linksLeftOutAreTheOnesThatAreNotHTTP() async throws {
        let manifestJSON = """
            {
                "scripts": "<script src=\\"https://example.com/plugin.js?ver=1\\"></script><script src=\\"ftp://example.com/old.js\\"></script><script src=\\"http://example.com/gtag/js?id=1\\"></script>",
                "styles": "<link rel=\\"stylesheet\\" href=\\"https://example.com/css2?family=Inter\\"><link rel=\\"stylesheet\\" href=\\"data:text/css,a%7Bcolor:red%7D\\">",
                "allowed_block_types": ["core/paragraph"]
            }
            """
        let manifest = try LocalEditorAssetManifest(
            remoteManifest: RemoteEditorAssetManifest(data: Data(manifestJSON.utf8))
        )

        let leftOut = await makeLibrary().linksLeftOut(of: manifest)

        #expect(leftOut.map(\.absoluteString) == ["ftp://example.com/old.js", "data:text/css,a%7Bcolor:red%7D"])
    }

    /// The manifest is whatever the site sends. An asset's file name is made from its URL and its path is
    /// never followed, so `..` in a URL can't put a file outside the bundle.
    @Test(
        "an asset whose path climbs above the site's root is stored inside the bundle like any other",
        arguments: ["/wp-content/../../", "/wp-content/%2e%2e/%2e%2e/"]
    )
    func assetWhosePathClimbsIsStoredInsideBundle(pathOutOfSite: String) async throws {
        // Where the file would land if its path were followed: in the temporary directory, beside the
        // directory the bundle is assembled in
        let name = "escaped-\(UUID().uuidString).js"
        let landing = URL.temporaryDirectory.appending(path: name)
        defer { try? FileManager.default.removeItem(at: landing) }

        let climbing = try #require(URL(string: "https://example.com\(pathOutOfSite)\(name)"))
        let manifest = """
            {
                "scripts": "<script src=\\"https://example.com/plugin.js?ver=1\\"></script><script src=\\"\(climbing.absoluteString)\\"></script>",
                "styles": "",
                "allowed_block_types": ["\(name)"]
            }
            """
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(forManifest: manifest)
        let library = makeLibrary(httpClient: mockClient)

        let bundle = try await library.downloadAssetBundle()

        #expect(!FileManager.default.fileExists(at: landing))
        #expect(bundle.hasAssetData(for: Self.scriptURL))
        #expect(bundle.hasAssetData(for: climbing))
        #expect(await library.missingAssets(of: bundle).isEmpty)

        let assets = await library.bundleRoot(for: bundle).appending(path: "assets")
        #expect(
            bundle.assetDataPath(for: climbing).deletingLastPathComponent().standardizedFileURL.path
                == assets.standardizedFileURL.path
        )
        #expect(try FileManager.default.contentsOfDirectory(atPath: assets.path).count == 2)
    }

    // MARK: - Which links are assets

    /// A link is an asset because it's on a script or stylesheet tag, not because of how its URL ends.
    @Test("every script and stylesheet link in a manifest is stored, however its URL ends")
    func everyScriptAndStylesheetLinkIsStored() async throws {
        let scripts = [
            "https://s0.wp.com/_static/??/wp-includes/js/dist/hooks.min.js,/wp-includes/js/dist/i18n.min.js",
            "https://www.googletagmanager.com/gtag/js?id=G-TEST",
        ]
        let styles = [
            "https://fonts-api.wp.com/css2?family=Inter:wght@400",
            "https://s0.wp.com/?custom-css=1&csblog=1",
        ]
        let scriptTags = scripts.map { "<script src='\($0.replacing("&", with: "&amp;"))'></script>" }.joined()
        let styleTags = styles.map { "<link rel='stylesheet' href='\($0.replacing("&", with: "&amp;"))'>" }.joined()
        let manifest = """
            {
                "scripts": "\(scriptTags)",
                "styles": "\(styleTags)",
                "allowed_block_types": ["every-link-is-stored"]
            }
            """
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { url in
            url.path.contains("editor-assets") ? Data(manifest.utf8) : Data("content of \(url.absoluteString)".utf8)
        }
        mockClient.assetResponseHeaders = { url in
            ["Content-Type": scripts.contains(url.absoluteString) ? "application/javascript" : "text/css; charset=utf-8"]
        }
        let library = makeLibrary(httpClient: mockClient)

        let bundle = try await library.downloadAssetBundle()

        for (asset, contentType) in scripts.map({ ($0, "application/javascript") }) + styles.map({ ($0, "text/css; charset=utf-8") }) {
            let url = try #require(URL(string: asset))
            #expect(try bundle.assetData(for: url) == Data("content of \(asset)".utf8))
            #expect(bundle.contentType(forAssetAt: url) == contentType)
        }
        #expect(await library.missingAssets(of: bundle).isEmpty)
    }

    /// A site can answer an asset request with a web page, such as a login or error page, and a success
    /// status. If it were kept, every editor would be served that page in place of the asset.
    @Test(
        "a download that's a web page isn't kept, and the asset counts as missing",
        arguments: [
            (isScript: true, contentType: "text/html; charset=UTF-8"),
            (isScript: true, contentType: "TEXT/HTML"),
            (isScript: false, contentType: "text/html ;charset=utf-8"),
        ]
    )
    func downloadThatIsAWebPageIsNotKept(isScript: Bool, contentType: String) async throws {
        let style = URL(string: "https://example.com/style.css?ver=1")!
        let refused = isScript ? Self.scriptURL : style
        let kept = isScript ? style : Self.scriptURL
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(
            forManifest: Self.manifestJSON(scriptVersion: "1", style: style.absoluteString)
        )
        mockClient.assetResponseHeaders = { $0 == refused ? ["Content-Type": contentType] : [:] }
        let library = makeLibrary(httpClient: mockClient)

        let bundle = try await library.downloadAssetBundle()

        #expect(!bundle.hasAssetData(for: refused))
        #expect(bundle.hasAssetData(for: kept))
        #expect(await library.missingAssets(of: bundle) == [refused])
    }

    /// The library rejects no other type. The editor's web view gets the asset with the type the server
    /// sent, and decides what to do with it, as it would if the site had served the asset.
    @Test(
        "a download with any type other than HTML, or none, is kept with the type it came with",
        arguments: [
            (isScript: true, contentType: "application/javascript"),
            (isScript: true, contentType: "text/javascript; charset=utf-8"),
            (isScript: true, contentType: "text/plain"),
            (isScript: true, contentType: "application/octet-stream"),
            (isScript: true, contentType: "application/json"),
            (isScript: true, contentType: "text/css"),
            (isScript: true, contentType: nil),
            (isScript: false, contentType: "text/css"),
            (isScript: false, contentType: "text/plain"),
            (isScript: false, contentType: "application/javascript"),
            (isScript: false, contentType: nil),
        ] as [(Bool, String?)]
    )
    func downloadIsKeptWhateverElseItsTypeIs(isScript: Bool, contentType: String?) async throws {
        let style = URL(string: "https://example.com/style.css?ver=1")!
        let asset = isScript ? Self.scriptURL : style
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(
            forManifest: Self.manifestJSON(scriptVersion: "1", style: style.absoluteString)
        )
        mockClient.assetResponseHeaders = { url in
            guard url == asset, let contentType else { return [:] }
            return ["Content-Type": contentType]
        }
        let library = makeLibrary(httpClient: mockClient)

        let bundle = try await library.downloadAssetBundle()

        #expect(bundle.hasAssetData(for: asset))
        #expect(bundle.contentType(forAssetAt: asset) == contentType)
        #expect(await library.missingAssets(of: bundle).isEmpty)
    }

    @Test("a refresh that's answered with a web page keeps the copy on disk")
    func refreshAnsweredWithAWebPageKeepsCopyOnDisk() async throws {
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        mockClient.assetResponseHeaders = { _ in ["Content-Type": "application/javascript"] }
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)
        let first = try await library.downloadAssetBundle()

        mockClient.urlResponseHandler = Self.responses(
            forManifest: Self.manifestJSON(scriptVersion: "1"),
            assetContent: "<html>Log in</html>"
        )
        mockClient.assetResponseHeaders = { _ in ["Content-Type": "text/html; charset=UTF-8"] }
        let refreshed = try await library.downloadAssetBundle()

        #expect(try refreshed.assetData(for: Self.scriptURL) == Data("mock content".utf8))
        #expect(refreshed.contentType(forAssetAt: Self.scriptURL) == "application/javascript")
        #expect(refreshed == first)
    }

    /// WordPress versions a file in its query, and the same path can be on more than one host, so assets
    /// that share a path are still different files.
    @Test("assets that share a path are each stored, with their own content")
    func assetsSharingAPathAreEachStored() async throws {
        let assets = [
            "https://example.com/wp-content/app.js?ver=1",
            "https://example.com/wp-content/app.js?ver=2",
            "https://cdn.example.com/wp-content/app.js?ver=1",
        ]
        let scripts = assets.map { "<script src=\\\"\($0)\\\"></script>" }.joined()
        let manifest = """
            {
                "scripts": "\(scripts)",
                "styles": "",
                "allowed_block_types": ["assets-sharing-a-path"]
            }
            """
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { url in
            url.path.contains("editor-assets") ? Data(manifest.utf8) : Data("content of \(url.absoluteString)".utf8)
        }

        let bundle = try await makeLibrary(httpClient: mockClient).downloadAssetBundle()

        for asset in assets {
            let url = try #require(URL(string: asset))
            #expect(try bundle.assetData(for: url) == Data("content of \(asset)".utf8))
        }
    }

    /// `EditorAssetLibrary` writes each asset and `EditorAssetBundle` reads it, so both must use the same path.
    @Test(
        "an asset is read from where it was written, whatever characters its path has",
        arguments: [
            "https://example.com/wp-content/plugins/my%20plugin/script.js",
            "https://example.com/wp-content/plugins/a%23b/script.js",
            "https://example.com/wp-content/plugins/a%3Fb/script.js",
            "https://example.com/wp-content/plugins/50%25/script.js",
        ]
    )
    func assetIsReadFromWhereItWasWritten(asset: String) async throws {
        let manifest = """
            {
                "scripts": "<script src=\\"\(asset)\\"></script>",
                "styles": "",
                "allowed_block_types": ["\(asset)"]
            }
            """
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(forManifest: manifest)

        let bundle = try await makeLibrary(httpClient: mockClient).downloadAssetBundle()

        let url = try #require(URL(string: asset))
        #expect(try bundle.assetData(for: url) == Data("mock content".utf8))
    }

    @Test("a download's file is moved into the bundle, not left where the download put it")
    func downloadedFilesAreNotLeftBehind() async throws {
        let style = URL(string: "https://example.com/plugin.css")!
        let mockClient = EditorAssetLibraryMockHTTPClient()
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(60))
        mockClient.urlResponseHandler = Self.responses(
            forManifest: Self.manifestJSON(scriptVersion: "1", style: style.absoluteString)
        )
        _ = try await library.downloadAssetBundle()

        // A changed manifest, whose stylesheet has no version and is downloaded again
        mockClient.urlResponseHandler = Self.responses(
            forManifest: Self.manifestJSON(scriptVersion: "2", style: style.absoluteString),
            assetContent: "new content"
        )
        _ = try await library.downloadAssetBundle()

        #expect(mockClient.downloadedFiles.count == 4)
        #expect(mockClient.downloadedFiles.allSatisfy { !FileManager.default.fileExists(at: $0) })
    }

    @Test(
        "a build leaves nothing in the temporary directory once its bundle is in place",
        arguments: [EditorCachePolicy.always, .ignore]
    )
    func buildLeavesNothingInTemporaryDirectory(cachePolicy: EditorCachePolicy) async throws {
        let manifestJSON = uniqueManifestJSON(
            identifier: "test-temporary-directory-\(UUID().uuidString)",
            script: "https://example.com/script.js"
        )
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(forManifest: manifestJSON)

        let bundle = try await makeLibrary(httpClient: mockClient, cachePolicy: cachePolicy).downloadAssetBundle()

        #expect(bundle.hasAssetData(for: URL(string: "https://example.com/script.js")!))
        #expect(buildsLeftInTemporaryDirectory(ofManifest: bundle.id).isEmpty)
    }

    @Test("a build that's cancelled leaves nothing in the temporary directory")
    func cancelledBuildLeavesNothingInTemporaryDirectory() async throws {
        let manifest = try LocalEditorAssetManifest(
            remoteManifest: RemoteEditorAssetManifest(
                data: Data(
                    uniqueManifestJSON(
                        identifier: "test-cancelled-temporary-directory-\(UUID().uuidString)",
                        script: "https://example.com/script.js"
                    ).utf8
                )
            )
        )

        let session = ParkedURLSession()
        defer { session.release() }
        let library = makeLibrary(httpClient: EditorHTTPClient(urlSession: session, authHeader: "Bearer test-token"))
        let destination = await library.bundleRoot(for: manifest.checksum).standardizedFileURL

        let build = Task { try await library.buildBundle(for: manifest) }
        try await session.waitUntilStarted()
        let abandoned = try #require(EditorAssetLibrary.inFlightBuilds.task(for: destination))
        #expect(buildsLeftInTemporaryDirectory(ofManifest: manifest.checksum).count == 1)
        build.cancel()

        await #expect(throws: CancellationError.self) { try await build.value }
        await abandoned.value
        #expect(buildsLeftInTemporaryDirectory(ofManifest: manifest.checksum).isEmpty)
    }

    /// The bundles for the manifest with `checksum` left directly in the temporary directory, where a build
    /// assembles a bundle before moving it into the library's storage.
    private func buildsLeftInTemporaryDirectory(ofManifest checksum: String) -> [URL] {
        let directories = try? FileManager.default.contentsOfDirectory(
            at: .temporaryDirectory,
            includingPropertiesForKeys: nil
        )
        return (directories ?? []).filter {
            (try? EditorAssetBundle(url: $0.appending(path: "manifest.json")))?.id == checksum
        }
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

    /// The library that starts a build dates the bundle by its own manifest fetch. A library that joins the
    /// build fetched the manifest later, so it found the site to match more recently.
    @Test("a library that joins a build dates the bundle by its own, later fetch of the manifest")
    func joinerDatesBundleByItsOwnFetch() async throws {
        let manifestJSON = uniqueManifestJSON(
            identifier: "joiner-\(UUID().uuidString)",
            script: "https://example.com/script.js"
        )
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
        let earlierFetch = Date(timeIntervalSinceNow: -120)
        let laterFetch = Date(timeIntervalSinceNow: -60)

        let started = Task { try await libraries[0].buildBundle(for: manifest, fetchedAt: earlierFetch) }
        try await waitUntil { EditorAssetLibrary.inFlightBuilds.waiterCount(for: destination) == 1 }
        let joined = Task { try await libraries[1].buildBundle(for: manifest, fetchedAt: laterFetch) }
        try await waitUntil { EditorAssetLibrary.inFlightBuilds.waiterCount(for: destination) == 2 }

        session.release()  // fails the parked download, which a build tolerates

        #expect(try await started.value.lastCheckedDate == earlierFetch)
        #expect(try await joined.value.lastCheckedDate == laterFetch)
        #expect(try await libraries[0].readAssetBundles().first?.lastCheckedDate == laterFetch)
    }

    @Test("under .ignore, a build doesn't join one in flight for the same manifest")
    func buildUnderIgnoreDoesNotJoinBuildInFlight() async throws {
        let manifest = try LocalEditorAssetManifest(
            remoteManifest: RemoteEditorAssetManifest(data: Data(Self.manifestJSON(scriptVersion: "1").utf8))
        )

        let session = ParkedURLSession()
        defer { session.release() }
        let storageRoot = URL.randomTemporaryDirectory
        let client = EditorHTTPClient(urlSession: session, authHeader: "Bearer test-token")
        let inFlight = makeLibrary(httpClient: client, cachePolicy: .always, storageRoot: storageRoot)
        let refreshing = makeLibrary(httpClient: client, cachePolicy: .ignore, storageRoot: storageRoot)
        let destination = await inFlight.bundleRoot(for: manifest.checksum).standardizedFileURL

        let build = Task { try await inFlight.buildBundle(for: manifest) }
        try await waitUntil { EditorAssetLibrary.inFlightBuilds.waiterCount(for: destination) == 1 }
        let refresh = Task { try await refreshing.buildBundle(for: manifest) }
        try await waitUntil { session.requestCount == 2 }

        #expect(EditorAssetLibrary.inFlightBuilds.waiterCount(for: destination) == 1)

        session.release()  // fails both parked downloads, which a build tolerates
        _ = try await (build.value, refresh.value)
    }
}

// MARK: - Once-Only Action for Tests

/// Runs its action the first time it's asked to, and never again.
private final class OnceOnly: @unchecked Sendable {
    private let lock = NSLock()
    private var action: (() -> Void)?

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    func run() {
        let action = lock.withLock {
            defer { self.action = nil }
            return self.action
        }
        action?()
    }
}

/// Runs an asynchronous action the first time it's asked to, and never again.
private actor OnceOnlyAsync {
    private var action: (@Sendable () async -> Void)?

    init(_ action: @escaping @Sendable () async -> Void) {
        self.action = action
    }

    func run() async {
        let action = self.action
        self.action = nil
        await action?()
    }
}

/// The time of the last `recordNow()` call, for comparing with a date the library records.
private final class RecordedDate: @unchecked Sendable {
    private let lock = NSLock()
    private var _date: Date?

    var date: Date? {
        lock.withLock { _date }
    }

    func recordNow() {
        lock.withLock { _date = Date() }
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
    /// Requests made via `download(_:)`, in order.
    var downloadRequests: [URLRequest] = []
    /// The temporary file each `download(_:)` call returned, in order.
    var downloadedFiles: [URL] = []
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

    /// The response headers sent with the asset at a URL, such as a `Content-Type`. None by default.
    var assetResponseHeaders: ((URL) -> [String: String]) = { _ in [:] }

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
            downloadRequests.append(urlRequest)
        }

        let data = try urlResponseHandler(url)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: tempURL)
        lock.withLock { downloadedFiles.append(tempURL) }

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: assetResponseHeaders(url)
        )!

        return (tempURL, response)
    }
}
