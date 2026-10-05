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
        "downloadAssetBundle leaves a bundle exactly as it was when neither its manifest nor its assets have changed",
        arguments: [EditorCachePolicy.maxAge(0), .ignore]
    )
    func downloadAssetBundleLeavesUnchangedBundleAsItWas(cachePolicy: EditorCachePolicy) async throws {
        let (library, _) = try await makeLibraryWithBundle(cachePolicy: cachePolicy)
        let bundle = try #require(try await library.readAssetBundles().first)

        let checked = try await library.downloadAssetBundle()

        // A host comparing dependencies sees no change, and the date still says when it was downloaded
        #expect(checked == bundle)
        #expect(checked.downloadDate == bundle.downloadDate)
        #expect(try await library.readAssetBundles() == [bundle])
    }

    @Test("under .ignore, assets that come back different go into a new bundle, and the one on disk is left as it was")
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
        // Two bundles for one manifest, which a host comparing dependencies can tell apart
        #expect(refreshed.id == bundle.id)
        #expect(refreshed != bundle)
        #expect(try await library.readAssetBundles().map(\.bundleRoot) == [refreshed.bundleRoot, bundle.bundleRoot])
        #expect(await library.existingBundle(forManifestChecksum: bundle.id)?.bundleRoot == refreshed.bundleRoot)
    }

    @Test("under .ignore, a new bundle takes the latest bundle's copy of an asset that fails to download again")
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

    @Test("under .ignore, an asset that fails to download comes from the bundle the site went back to")
    func assetThatFailsToDownloadComesFromBundleSiteWentBackTo() async throws {
        let mockClient = EditorAssetLibraryMockHTTPClient()
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        let earlier = try await library.downloadAssetBundle()
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "2"))
        _ = try await library.downloadAssetBundle()

        // The site goes back to the earlier manifest, whose script the latest bundle doesn't have
        mockClient.urlResponseHandler = { url in
            guard url.path.contains("editor-assets") else { throw URLError(.timedOut) }
            return Data(Self.manifestJSON(scriptVersion: "1").utf8)
        }
        let refreshed = try await library.downloadAssetBundle()

        #expect(try refreshed.assetData(for: Self.scriptURL) == Data("mock content".utf8))
        #expect(refreshed == earlier)
    }

    @Test("under .ignore, assets stored at one path that fail to download keep the copy on disk")
    func assetsStoredAtOnePathKeepCopyOnDiskWhenDownloadsFail() async throws {
        // The same file on two hosts: a bundle stores an asset by its path alone
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

    /// The bundle on disk is still right, so it's kept. What the server says about its assets now is still
    /// what an editor should be served them with.
    @Test("under .ignore, a bundle whose assets come back the same takes the headers they came back with")
    func unchangedBundleTakesNewHeadersUnderIgnore() async throws {
        let storageRoot = URL.randomTemporaryDirectory
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.assetValidators = { _ in ["Content-Type": "text/plain"] }
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore, storageRoot: storageRoot)
        let bundle = try await library.downloadAssetBundle()

        // The server is put right: the same file, served as what it is
        mockClient.assetValidators = { _ in ["Content-Type": "application/javascript"] }
        let refreshed = try await library.downloadAssetBundle()

        // The same bundle on disk, but not one a host comparing dependencies should take for unchanged
        #expect(refreshed.bundleRoot == bundle.bundleRoot)
        #expect(refreshed != bundle)
        #expect(refreshed.contentType(forAssetAt: Self.scriptURL) == "application/javascript")
        #expect(
            try await library.readAssetBundles().first?.contentType(forAssetAt: Self.scriptURL)
                == "application/javascript"
        )
        #expect(try FileManager.default.contentsOfDirectory(atPath: storageRoot.path).count == 1)
    }

    /// The bundle on disk is kept, but the failure isn't hidden behind it: the next check of the manifest
    /// asks for the asset again.
    @Test("under .ignore, a bundle kept because its assets failed to download records that they weren't refreshed")
    func bundleKeptUnderIgnoreRecordsAssetsNotRefreshed() async throws {
        let storageRoot = URL.randomTemporaryDirectory
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        let refreshing = makeLibrary(httpClient: mockClient, cachePolicy: .ignore, storageRoot: storageRoot)
        let bundle = try await refreshing.downloadAssetBundle()

        mockClient.urlResponseHandler = { url in
            guard url.path.contains("editor-assets") else { throw URLError(.timedOut) }
            return Data(Self.manifestJSON(scriptVersion: "1").utf8)
        }
        let refreshed = try await refreshing.downloadAssetBundle()

        #expect(refreshed == bundle)
        #expect(await refreshing.assetsNotRefreshed(in: refreshed) == [Self.scriptURL])
        #expect(await refreshing.missingAssets(of: refreshed).isEmpty)

        // It has everything an editor loads, so an editor's own library has no reason to ask the site
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .always, storageRoot: storageRoot)
        #expect(try await library.readLatestAssetBundle() == bundle)

        // A check asks for the asset again, though its URL has a version and a copy of it is on disk
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        let downloads = mockClient.downloadCallCount
        let settled = try await library.downloadAssetBundle()

        #expect(mockClient.downloadCallCount == downloads + 1)
        // It's the asset the bundle already had, so it's the same bundle, with nothing left to ask for
        #expect(settled == bundle)
        #expect(await library.assetsNotRefreshed(in: settled).isEmpty)
        #expect(try await library.readLatestAssetBundle() == bundle)
        #expect(try FileManager.default.contentsOfDirectory(atPath: storageRoot.path).count == 1)
    }

    @Test("an asset that wasn't refreshed is asked for again each time the manifest is checked, until it downloads")
    func assetNotRefreshedIsAskedForAgain() async throws {
        let style = URL(string: "https://example.com/plugin.css")!
        let mockClient = EditorAssetLibraryMockHTTPClient()
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .always)
        mockClient.urlResponseHandler = Self.responses(
            forManifest: Self.manifestJSON(scriptVersion: "1", style: style.absoluteString)
        )
        _ = try await library.downloadAssetBundle()

        // A changed manifest, whose stylesheet can't be downloaded
        let changedManifest = Self.manifestJSON(scriptVersion: "2", style: style.absoluteString)
        mockClient.urlResponseHandler = { url in
            if url.path.contains("editor-assets") {
                return Data(changedManifest.utf8)
            }
            guard url.path != style.path else { throw URLError(.timedOut) }
            return Data("new content".utf8)
        }
        let changed = try await library.downloadAssetBundle()
        let downloads = mockClient.downloadCallCount

        // It still can't: it's asked for and nothing else is, and the bundle is kept as it is
        let again = try await library.downloadAssetBundle()

        #expect(mockClient.downloadCallCount == downloads + 1)
        #expect(mockClient.downloadedURLs.last == style)
        #expect(again == changed)
        #expect(await library.assetsNotRefreshed(in: again) == [style])

        // It downloads: the bundle that has it is the site's latest, and there's nothing left to ask for
        mockClient.urlResponseHandler = Self.responses(forManifest: changedManifest, assetContent: "new content")
        let refreshed = try await library.downloadAssetBundle()

        #expect(try refreshed.assetData(for: style) == Data("new content".utf8))
        #expect(await library.assetsNotRefreshed(in: refreshed).isEmpty)
        #expect(try await library.readLatestAssetBundle() == refreshed)
        // An editor may still be reading the bundle that held the earlier copy
        #expect(try changed.assetData(for: style) == Data("mock content".utf8))
    }

    /// One file to download, however many times it's linked.
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
        mockClient.assetValidators = { _ in ["Content-Type": "application/javascript", "ETag": "\"first\""] }
        mockClient.urlResponseHandler = Self.responses(forManifest: manifest)
        let library = makeLibrary(httpClient: mockClient)

        let bundle = try await library.downloadAssetBundle()

        #expect(mockClient.downloadCallCount == 1)
        #expect(bundle.contentType(forAssetAt: Self.scriptURL) == "application/javascript")
        #expect(bundle.headers(for: Self.scriptURL)?.etag == "\"first\"")
        #expect(await library.missingAssets(of: bundle).isEmpty)
    }

    /// Over `http`, a request may not be allowed at all.
    @Test("an asset a manifest links over both http and https is asked for over https")
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

    /// A copy that came over `http` isn't one to take in place of asking over `https`.
    @Test("a changed manifest's bundle asks again for an asset the latest bundle has by another scheme")
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

    /// Another library can record something in a bundle between this one reading it and marking it: a
    /// refresh whose asset failed to download, here. Marking the bundle mustn't write that away.
    @Test("a check that keeps a bundle leaves what another library recorded in it meanwhile")
    func checkKeepsWhatAnotherLibraryRecordedInBundle() async throws {
        let (library, _) = try await makeLibraryWithBundle(cachePolicy: .maxAge(0))
        let bundle = try #require(try await library.readAssetBundles().first)
        let scriptKey = EditorAssetBundle.assetKey(for: Self.scriptURL)

        // The check has found the bundle on disk, and hasn't marked it yet
        let checked = try await library.downloadAssetBundle { _ in
            try? EditorAssetBundle(
                manifest: bundle.manifest,
                downloadDate: bundle.downloadDate,
                lastCheckedDate: bundle.lastCheckedDate,
                assetsNotRefreshed: [scriptKey],
                bundleRoot: bundle.bundleRoot
            ).writeManifest()
        }

        #expect(checked.assetsNotRefreshed == [scriptKey])
        #expect(try await library.readAssetBundles().first?.assetsNotRefreshed == [scriptKey])
    }

    /// The build kept the stylesheet from the bundle on disk without asking for it, so it knows nothing
    /// new about it. What another library recorded about it while the build ran stands, whether the build
    /// ends up keeping that bundle or publishing its own.
    @Test(
        "a build records the assets it kept from the bundle on disk as that bundle records them when it finishes",
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

        // While the check asks for the script again, another library's refresh records that the
        // stylesheet failed to download
        mockClient.urlResponseHandler = { url in
            if url.path.contains("editor-assets") {
                return Data(manifest.utf8)
            }
            try EditorAssetBundle(
                manifest: gapped.manifest,
                downloadDate: gapped.downloadDate,
                lastCheckedDate: gapped.lastCheckedDate,
                assetsNotRefreshed: [EditorAssetBundle.assetKey(for: style)],
                bundleRoot: gapped.bundleRoot
            ).writeManifest()
            guard scriptDownloads else { throw URLError(.timedOut) }
            return Data("mock content".utf8)
        }
        let checked = try await library.downloadAssetBundle()

        #expect((checked.bundleRoot == gapped.bundleRoot) == !scriptDownloads)
        #expect(await library.assetsNotRefreshed(in: checked) == [style])
    }

    /// Looking at a bundle isn't handing it out. One that's passed over for missing an asset is as free to
    /// be cleaned up as it was.
    @Test("cleanup removes a bundle that was only passed over for missing an asset")
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

    @Test("downloadAssetBundle downloads an asset that an earlier build of the bundle failed to")
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

    /// A bundle used to keep each asset at its URL's path, where a bundle doesn't look now. Its assets are
    /// copied to where one does, so that an update costs a site neither a download nor its assets while it
    /// can't be reached.
    @Test("a bundle stored before assets were named for their URLs keeps its assets, without downloading them again")
    func bundleStoredAtAssetPathsKeepsItsAssets() async throws {
        let storageRoot = URL.randomTemporaryDirectory
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .always, storageRoot: storageRoot)
        let stored = try await library.downloadAssetBundle()
        // As it was stored then
        let storedAsset = stored.bundleRoot.appending(path: "plugin.js")
        try FileManager.default.moveItem(at: stored.assetDataPath(for: Self.scriptURL), to: storedAsset)

        let latest = try #require(try await library.readLatestAssetBundle())

        #expect(latest.id == stored.id)
        #expect(try latest.assetData(for: Self.scriptURL) == Data("mock content".utf8))
        #expect(mockClient.downloadCallCount == 1)
        // The site wasn't asked anything, so the bundle is no newer than it was
        #expect(latest.downloadDate == stored.downloadDate)
        #expect(latest.lastCheckedDate == stored.lastCheckedDate)
        // An editor may be reading the bundle as it was stored
        #expect(latest.bundleRoot != stored.bundleRoot)
        #expect(FileManager.default.fileExists(at: storedAsset))
        // It's an earlier bundle's copy of the asset, to ask for again when the manifest is next checked
        #expect(await library.assetsNotRefreshed(in: latest) == [Self.scriptURL])

        // And once is enough
        #expect(try await library.readLatestAssetBundle() == latest)
        #expect(try await library.readLatestAssetBundleOnDisk() == latest)
        #expect(try FileManager.default.contentsOfDirectory(atPath: storageRoot.path).count == 2)
    }

    /// The copy has to come before the bundle it was made from, wherever that bundle is. Otherwise the next
    /// read finds the old one again, and copies it again.
    @Test("a bundle stored before assets were named for their URLs is copied once, whatever its directory is called")
    func bundleStoredAtAssetPathsIsCopiedOnceWhateverItsDirectory() async throws {
        let storageRoot = URL.randomTemporaryDirectory
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .always, storageRoot: storageRoot)
        let stored = try await library.downloadAssetBundle()
        try FileManager.default.moveItem(
            at: stored.assetDataPath(for: Self.scriptURL),
            to: stored.bundleRoot.appending(path: "plugin.js")
        )
        // Not the manifest's own directory, which a refresh's bundle doesn't get when another has it
        try FileManager.default.moveItem(
            at: stored.bundleRoot,
            to: storageRoot.appending(path: "\(stored.id)-refreshed")
        )

        let latest = try #require(try await library.readLatestAssetBundle())

        #expect(latest.hasAssetData(for: Self.scriptURL))
        #expect(try await library.readLatestAssetBundle() == latest)
        #expect(try await library.readLatestAssetBundleOnDisk() == latest)
        #expect(try FileManager.default.contentsOfDirectory(atPath: storageRoot.path).count == 2)
    }

    /// A bundle kept one file at a path for every asset with that path, whichever host or query each was
    /// asked for by. There's no telling which of them the file holds.
    @Test("a file that a bundle stored before assets were named for their URLs kept for two assets is taken for neither")
    func fileKeptForTwoAssetsInEarlierLayoutIsTakenForNeither() async throws {
        let storageRoot = URL.randomTemporaryDirectory
        let cdnScript = URL(string: "https://cdn.example.com/plugin.js?ver=1")!
        let style = URL(string: "https://example.com/plugin.css")!
        let manifest = """
            {
                "scripts": "<script src=\\"https://example.com/plugin.js?ver=1\\"></script><script src=\\"https://cdn.example.com/plugin.js?ver=1\\"></script>",
                "styles": "<link rel=\\"stylesheet\\" href=\\"https://example.com/plugin.css\\">",
                "allowed_block_types": ["core/paragraph"]
            }
            """
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(forManifest: manifest)
        let library = makeLibrary(httpClient: mockClient, storageRoot: storageRoot)
        let stored = try await library.downloadAssetBundle()
        // As it was stored then: one file for both scripts, and one for the stylesheet
        try FileManager.default.moveItem(
            at: stored.assetDataPath(for: Self.scriptURL),
            to: stored.bundleRoot.appending(path: "plugin.js")
        )
        try FileManager.default.removeItem(at: stored.assetDataPath(for: cdnScript))
        try FileManager.default.moveItem(
            at: stored.assetDataPath(for: style),
            to: stored.bundleRoot.appending(path: "plugin.css")
        )

        let onDisk = try #require(try await library.readLatestAssetBundleOnDisk())

        #expect(onDisk.hasAssetData(for: style))
        #expect(await library.missingAssets(of: onDisk) == [Self.scriptURL, cdnScript])
    }

    /// Such a bundle kept whatever its site answered with, so a check asks for its assets again. They're
    /// still what there is to fall back on, wherever the bundle kept them.
    @Test(
        "a check of a bundle stored before assets were named for their URLs asks for its assets again, and keeps them if that fails",
        arguments: [EditorCachePolicy.maxAge(0), .ignore]
    )
    func checkOfBundleStoredAtAssetPathsAsksForItsAssetsAgain(cachePolicy: EditorCachePolicy) async throws {
        let storageRoot = URL.randomTemporaryDirectory
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        let library = makeLibrary(httpClient: mockClient, cachePolicy: cachePolicy, storageRoot: storageRoot)
        let stored = try await library.downloadAssetBundle()
        try FileManager.default.moveItem(
            at: stored.assetDataPath(for: Self.scriptURL),
            to: stored.bundleRoot.appending(path: "plugin.js")
        )

        mockClient.urlResponseHandler = { url in
            guard url.path.contains("editor-assets") else { throw URLError(.timedOut) }
            return Data(Self.manifestJSON(scriptVersion: "1").utf8)
        }
        let checked = try await library.downloadAssetBundle()

        #expect(mockClient.downloadCallCount == 2)
        #expect(try checked.assetData(for: Self.scriptURL) == Data("mock content".utf8))
        #expect(await library.assetsNotRefreshed(in: checked) == [Self.scriptURL])

        // It downloads: there's nothing left to ask for
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        let settled = try await library.downloadAssetBundle()

        #expect(settled.bundleRoot == checked.bundleRoot)
        #expect(await library.assetsNotRefreshed(in: settled).isEmpty)
    }

    /// A copy nobody was given is as free to be cleaned up as the bundle it was made from.
    @Test("cleanup removes the copy of a bundle stored before assets were named for their URLs, once it's superseded")
    func cleanupRemovesSupersededCopyOfBundleStoredAtAssetPaths() async throws {
        let storageRoot = URL.randomTemporaryDirectory
        let planted = try await plantBundles(forManifests: [Self.manifestJSON(scriptVersion: "1")], in: storageRoot)
        try FileManager.default.moveItem(
            at: planted[0].assetDataPath(for: Self.scriptURL),
            to: planted[0].bundleRoot.appending(path: "plugin.js")
        )
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(
            forManifest: Self.manifestJSON(scriptVersion: "1"),
            assetContent: "new content"
        )
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(0), storageRoot: storageRoot)

        let checked = try await library.downloadAssetBundle()
        try await library.cleanup()

        #expect(try checked.assetData(for: Self.scriptURL) == Data("new content".utf8))
        #expect(try await library.readAssetBundles().map(\.bundleRoot) == [checked.bundleRoot])
    }

    /// Two links written differently can lead to one file: the earlier layout kept an asset wherever its
    /// path led, whatever it went through to get there.
    @Test("a file that two paths led to in a bundle stored before assets were named for their URLs is taken for neither")
    func fileTwoPathsLedToInEarlierLayoutIsTakenForNeither() async throws {
        let storageRoot = URL.randomTemporaryDirectory
        let roundabout = URL(string: "https://cdn.example.com/x/%2E%2E/plugin.js?ver=1")!
        let manifest = """
            {
                "scripts": "<script src=\\"https://example.com/plugin.js?ver=1\\"></script><script src=\\"\(roundabout.absoluteString)\\"></script>",
                "styles": "",
                "allowed_block_types": ["core/paragraph"]
            }
            """
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(forManifest: manifest)
        let library = makeLibrary(httpClient: mockClient, storageRoot: storageRoot)
        let stored = try await library.downloadAssetBundle()
        // As it was stored then: one file, where both paths lead
        try FileManager.default.moveItem(
            at: stored.assetDataPath(for: Self.scriptURL),
            to: stored.bundleRoot.appending(path: "plugin.js")
        )
        try FileManager.default.removeItem(at: stored.assetDataPath(for: roundabout))

        let onDisk = try #require(try await library.readLatestAssetBundleOnDisk())

        #expect(await library.missingAssets(of: onDisk) == [Self.scriptURL, roundabout])
    }

    /// Not a bundle the tests' own library wrote and then rearranged: one as the last release left it on
    /// disk. Its manifest file holds no more than a manifest and a download date, its assets are at their
    /// URLs' paths, and it never held a link that didn't end in `.js` or `.css`.
    @Test("a bundle as the last release stored it gives the assets it has, and asks only for the one it never held")
    func bundleAsLastReleaseStoredItGivesItsAssets() async throws {
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

        // The site can't be reached: what the bundle has is still there to give an editor
        let onDisk = try #require(try await library.readLatestAssetBundleOnDisk())

        #expect(onDisk.id == manifest.checksum)
        #expect(onDisk.downloadDate == downloadDate)
        #expect(onDisk.lastCheckedDate == nil)
        #expect(try onDisk.assetData(for: script) == Data("script".utf8))
        #expect(try onDisk.assetData(for: style) == Data("style".utf8))
        #expect(await library.missingAssets(of: onDisk) == [concatenated])
        #expect(try await library.readLatestAssetBundleOnDisk() == onDisk)
        // It's missing an asset, so it isn't one to settle for
        #expect(try await library.readLatestAssetBundle() == nil)

        // The site can be reached: everything is asked for, as the bundle records none of it as downloaded
        mockClient.urlResponseHandler = Self.responses(forManifest: manifestJSON, assetContent: "new content")
        let checked = try await library.downloadAssetBundle()

        #expect(Set(mockClient.downloadedURLs) == [script, style, concatenated])
        #expect(await library.missingAssets(of: checked).isEmpty)
        #expect(await library.assetsNotRefreshed(in: checked).isEmpty)
        #expect(try await library.readLatestAssetBundle() == checked)
    }

    /// A refresh that changes a bundle's assets publishes a bundle of its own, which a check of the same
    /// manifest that was already under way knows nothing about. What that check found or built is older,
    /// and mustn't go back in front.
    @Test("a check that's overtaken by a refresh gives the refresh's bundle, rather than putting its own back in front")
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

        // The check has asked for the script again, and failed again. Before it settles, a refresh
        // downloads the script and publishes a bundle that has it.
        let refresh = OnceOnlyAsync {
            mockClient.urlResponseHandler = Self.responses(forManifest: manifest)
            _ = try? await refreshing.downloadAssetBundle()
        }
        let checked = try await library.downloadAssetBundle { _ in await refresh.run() }

        #expect(checked.bundleRoot != gapped.bundleRoot)
        #expect(checked.hasAssetData(for: Self.scriptURL))
        #expect(try await library.readAssetBundles().first?.bundleRoot == checked.bundleRoot)
    }

    @Test("a bundle stored before assets were named for their URLs is as old as it was, for the cache policy")
    func bundleStoredAtAssetPathsIsNoNewerForBeingCopied() async throws {
        let (library, mockClient) = try await makeLibraryWithBundle(cachePolicy: .maxAge(60))
        let stored = try #require(try await library.readAssetBundles().first)
        try backdate(stored, by: 120)
        try FileManager.default.moveItem(
            at: stored.assetDataPath(for: Self.scriptURL),
            to: stored.bundleRoot.appending(path: "plugin.js")
        )

        #expect(try await library.readLatestAssetBundle() == nil)

        // What there is to use when the site can't be asked has its asset all the same
        let onDisk = try #require(try await library.readLatestAssetBundleOnDisk())
        #expect(onDisk.hasAssetData(for: Self.scriptURL))
        #expect(mockClient.downloadCallCount == 1)
    }

    /// A bundle is dated by when the site was found to have its manifest: when the manifest was fetched,
    /// not when the bundle finished building, which can be a good while later. That's what its age for the
    /// cache policy counts from, and what decides which bundle is the site's latest.
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

    /// The site's manifest changes while its earlier one's bundle is still building, and a refresh builds
    /// the new one's first. The slower build is of what the site had before, so it stays behind.
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
    /// matches it: a more recent look at the site than the refresh's own. The refresh's bundle replaces
    /// that one all the same, so it has to come ahead of it.
    @Test("a bundle that replaces its manifest's bundle comes ahead of it, though that one was matched while it built")
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

    /// The clock was ahead when the bundle on disk was last matched, and has been set back since. What's
    /// published now is dated now, and still has to come ahead of it — and stay there.
    @Test("a bundle dated in time to come stays behind the bundles published since")
    func bundleDatedInTimeToComeStaysBehindBundlesPublishedSince() async throws {
        let storageRoot = URL.randomTemporaryDirectory
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore, storageRoot: storageRoot)
        let dated = try await library.downloadAssetBundle()
        try backdate(dated, by: -86_400)

        // A refresh replaces it, for the same manifest
        mockClient.urlResponseHandler = Self.responses(
            forManifest: Self.manifestJSON(scriptVersion: "1"),
            assetContent: "new content"
        )
        let refreshed = try await library.downloadAssetBundle()
        #expect(try await library.readAssetBundles().first?.bundleRoot == refreshed.bundleRoot)
        // It's been dated afresh, so it won't come back in front when the clock reaches the date it had
        #expect(try #require(try await library.readAssetBundles().last?.lastCheckedDate) <= Date())

        // Another that changes nothing keeps the refreshed bundle, and leaves it in front
        let again = try await library.downloadAssetBundle()
        #expect(again.bundleRoot == refreshed.bundleRoot)
        #expect(try await library.readAssetBundles().first?.bundleRoot == refreshed.bundleRoot)
        #expect(try FileManager.default.contentsOfDirectory(atPath: storageRoot.path).count == 2)

        // And so does a bundle for another manifest
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "2"))
        let changed = try await library.downloadAssetBundle()
        #expect(try await library.readAssetBundles().first?.bundleRoot == changed.bundleRoot)
    }

    /// All a date still to come tells is that the bundle was matched after the ones with dates that can
    /// be believed. It keeps its place ahead of them.
    @Test("a bundle dated in time to come stays ahead of the bundles that were there before it")
    func bundleDatedInTimeToComeStaysAheadOfEarlierBundles() async throws {
        let mockClient = EditorAssetLibraryMockHTTPClient()
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(0))
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        let earlier = try await library.downloadAssetBundle()
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "2"))
        let latest = try await library.downloadAssetBundle()
        try backdate(latest, by: -86_400)

        let onDisk = try #require(try await library.readLatestAssetBundleOnDisk())

        #expect(onDisk.id == latest.id)
        let bundles = try await library.readAssetBundles()
        #expect(bundles.map(\.id) == [latest.id, earlier.id])
        #expect(try #require(bundles.first?.lastCheckedDate) <= Date())
    }

    /// Their dates still say which came later, which is all that's kept of them.
    @Test("bundles dated in time to come keep their order when they're dated afresh")
    func bundlesDatedInTimeToComeKeepTheirOrder() async throws {
        let mockClient = EditorAssetLibraryMockHTTPClient()
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(0))
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        let earlier = try await library.downloadAssetBundle()
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "2"))
        let later = try await library.downloadAssetBundle()
        try backdate(earlier, by: -86_400)
        try backdate(later, by: -172_800)

        #expect(try await library.readLatestAssetBundleOnDisk()?.id == later.id)

        let bundles = try await library.readAssetBundles()
        #expect(bundles.map(\.id) == [later.id, earlier.id])
        #expect(bundles.allSatisfy { ($0.lastCheckedDate ?? .distantFuture) <= Date() })
    }

    /// A date that's still to come says nothing about how long ago the manifest was checked.
    @Test("a bundle dated in time to come isn't trusted for its age, only by a policy that never asks")
    func bundleDatedInTimeToComeIsNotTrustedForItsAge() async throws {
        let storageRoot = URL.randomTemporaryDirectory
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = Self.responses(forManifest: Self.manifestJSON(scriptVersion: "1"))
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(3600), storageRoot: storageRoot)
        let bundle = try await library.downloadAssetBundle()
        try backdate(bundle, by: -86_400)

        #expect(try await library.readLatestAssetBundle() == nil)
        #expect(try await makeLibrary(cachePolicy: .always, storageRoot: storageRoot).readLatestAssetBundle() == bundle)
    }

    /// Another library may have found the site's manifest to match the bundle more recently than this one
    /// did, and recorded it first: here, between this check fetching the manifest and marking the bundle.
    @Test("a check doesn't make a bundle look less recently matched than it's recorded to be")
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

    /// A date that's still to come is one the clock has been set back from. Going by it would leave the
    /// bundle unchecked until the clock caught up.
    @Test("a check dates a bundle afresh when the date it's recorded with is still to come")
    func checkDatesBundleAfreshWhenRecordedDateIsStillToCome() async throws {
        let (library, _) = try await makeLibraryWithBundle(cachePolicy: .maxAge(0))
        let bundle = try #require(try await library.readAssetBundles().first)
        try backdate(bundle, by: -3600)

        let checked = try await library.downloadAssetBundle()

        #expect(try #require(checked.lastCheckedDate) <= Date())
    }

    /// What a refresh learned is the caller's to be told, whether or not it could be written down.
    @Test("a bundle kept after a refresh says which assets failed to download even when that can't be recorded")
    func keptBundleSaysWhatFailedWhenItCannotBeRecorded() async throws {
        let (library, mockClient) = try await makeLibraryWithBundle(cachePolicy: .ignore)
        let bundle = try #require(try await library.readAssetBundles().first)
        mockClient.urlResponseHandler = { url in
            guard url.path.contains("editor-assets") else { throw URLError(.timedOut) }
            return Data(Self.manifestJSON(scriptVersion: "1").utf8)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: bundle.bundleRoot.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundle.bundleRoot.path)
        }

        let refreshed = try await library.downloadAssetBundle()

        #expect(refreshed.bundleRoot == bundle.bundleRoot)
        #expect(await library.assetsNotRefreshed(in: refreshed) == [Self.scriptURL])
    }

    /// An editor may be reading the bundle that's missing the asset, so the asset doesn't go into it.
    @Test("a check that downloads what a bundle is missing leaves that bundle as it was, and builds one beside it")
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

    @Test("a check whose bundle is still missing an asset afterwards keeps that bundle, and adds no other")
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

    /// Nothing is downloaded into the library's storage, so a bundle deleted there stays deleted.
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

        // The manifest's bundle, in a directory that building the manifest again wouldn't replace
        let moved = storageRoot.appending(path: "\(gapped.id)-moved")
        try FileManager.default.moveItem(at: gapped.bundleRoot, to: moved)

        // The bundle is deleted while its missing script downloads, the first time that's asked for
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

    @Test("an asset that a check downloads for a bundle that was missing it keeps the headers it came with")
    func repairedAssetKeepsItsValidator() async throws {
        let style = URL(string: "https://example.com/plugin.css")!
        let manifest = Self.manifestJSON(scriptVersion: "1", style: style.absoluteString)
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.assetValidators = { $0.path == style.path ? ["ETag": "\"first\""] : [:] }
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
        #expect(repaired.headers(for: style)?.etag == "\"first\"")
        #expect(try await library.readAssetBundles().first?.headers(for: style)?.etag == "\"first\"")

        // So the next bundle asks only for a newer copy of it
        mockClient.urlResponseHandler = Self.responses(
            forManifest: Self.manifestJSON(scriptVersion: "2", style: style.absoluteString),
            assetContent: "new content"
        )
        let changed = try await library.downloadAssetBundle()

        let request = try #require(mockClient.downloadRequests.last { $0.url == style })
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"first\"")
        #expect(try changed.assetData(for: style) == Data("mock content".utf8))
    }

    @Test(
        "a changed manifest's bundle takes the assets whose URL hasn't changed from the latest bundle",
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
        "a changed manifest's bundle downloads again an asset whose URL carries no version",
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

    @Test(
        "a changed manifest's bundle asks only for a newer copy of an asset without a version, and keeps the one on disk when there's none",
        arguments: [["ETag": "\"first\""], ["Last-Modified": "Wed, 30 Sep 2026 21:43:35 GMT"]]
    )
    func changedBundleKeepsUnversionedAssetServerSaysIsUnchanged(assetHeaders: [String: String]) async throws {
        let style = URL(string: "https://example.com/plugin.css")!
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.assetValidators = { $0.path == style.path ? assetHeaders : [:] }
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(60))
        mockClient.urlResponseHandler = Self.responses(
            forManifest: Self.manifestJSON(scriptVersion: "1", style: style.absoluteString)
        )
        _ = try await library.downloadAssetBundle()

        // Twice, because the second bundle has to keep the asset's headers along with the asset
        for scriptVersion in ["2", "3"] {
            mockClient.urlResponseHandler = Self.responses(
                forManifest: Self.manifestJSON(scriptVersion: scriptVersion, style: style.absoluteString),
                assetContent: "new content"
            )
            let changed = try await library.downloadAssetBundle()

            let request = try #require(mockClient.downloadRequests.last { $0.url == style })
            #expect(request.value(forHTTPHeaderField: "If-None-Match") == assetHeaders["ETag"])
            #expect(request.value(forHTTPHeaderField: "If-Modified-Since") == assetHeaders["Last-Modified"])
            #expect(try changed.assetData(for: style) == Data("mock content".utf8))
        }
    }

    @Test("a changed manifest's bundle downloads the newer copy of an asset without a version when the server has one")
    func changedBundleDownloadsUnversionedAssetServerSaysHasChanged() async throws {
        let style = URL(string: "https://example.com/plugin.css")!
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.assetValidators = { $0.path == style.path ? ["ETag": "\"first\""] : [:] }
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(60))
        mockClient.urlResponseHandler = Self.responses(
            forManifest: Self.manifestJSON(scriptVersion: "1", style: style.absoluteString)
        )
        _ = try await library.downloadAssetBundle()

        mockClient.assetValidators = { $0.path == style.path ? ["ETag": "\"second\""] : [:] }
        mockClient.urlResponseHandler = Self.responses(
            forManifest: Self.manifestJSON(scriptVersion: "2", style: style.absoluteString),
            assetContent: "new content"
        )
        let changed = try await library.downloadAssetBundle()

        #expect(try changed.assetData(for: style) == Data("new content".utf8))
        #expect(changed.headers(for: style)?.etag == "\"second\"")
    }

    /// The editor is served an asset with the type its server gave it, so the type has to stay with the file
    /// however the file gets into a bundle: downloaded, copied because its URL hasn't changed, or kept because
    /// the server says it hasn't.
    @Test("an asset's Content-Type is kept with it, from one bundle to the next")
    func assetContentTypeIsKeptWithAsset() async throws {
        let style = URL(string: "https://example.com/plugin.css")!
        let script = URL(string: "https://example.com/plugin.js?ver=1")!
        let secondScript = URL(string: "https://example.com/second.js?ver=1")!
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.assetValidators = { url in
            switch url.path {
            case style.path: ["Content-Type": "text/css; charset=utf-8", "ETag": "\"first\""]
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

        // A changed manifest: the script is copied for its unchanged URL, the stylesheet kept on a 304
        mockClient.urlResponseHandler = Self.responses(forManifest: manifest(extraScript: true))
        let second = try await library.downloadAssetBundle()

        #expect(second.id != first.id)
        for bundle in [first, second] {
            #expect(bundle.contentType(forAssetAt: style) == "text/css; charset=utf-8")
            #expect(bundle.contentType(forAssetAt: script) == "application/javascript")
        }
        // Its server sent no type, so there is none to serve it with
        #expect(second.contentType(forAssetAt: secondScript) == nil)
    }

    @Test("under .ignore, an asset is downloaded in full even when the server could say it hasn't changed")
    func assetDownloadIsUnconditionalUnderIgnore() async throws {
        let style = URL(string: "https://example.com/plugin.css")!
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.assetValidators = { _ in ["ETag": "\"first\""] }
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)
        mockClient.urlResponseHandler = Self.responses(
            forManifest: Self.manifestJSON(scriptVersion: "1", style: style.absoluteString)
        )
        _ = try await library.downloadAssetBundle()

        mockClient.urlResponseHandler = Self.responses(
            forManifest: Self.manifestJSON(scriptVersion: "2", style: style.absoluteString),
            assetContent: "new content"
        )
        let refreshed = try await library.downloadAssetBundle()

        #expect(mockClient.downloadRequests.allSatisfy { $0.value(forHTTPHeaderField: "If-None-Match") == nil })
        #expect(try refreshed.assetData(for: style) == Data("new content".utf8))
    }

    @Test("a changed manifest's bundle keeps the copy on disk of an asset without a version that fails to download")
    func changedBundleKeepsUnversionedAssetThatFailsToDownload() async throws {
        let style = URL(string: "https://example.com/plugin.css")!
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.assetValidators = { $0.path == style.path ? ["ETag": "\"first\""] : [:] }
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(60))
        mockClient.urlResponseHandler = Self.responses(
            forManifest: Self.manifestJSON(scriptVersion: "1", style: style.absoluteString)
        )
        _ = try await library.downloadAssetBundle()

        // The server has a newer copy, which can't be downloaded
        mockClient.assetValidators = { $0.path == style.path ? ["ETag": "\"second\""] : [:] }
        mockClient.urlResponseHandler = { url in
            if url.path.contains("editor-assets") {
                return Data(Self.manifestJSON(scriptVersion: "2", style: style.absoluteString).utf8)
            }
            guard url.path != style.path else { throw URLError(.timedOut) }
            return Data("new content".utf8)
        }
        let changed = try await library.downloadAssetBundle()

        #expect(try changed.assetData(for: style) == Data("mock content".utf8))
        // It's the earlier copy, so it's the earlier copy's headers that go with it
        #expect(changed.headers(for: style)?.etag == "\"first\"")
        // The copy stands in for the asset without hiding that the asset failed to download
        #expect(await library.assetsNotRefreshed(in: changed) == [style])
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

    @Test("a changed manifest's bundle whose assets are all carried forward still reports that it's complete")
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

    @Test("under .ignore, an asset is asked for afresh rather than taken from a stored response")
    func assetDownloadAsksAfreshUnderIgnore() async throws {
        let (_, mockClient) = try await makeLibraryWithBundle(cachePolicy: .ignore)

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
        let (library, _) = try await makeLibraryWithBundle(cachePolicy: .maxAge(0))
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

    @Test("a manifest's links that aren't HTTP are the only ones a bundle doesn't hold")
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

    /// A manifest is whatever the site sends. An asset is stored under a name made from its URL, never at
    /// its path, so `..` in one takes it nowhere.
    @Test(
        "an asset whose path climbs out of the site is stored inside the bundle like any other",
        arguments: ["/wp-content/../../", "/wp-content/%2e%2e/%2e%2e/"]
    )
    func assetWhosePathClimbsIsStoredInsideBundle(pathOutOfSite: String) async throws {
        // Where it would land if its path were followed: beside the directory the bundle is assembled in
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

    /// What makes a link an asset is the tag it's on, not how its URL ends.
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
        mockClient.assetValidators = { url in
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

    /// A site can answer a request for an asset with a web page and still say it went well: one to log in
    /// on, or one saying what went wrong. Kept, it would be served to every editor in the asset's place.
    @Test(
        "a download that's a web page isn't kept, and is missed",
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
        mockClient.assetValidators = { $0 == refused ? ["Content-Type": contentType] : [:] }
        let library = makeLibrary(httpClient: mockClient)

        let bundle = try await library.downloadAssetBundle()

        #expect(!bundle.hasAssetData(for: refused))
        #expect(bundle.hasAssetData(for: kept))
        #expect(await library.missingAssets(of: bundle) == [refused])
    }

    /// What a web view makes of an asset is for the web view to decide, from the type the asset is served
    /// with, as it would if the site had served it.
    @Test(
        "a download is kept whatever else its type is, or when it has none, and keeps the type it came with",
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
        mockClient.assetValidators = { url in
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
        mockClient.assetValidators = { _ in ["Content-Type": "application/javascript"] }
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .ignore)
        let first = try await library.downloadAssetBundle()

        mockClient.urlResponseHandler = Self.responses(
            forManifest: Self.manifestJSON(scriptVersion: "1"),
            assetContent: "<html>Log in</html>"
        )
        mockClient.assetValidators = { _ in ["Content-Type": "text/html; charset=UTF-8"] }
        let refreshed = try await library.downloadAssetBundle()

        #expect(try refreshed.assetData(for: Self.scriptURL) == Data("mock content".utf8))
        #expect(refreshed.contentType(forAssetAt: Self.scriptURL) == "application/javascript")
        #expect(refreshed == first)
    }

    /// WordPress tells one version of a file from another by its query, and one host's file from another's
    /// by its host.
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

    /// The library writes an asset and the bundle reads it, so the two have to agree on where.
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
        mockClient.assetValidators = { $0.path == style.path ? ["ETag": "\"first\""] : [:] }
        let library = makeLibrary(httpClient: mockClient, cachePolicy: .maxAge(60))
        mockClient.urlResponseHandler = Self.responses(
            forManifest: Self.manifestJSON(scriptVersion: "1", style: style.absoluteString)
        )
        _ = try await library.downloadAssetBundle()

        // A changed manifest, whose stylesheet the server says is unchanged: that answer has a file too
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

    /// The bundles for the manifest with `checksum` that are in the temporary directory itself, which is where a
    /// build assembles one before putting it in the library's storage.
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

    /// The build is the library's that started it, and so is the date it gives the bundle. A library that
    /// joins it fetched the manifest later, and so has found the site to match more recently.
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

/// The moment a test asks it to record, for comparing with a date the library records.
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
    /// The file each `download(_:)` handed back, in order.
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

    /// The headers the server sends with the asset at a URL — `ETag`, `Last-Modified`, `Content-Type`, or none. When a
    /// download's request sends one back unchanged, the server answers 304 with no body, as a real one would.
    var assetValidators: ((URL) -> [String: String]) = { _ in [:] }

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

        let assetHeaders = assetValidators(url)
        let isUnchanged = Self.asksOnlyForNewerCopy(urlRequest, than: assetHeaders)

        let data = isUnchanged ? Data() : try urlResponseHandler(url)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: tempURL)
        lock.withLock { downloadedFiles.append(tempURL) }

        let response = HTTPURLResponse(
            url: url,
            statusCode: isUnchanged ? 304 : 200,
            httpVersion: "HTTP/1.1",
            headerFields: assetHeaders
        )!

        return (tempURL, response)
    }

    /// Whether `request` sends back the validator the server would send with the asset now.
    private static func asksOnlyForNewerCopy(_ request: URLRequest, than assetHeaders: [String: String]) -> Bool {
        if let etag = assetHeaders["ETag"] {
            return request.value(forHTTPHeaderField: "If-None-Match") == etag
        }

        if let lastModified = assetHeaders["Last-Modified"] {
            return request.value(forHTTPHeaderField: "If-Modified-Since") == lastModified
        }

        return false
    }
}
