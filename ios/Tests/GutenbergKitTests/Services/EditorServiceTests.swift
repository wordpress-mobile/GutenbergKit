import Foundation
import Testing

@testable import GutenbergKit

/// One at a time, for the reason `EditorAssetLibraryTests` are: nearly every one of these builds or
/// reads an asset bundle.
@Suite(.serialized)
struct EditorServiceTests: MakesTestFixtures {

  // MARK: - Test Fixtures
  static let testSiteURL = URL(string: "https://example.com")!
  static let testApiRoot = URL(string: "https://example.com/wp-json")!

  // MARK: - fetchAssetBundleCount Tests
  @Test("fetchAssetBundleCount returns zero when no bundles exist")
  func fetchAssetBundleCountReturnsZeroWhenEmpty() async throws {
    #expect(try await makeService().fetchAssetBundleCount() == 0)
  }

  // MARK: - DependencyWeights Tests

  @Test("DependencyWeights have expected values")
  func dependencyWeightsHaveExpectedValues() {
    #expect(EditorService.DependencyWeights.editorSettings.rawValue == 10)
    #expect(EditorService.DependencyWeights.assetBundle.rawValue == 50)
    #expect(EditorService.DependencyWeights.post.rawValue == 10)
    #expect(EditorService.DependencyWeights.postType.rawValue == 10)
    #expect(EditorService.DependencyWeights.activeTheme.rawValue == 10)
    #expect(EditorService.DependencyWeights.settingsOptions.rawValue == 10)
    #expect(EditorService.DependencyWeights.postTypes.rawValue == 10)
  }

  @Test("DependencyWeights sum to expected total")
  func dependencyWeightsSumToExpectedTotal() {
    let allWeights = EditorService.DependencyWeights.allCases
    let total = allWeights.reduce(0.0) { $0 + $1.rawValue }

    // Total should be 110 (10+50+10+10+10+10+10)
    #expect(total == 110)
  }

  // MARK: - cleanup and purge Tests

  @Test("cleanup does not throw when no bundles exist")
  func cleanupDoesNotThrowWhenEmpty() async throws {
    try await makeService().cleanup()
    try await makeService().cleanup()  // Check that it can be called multiple times
  }

  @Test("purge completes without throwing")
  func purgeCompletesWithoutThrowingForEmptyCacheDirectory() async throws {
    try await makeService().purge()
    try await makeService().purge()  // Check that it can be called multiple times

  }

  // MARK: - preparePreloadList Tests

  @Test("prepare does not fetch post when postID is negative")
  func prepareDoesNotFetchPostWhenPostIDIsNegative() async throws {
    let mockClient = EditorAssetLibraryMockHTTPClient()
    mockClient.urlResponseHandler = Self.editorServiceResponseHandler
    let configuration = makeConfiguration(postID: -1)
    let service = EditorService(
      configuration: configuration,
      httpClient: mockClient,
      storageRoot: .randomTemporaryDirectory,
      cacheRoot: .randomTemporaryDirectory
    )

    _ = try await service.prepare()

    // Verify no request was made to /posts/-1
    let postRequests = mockClient.requestedURLs.filter { $0.absoluteString.contains("/posts/-1") }
    #expect(postRequests.isEmpty, "Should not request /posts/-1 for negative post IDs")
  }

  @Test("prepare does not fetch post when postID is zero")
  func prepareDoesNotFetchPostWhenPostIDIsZero() async throws {
    let mockClient = EditorAssetLibraryMockHTTPClient()
    mockClient.urlResponseHandler = Self.editorServiceResponseHandler
    let configuration = makeConfiguration(postID: 0)
    let service = EditorService(
      configuration: configuration,
      httpClient: mockClient,
      storageRoot: .randomTemporaryDirectory,
      cacheRoot: .randomTemporaryDirectory
    )

    _ = try await service.prepare()

    // Verify no request was made to /posts/0
    let postRequests = mockClient.requestedURLs.filter { $0.absoluteString.contains("/posts/0") }
    #expect(postRequests.isEmpty, "Should not request /posts/0 for zero post IDs")
  }

  @Test("prepare fetches post when postID is positive")
  func prepareFetchesPostWhenPostIDIsPositive() async throws {
    let mockClient = EditorAssetLibraryMockHTTPClient()
    mockClient.urlResponseHandler = Self.editorServiceResponseHandler
    let configuration = makeConfiguration(postID: 123)
    let service = EditorService(
      configuration: configuration,
      httpClient: mockClient,
      storageRoot: .randomTemporaryDirectory,
      cacheRoot: .randomTemporaryDirectory
    )

    _ = try await service.prepare()

    // Verify a request was made to /posts/123
    let postRequests = mockClient.requestedURLs.filter { $0.absoluteString.contains("/posts/123") }
    #expect(!postRequests.isEmpty, "Should request /posts/123 for positive post IDs")
  }

  // MARK: - Progress

  /// The first `prepare()` to finish clears the service's progress while the other still has
  /// progress to report, so `incrementProgress` has to drop late progress rather than trap on it.
  /// A shared bundle build delivers the same late progress to a service whose `prepare()` has
  /// given up on it.
  @Test("overlapping prepare() calls on one service don't trap on each other's progress")
  func overlappingPrepareCallsDontTrap() async throws {
    let client = GatedHTTPClient(respond: Self.editorServiceResponseHandler)
    let service = EditorService(
      configuration: makeConfiguration(),
      httpClient: client,
      storageRoot: .randomTemporaryDirectory,
      cacheRoot: .randomTemporaryDirectory
    )

    let first = Task { try await GatedHTTPClient.$caller.withValue("first") { try await service.prepare() } }
    let second = Task { try await GatedHTTPClient.$caller.withValue("second") { try await service.prepare() } }
    try await waitUntil { client.isHolding("first") && client.isHolding("second") }

    client.release("first")
    _ = try await first.value
    client.release("second")
    _ = try await second.value
  }

  // MARK: - Cache Policy

  @Test("prepare() under .always uses the bundle on disk without checking the manifest")
  func prepareUnderAlwaysUsesBundleOnDisk() async throws {
    let site = TestSite(configuration: makeConfiguration(), manifest: Self.pluginManifest(version: "1"))
    let bundle = try await site.service(cachePolicy: .always).prepare().assetBundle

    let again = try await site.service(cachePolicy: .always).prepare().assetBundle

    #expect(again.id == bundle.id)
    #expect(site.manifestRequestCount == 1)
    #expect(site.client.downloadCallCount == 1)
  }

  @Test("prepare() under .ignore downloads the bundle's assets again, even when its manifest hasn't changed")
  func prepareUnderIgnoreDownloadsUnchangedBundleAgain() async throws {
    let site = TestSite(configuration: makeConfiguration(), manifest: Self.pluginManifest(version: "1"))
    let bundle = try await site.service(cachePolicy: .always).prepare().assetBundle

    let refreshed = try await site.service(cachePolicy: .ignore).prepare().assetBundle

    #expect(refreshed.id == bundle.id)
    #expect(site.manifestRequestCount == 2)
    #expect(site.client.downloadCallCount == 2)
  }

  @Test("prepare() under .maxAge checks the manifest once it's due, and keeps the bundle when it hasn't changed")
  func prepareUnderMaxAgeKeepsUnchangedBundle() async throws {
    let site = TestSite(configuration: makeConfiguration(), manifest: Self.pluginManifest(version: "1"))
    let bundle = try await site.service(cachePolicy: .always).prepare().assetBundle

    let checked = try await site.service(cachePolicy: .maxAge(0)).prepare().assetBundle

    #expect(checked.id == bundle.id)
    #expect(site.manifestRequestCount == 2)
    #expect(site.client.downloadCallCount == 1)
  }

  @Test("prepare() under .ignore picks up a changed manifest, which later editors then load")
  func prepareUnderIgnorePicksUpChangedManifest() async throws {
    let site = TestSite(configuration: makeConfiguration(), manifest: Self.pluginManifest(version: "1"))
    let bundle = try await site.service(cachePolicy: .always).prepare().assetBundle

    site.manifest = Self.pluginManifest(version: "2")
    let refreshed = try await site.service(cachePolicy: .ignore).prepare().assetBundle
    let afterwards = try await site.service(cachePolicy: .always).prepare().assetBundle

    #expect(refreshed.id != bundle.id)
    #expect(afterwards.id == refreshed.id)
    #expect(site.client.downloadCallCount == 2)
  }

  @Test("prepare() uses the bundle on disk without checking the manifest by default")
  func prepareUsesBundleOnDiskByDefault() async throws {
    let site = TestSite(configuration: makeConfiguration(), manifest: Self.pluginManifest(version: "1"))
    let bundle = try await site.service(cachePolicy: .always).prepare().assetBundle

    let again = try await EditorService(
      configuration: site.configuration,
      httpClient: site.client,
      storageRoot: site.storageRoot,
      cacheRoot: site.cacheRoot
    ).prepare().assetBundle

    #expect(again == bundle)
    #expect(site.manifestRequestCount == 1)
  }

  @Test("prepare() under .maxAge checks the manifest only once the last check is older than the age")
  func prepareUnderMaxAgeChecksOnceExpired() async throws {
    let site = TestSite(configuration: makeConfiguration(), manifest: Self.pluginManifest(version: "1"))
    let bundle = try await site.service(cachePolicy: .always).prepare().assetBundle

    _ = try await site.service(cachePolicy: .maxAge(3600)).prepare()
    #expect(site.manifestRequestCount == 1)

    try site.setLastManifestCheck(of: bundle, to: Date(timeIntervalSinceNow: -7200))
    let checked = try await site.service(cachePolicy: .maxAge(3600)).prepare().assetBundle
    #expect(site.manifestRequestCount == 2)
    #expect(checked == bundle)

    // The check started the bundle's age over
    _ = try await site.service(cachePolicy: .maxAge(3600)).prepare()
    #expect(site.manifestRequestCount == 2)
    #expect(site.client.downloadCallCount == 1)
  }

  @Test("a manifest check that fails fails prepare(), and leaves what's on disk for later editors")
  func failedManifestCheckLeavesDiskUntouched() async throws {
    let site = TestSite(configuration: makeConfiguration(), manifest: Self.pluginManifest(version: "1"))
    let bundle = try await site.service(cachePolicy: .always).prepare().assetBundle

    site.isOffline = true
    await #expect(throws: URLError.self) {
      try await site.service(cachePolicy: .ignore).prepare()
    }

    #expect(try await site.service(cachePolicy: .always).prepare().assetBundle == bundle)
    #expect(try await site.service(cachePolicy: .always).fetchAssetBundleCount() == 1)
  }

  @Test("cleanup() keeps a superseded bundle that dependencies prepared earlier still use")
  func cleanupKeepsBundleStillInUse() async throws {
    let site = TestSite(configuration: makeConfiguration(), manifest: Self.pluginManifest(version: "1"))
    let held = try await site.service(cachePolicy: .always).prepare()

    site.manifest = Self.pluginManifest(version: "2")
    let refreshed = try await site.service(cachePolicy: .ignore).prepare()
    try await site.service(cachePolicy: .always).cleanup()

    #expect(refreshed.assetBundle.id != held.assetBundle.id)
    #expect((try? held.assetBundle.getEditorRepresentation() as EditorAssetBundle.EditorRepresentation) != nil)
  }

  @Test("with automatic fallback, a refresh that can't reach the site returns what's on disk")
  func failedRefreshFallsBackToDisk() async throws {
    let configuration = makeConfiguration().toBuilder().setNetworkFallbackMode(.automatic).build()
    let site = TestSite(configuration: configuration, manifest: Self.pluginManifest(version: "1"))
    let prepared = try await site.service(cachePolicy: .always).prepare()

    site.isOffline = true
    let refreshed = try await site.service(cachePolicy: .ignore).prepare()

    #expect(refreshed.assetBundle.assetCount == 1)
    #expect(refreshed == prepared)
  }

  @Test("with automatic fallback, prepare() returns empty dependencies when offline with nothing on disk")
  func offlineWithNothingOnDiskReturnsEmptyDependencies() async throws {
    let configuration = makeConfiguration().toBuilder().setNetworkFallbackMode(.automatic).build()
    let site = TestSite(configuration: configuration, manifest: Self.pluginManifest(version: "1"))
    site.isOffline = true

    let dependencies = try await site.service(cachePolicy: .ignore).prepare()

    #expect(dependencies.editorSettings == .undefined)
    #expect(dependencies.assetBundle.assetCount == 0)
    #expect(dependencies.preloadList == nil)
  }

  /// The post is the one thing `prepare()` asks the site for every time, so a service for a post
  /// can't reach the site whatever its cache policy.
  @Test(
    "with automatic fallback, prepare() for a post that can't reach the site returns what's on disk, without the post",
    arguments: [EditorCachePolicy.always, .maxAge(0), .ignore]
  )
  func failedPrepareForPostFallsBackToDisk(cachePolicy: EditorCachePolicy) async throws {
    let configuration = makeConfiguration(postID: 123).toBuilder().setNetworkFallbackMode(.automatic).build()
    let site = TestSite(configuration: configuration, manifest: Self.pluginManifest(version: "1"))
    let prepared = try await site.service(cachePolicy: .always).prepare()

    site.isOffline = true
    let dependencies = try await site.service(cachePolicy: cachePolicy).prepare()

    let preloadList = try #require(dependencies.preloadList)
    #expect(dependencies.assetBundle == prepared.assetBundle)
    #expect(dependencies.editorSettings == prepared.editorSettings)
    #expect(preloadList.postTypeData == prepared.preloadList?.postTypeData)
    #expect(preloadList.postData == nil)
    // One for each `prepare()`: reading what's on disk asks the site for nothing
    #expect(site.postRequestCount == 2)
  }

  @Test("with automatic fallback, what's on disk needs no settings or bundle for a configuration that uses neither")
  func fallbackToDiskNeedsOnlyWhatConfigurationUses() async throws {
    let configuration = makeConfiguration(postID: 123, shouldUsePlugins: false, shouldUseThemeStyles: false)
      .toBuilder().setNetworkFallbackMode(.automatic).build()
    let site = TestSite(configuration: configuration, manifest: Self.pluginManifest(version: "1"))
    let prepared = try await site.service(cachePolicy: .always).prepare()

    site.isOffline = true
    let dependencies = try await site.service(cachePolicy: .always).prepare()

    #expect(dependencies.preloadList?.postTypeData == prepared.preloadList?.postTypeData)
    #expect(dependencies.editorSettings == .undefined)
    #expect(dependencies.assetBundle == .empty)
  }

  @Test("without automatic fallback, prepare() for a post that can't reach the site throws, whatever is on disk")
  func failedPrepareForPostThrowsWithoutFallback() async throws {
    let site = TestSite(configuration: makeConfiguration(postID: 123), manifest: Self.pluginManifest(version: "1"))
    _ = try await site.service(cachePolicy: .always).prepare()

    site.isOffline = true
    await #expect(throws: URLError.self) {
      try await site.service(cachePolicy: .always).prepare()
    }
  }

  // MARK: - What a Prepare Came To

  @Test("prepareAvailable() reports no failures when every dependency is fetched")
  func prepareAvailableReportsNoFailures() async throws {
    let site = TestSite(configuration: makeConfiguration(postID: 123), manifest: Self.pluginManifest(version: "1"))

    let preparation = try await site.service(cachePolicy: .always).prepareAvailable()

    #expect(preparation.isComplete)
    #expect(preparation.dependencies.assetBundle.assetCount == 1)
    #expect(preparation.dependencies.preloadList?.postData != nil)
  }

  /// A site can answer and still not have the manifest: the endpoint is removed, or errors.
  @Test("a manifest check the site answers with an error gives the bundle on disk, and says the check failed")
  func manifestCheckAnsweredWithErrorGivesBundleOnDisk() async throws {
    let site = TestSite(configuration: makeConfiguration(), manifest: Self.pluginManifest(version: "1"))
    let prepared = try await site.service(cachePolicy: .always).prepare()

    site.failure = { $0.absoluteString.contains("editor-assets") ? Self.notFound($0) : nil }
    let preparation = try await site.service(cachePolicy: .maxAge(0)).prepareAvailable()

    #expect(preparation.dependencies == prepared)
    #expect(dependenciesNotFetched(in: preparation) == [.assetBundle: true])
    #expect(preparation.failures.count == 1)
  }

  @Test("prepare() gives the bundle on disk when the manifest check errors and the fallback is automatic")
  func prepareGivesBundleOnDiskWhenManifestCheckErrors() async throws {
    let configuration = makeConfiguration().toBuilder().setNetworkFallbackMode(.automatic).build()
    let site = TestSite(configuration: configuration, manifest: Self.pluginManifest(version: "1"))
    let prepared = try await site.service(cachePolicy: .always).prepare()

    site.failure = { $0.absoluteString.contains("editor-assets") ? Self.notFound($0) : nil }
    let dependencies = try await site.service(cachePolicy: .maxAge(0)).prepare()

    #expect(dependencies == prepared)
  }

  @Test("prepare() throws when the manifest check errors and the fallback is disabled")
  func prepareThrowsWhenManifestCheckErrorsWithoutFallback() async throws {
    let site = TestSite(configuration: makeConfiguration(), manifest: Self.pluginManifest(version: "1"))
    _ = try await site.service(cachePolicy: .always).prepare()

    site.failure = { $0.absoluteString.contains("editor-assets") ? Self.notFound($0) : nil }
    await #expect(throws: EditorHTTPClient.ClientError.self) {
      try await site.service(cachePolicy: .maxAge(0)).prepare()
    }
  }

  @Test("each dependency that can't be fetched comes from disk, and each is reported")
  func prepareAvailableFallsBackToDiskForEveryDependency() async throws {
    let site = TestSite(configuration: makeConfiguration(postID: 123), manifest: Self.pluginManifest(version: "1"))
    let prepared = try await site.service(cachePolicy: .always).prepare()

    site.isOffline = true
    let preparation = try await site.service(cachePolicy: .ignore).prepareAvailable()

    #expect(preparation.dependencies.editorSettings == prepared.editorSettings)
    #expect(preparation.dependencies.assetBundle == prepared.assetBundle)
    #expect(preparation.dependencies.preloadList?.postTypeData == prepared.preloadList?.postTypeData)
    #expect(dependenciesNotFetched(in: preparation) == [
      .editorSettings: true,
      .assetBundle: true,
      .postType: true,
      .postTypes: true,
      .activeTheme: true,
      .settingsOptions: true,
      // Never stored, so there's no copy of it to use
      .post: false,
    ])
  }

  @Test("a dependency with no copy on disk is left out, without emptying the ones that have one")
  func prepareAvailableLeavesOutOnlyWhatIsMissing() async throws {
    let site = TestSite(configuration: makeConfiguration(), manifest: Self.pluginManifest(version: "1"))
    let prepared = try await site.service(cachePolicy: .always).prepare()
    try await EditorAssetLibrary(
      configuration: site.configuration,
      httpClient: site.client,
      storageRoot: site.storageRoot
    ).purge()

    site.isOffline = true
    let preparation = try await site.service(cachePolicy: .always).prepareAvailable()

    #expect(preparation.dependencies.assetBundle == .empty)
    #expect(preparation.dependencies.editorSettings == prepared.editorSettings)
    #expect(preparation.dependencies.preloadList == prepared.preloadList)
    #expect(dependenciesNotFetched(in: preparation) == [.assetBundle: false])
  }

  @Test("with nothing on disk, every dependency is reported as left out")
  func prepareAvailableReportsEverythingLeftOut() async throws {
    let site = TestSite(configuration: makeConfiguration(), manifest: Self.pluginManifest(version: "1"))
    site.isOffline = true

    let preparation = try await site.service(cachePolicy: .always).prepareAvailable()

    #expect(preparation.dependencies.editorSettings == .undefined)
    #expect(preparation.dependencies.assetBundle == .empty)
    #expect(preparation.dependencies.preloadList == nil)
    #expect(dependenciesNotFetched(in: preparation).values.allSatisfy { !$0 })
    #expect(dependenciesNotFetched(in: preparation).count == 6)
  }

  @Test("a bundle that's missing an asset is reported, and doesn't stop prepare() even without a fallback")
  func bundleMissingAssetIsReported() async throws {
    let site = TestSite(configuration: makeConfiguration(), manifest: Self.pluginManifest(version: "1"))
    site.failure = { $0.path == Self.pluginScript.path ? Self.notFound($0) : nil }

    let preparation = try await site.service(cachePolicy: .always).prepareAvailable()

    #expect(assetsMissing(in: preparation) == [Self.pluginScript])
    #expect(dependenciesNotFetched(in: preparation).isEmpty)
    #expect(try await site.service(cachePolicy: .always).prepare().assetBundle.id == preparation.dependencies.assetBundle.id)
  }

  /// Whatever the cache policy: under `.always`, nothing else would ever ask the site again.
  @Test("a bundle that's missing an asset is tried again on every prepare, until it has it")
  func bundleMissingAssetIsTriedAgainEveryPrepare() async throws {
    let site = TestSite(configuration: makeConfiguration(), manifest: Self.pluginManifest(version: "1"))
    site.failure = { $0.path == Self.pluginScript.path ? Self.notFound($0) : nil }
    _ = try await site.service(cachePolicy: .always).prepare()

    let again = try await site.service(cachePolicy: .always).prepareAvailable()
    #expect(assetsMissing(in: again) == [Self.pluginScript])
    #expect(site.manifestRequestCount == 2)
    #expect(site.client.downloadCallCount == 2)

    site.failure = nil
    let repaired = try await site.service(cachePolicy: .always).prepareAvailable()
    #expect(repaired.isComplete)
    #expect(repaired.dependencies.assetBundle.hasAssetData(for: Self.pluginScript))
    #expect(site.manifestRequestCount == 3)
    #expect(site.client.downloadCallCount == 3)

    // And once it has it, there's nothing left to ask for
    _ = try await site.service(cachePolicy: .always).prepare()
    #expect(site.manifestRequestCount == 3)
    #expect(site.client.downloadCallCount == 3)
  }

  /// The cache policy asks for no more than the bundle on disk. Trying its missing asset again is worth
  /// asking the site for, but the bundle doesn't depend on the answer — so no dependency went unfetched,
  /// and nothing throws for want of a fallback.
  @Test("a bundle that's missing an asset is still given when the site can't be asked about it, even without a fallback")
  func bundleMissingAssetIsGivenWhenSiteCannotBeAsked() async throws {
    let site = TestSite(configuration: makeConfiguration(), manifest: Self.pluginManifest(version: "1"))
    site.failure = { $0.path == Self.pluginScript.path ? Self.notFound($0) : nil }
    let gapped = try await site.service(cachePolicy: .always).prepare().assetBundle

    site.isOffline = true
    let preparation = try await site.service(cachePolicy: .always).prepareAvailable()

    #expect(preparation.dependencies.assetBundle == gapped)
    #expect(dependenciesNotFetched(in: preparation).isEmpty)
    #expect(assetsMissing(in: preparation) == [Self.pluginScript])
    #expect(try await site.service(cachePolicy: .always).prepare().assetBundle == gapped)
  }

  @Test("a bundle that's missing an asset is still given when the site answers the check with an error")
  func bundleMissingAssetIsGivenWhenManifestCheckErrors() async throws {
    let site = TestSite(configuration: makeConfiguration(), manifest: Self.pluginManifest(version: "1"))
    site.failure = { $0.path == Self.pluginScript.path ? Self.notFound($0) : nil }
    let gapped = try await site.service(cachePolicy: .always).prepare().assetBundle

    // The site no longer has the endpoint that serves its manifest
    site.failure = { Self.notFound($0) }

    #expect(try await site.service(cachePolicy: .always).prepare().assetBundle == gapped)
  }

  /// The bundle that was trusted when the prepare began isn't the one to give if there's a newer one by
  /// the time the site turns out not to answer: another service may have published it in between.
  @Test("a bundle that's missing an asset gives way to one published while the site couldn't be asked")
  func bundleMissingAssetGivesWayToOnePublishedMeanwhile() async throws {
    let site = TestSite(configuration: makeConfiguration(), manifest: Self.pluginManifest(version: "1"))
    site.failure = { $0.path == Self.pluginScript.path ? Self.notFound($0) : nil }
    let gapped = try await site.service(cachePolicy: .always).prepare().assetBundle
    let publishedRoot = gapped.bundleRoot.deletingLastPathComponent().appending(path: "\(gapped.id)-published")

    // While the manifest is being asked for, and failing, a bundle with the asset is published
    site.failure = { _ in
      if !FileManager.default.fileExists(atPath: publishedRoot.path) {
        try? FileManager.default.copyItem(at: gapped.bundleRoot, to: publishedRoot)
        if let published = try? EditorAssetBundle(
          manifest: gapped.manifest,
          downloadDate: Date(),
          lastCheckedDate: Date(),
          bundleRoot: publishedRoot
        ) {
          try? published.writeManifest()
          try? FileManager.default.createDirectory(
            at: published.assetDataPath(for: Self.pluginScript).deletingLastPathComponent(),
            withIntermediateDirectories: true
          )
          try? Data("script".utf8).write(to: published.assetDataPath(for: Self.pluginScript))
        }
      }
      return URLError(.timedOut)
    }
    let preparation = try await site.service(cachePolicy: .always).prepareAvailable()

    #expect(preparation.dependencies.assetBundle.bundleRoot.lastPathComponent == publishedRoot.lastPathComponent)
    #expect(preparation.dependencies.assetBundle.hasAssetData(for: Self.pluginScript))
    #expect(preparation.isComplete)
  }

  /// The copy on disk stands in for the asset, and the failure isn't hidden behind it.
  @Test("an asset that fails to download in a refresh is reported, and asked for again at each check until it downloads")
  func assetNotRefreshedIsReportedAndAskedForAgain() async throws {
    let site = TestSite(configuration: makeConfiguration(), manifest: Self.pluginManifest(version: "1"))
    let prepared = try await site.service(cachePolicy: .always).prepare()

    site.failure = { $0.path == Self.pluginScript.path ? URLError(.timedOut) : nil }
    let refreshed = try await site.service(cachePolicy: .ignore).prepareAvailable()

    #expect(refreshed.dependencies.assetBundle == prepared.assetBundle)
    #expect(assetsNotRefreshed(in: refreshed) == [Self.pluginScript])
    #expect(assetsMissing(in: refreshed).isEmpty)
    #expect(dependenciesNotFetched(in: refreshed).isEmpty)

    // The bundle has everything an editor loads, and it's what `.always` asks for: the next editor
    // doesn't wait on the site for it, and has nothing to report, because nothing was asked.
    let requests = site.client.requests.count + site.client.downloadCallCount
    let opened = try await site.service(cachePolicy: .always).prepareAvailable()

    #expect(opened.isComplete)
    #expect(opened.dependencies.assetBundle == prepared.assetBundle)
    #expect(site.client.requests.count + site.client.downloadCallCount == requests)

    // The next check of the manifest asks for the asset again, though its URL has a version
    let downloads = site.client.downloadCallCount
    let checked = try await site.service(cachePolicy: .maxAge(0)).prepareAvailable()

    #expect(assetsNotRefreshed(in: checked) == [Self.pluginScript])
    #expect(site.client.downloadCallCount == downloads + 1)

    site.failure = nil
    let settled = try await site.service(cachePolicy: .maxAge(0)).prepareAvailable()

    #expect(settled.isComplete)
    #expect(settled.dependencies.assetBundle == prepared.assetBundle)
    #expect(try await site.service(cachePolicy: .always).fetchAssetBundleCount() == 1)

    // And once it has it, a check has nothing left to ask for
    let settledDownloads = site.client.downloadCallCount
    _ = try await site.service(cachePolicy: .maxAge(0)).prepare()
    #expect(site.client.downloadCallCount == settledDownloads)
  }

  /// An app update mustn't cost a site its assets while the site can't be reached.
  @Test("a bundle stored before assets were named for their URLs gives its assets when the site can't be reached")
  func bundleStoredAtAssetPathsGivesItsAssetsOffline() async throws {
    let site = TestSite(configuration: makeConfiguration(), manifest: Self.pluginManifest(version: "1"))
    let stored = try await site.service(cachePolicy: .always).prepare().assetBundle
    // As it was stored then: at its URL's path
    try FileManager.default.moveItem(
      at: stored.assetDataPath(for: Self.pluginScript),
      to: stored.bundleRoot.appending(path: "plugin.js")
    )

    site.isOffline = true
    let preparation = try await site.service(cachePolicy: .always).prepareAvailable()

    #expect(preparation.isComplete)
    #expect(preparation.dependencies.assetBundle.hasAssetData(for: Self.pluginScript))
    #expect(site.client.downloadCallCount == 1)

    // Nor when the site was to be asked and couldn't be: the bundle wasn't fetched, and that's all
    // there is to say about it. None of its assets was asked for, so none failed to download.
    let refresh = try await site.service(cachePolicy: .ignore).prepareAvailable()

    #expect(refresh.dependencies.assetBundle.hasAssetData(for: Self.pluginScript))
    #expect(dependenciesNotFetched(in: refresh)[.assetBundle] == true)
    #expect(assetsNotRefreshed(in: refresh).isEmpty)
  }

  /// Not at the first failure: by the time it throws, whatever could be fetched is stored, so trying
  /// again starts from there.
  @Test("with no fallback, a dependency that can't be fetched throws once the others have been fetched and stored")
  func failureThrowsOnceOtherDependenciesAreStored() async throws {
    let site = TestSite(configuration: makeConfiguration(), manifest: Self.pluginManifest(version: "1"))
    site.failure = { $0.absoluteString.contains("wp-block-editor/v1/settings") ? Self.notFound($0) : nil }

    await #expect(throws: EditorHTTPClient.ClientError.self) {
      try await site.service(cachePolicy: .always).prepare()
    }
    #expect(try await site.service(cachePolicy: .always).fetchAssetBundleCount() == 1)

    // Trying again asks only for what failed
    site.failure = nil
    let requests = site.client.requests.count
    let prepared = try await site.service(cachePolicy: .always).prepare()

    #expect(prepared.assetBundle.hasAssetData(for: Self.pluginScript))
    #expect(site.client.requests.count == requests + 1)
    #expect(site.client.downloadCallCount == 1)
  }

  /// A copy that can't be read is no copy, and the site can still be asked.
  @Test("a dependency whose copy on disk can't be read is fetched, rather than given up on")
  func unreadableCopyOnDiskIsFetchedAgain() async throws {
    let site = TestSite(configuration: makeConfiguration(), manifest: Self.pluginManifest(version: "1"))
    let prepared = try await site.service(cachePolicy: .always).prepare()
    let settingsURL = try #require(site.client.requestedURLs.first { $0.absoluteString.contains("block-editor/v1/settings") })
    try EditorURLCache(siteId: site.configuration.siteId, parentDirectory: site.cacheRoot).store(
      EditorURLResponse(data: Data("not editor settings".utf8), responseHeaders: [:]),
      for: settingsURL,
      httpMethod: .GET
    )

    let preparation = try await site.service(cachePolicy: .always).prepareAvailable()

    #expect(preparation.isComplete)
    #expect(preparation.dependencies.editorSettings == prepared.editorSettings)
    #expect(site.client.requestedURLs.filter { $0 == settingsURL }.count == 2)
  }

  @Test("a cancelled prepare throws, rather than reporting everything it was fetching as a failure")
  func cancelledPrepareThrows() async throws {
    let client = GatedHTTPClient { Self.editorServiceResponseHandler($0) }
    let service = EditorService(
      configuration: makeConfiguration().toBuilder().setNetworkFallbackMode(.automatic).build(),
      httpClient: client,
      storageRoot: .randomTemporaryDirectory,
      cacheRoot: .randomTemporaryDirectory
    )

    let prepare = Task {
      try await GatedHTTPClient.$caller.withValue("prepare") { try await service.prepareAvailable() }
    }
    try await waitUntil { client.isHolding("prepare") }
    prepare.cancel()

    await #expect(throws: CancellationError.self) { try await prepare.value }
  }

  @Test("progress ends on its total when dependencies come from disk")
  func progressEndsOnTotalWhenFallingBack() async throws {
    let site = TestSite(configuration: makeConfiguration(postID: 123), manifest: Self.pluginManifest(version: "1"))
    _ = try await site.service(cachePolicy: .always).prepare()
    let tracker = ProgressTracker()

    site.isOffline = true
    _ = try await site.service(cachePolicy: .ignore).prepareAvailable { tracker.append($0) }

    let last = try #require(tracker.updates.last)
    #expect(last.completed == last.total)
    #expect(tracker.updates.allSatisfy { $0.completed <= $0.total })
  }

  // MARK: - Automatic Cleanup

  @Test("a site's old bundles are cleaned up, whichever site was prepared first that day")
  func automaticCleanupRunsPerSite() async throws {
    let first = TestSite(
      configuration: makeConfiguration(siteURL: Self.uniqueSiteURL()), manifest: Self.pluginManifest(version: "1"))
    let second = TestSite(
      configuration: makeConfiguration(siteURL: Self.uniqueSiteURL()), manifest: Self.pluginManifest(version: "2"))
    defer { Self.forgetAutomaticCleanups(of: [first, second]) }
    try await plantBundles(
      forManifests: [Self.pluginManifest(version: "1"), Self.pluginManifest(version: "2")],
      in: second.storageRoot
    )
    #expect(try await second.service(cachePolicy: .always).fetchAssetBundleCount() == 2)

    _ = try await first.service(cachePolicy: .always).prepare()
    _ = try await second.service(cachePolicy: .always).prepare()

    #expect(try await second.service(cachePolicy: .always).fetchAssetBundleCount() == 1)
  }

  // MARK: - Progress Totals

  @Test("prepare() progress never passes its total, and ends on it")
  func prepareProgressStaysWithinTotal() async throws {
    let scripts = ["a", "b", "c", "d"]
      .map { #"<script src=\"https://example.com/\#($0).js\"></script>"# }
      .joined()
    let site = TestSite(
      configuration: makeConfiguration(),
      manifest: #"{"scripts":"\#(scripts)","styles":"","allowed_block_types":[]}"#
    )
    let tracker = ProgressTracker()

    _ = try await site.service(cachePolicy: .always).prepare { tracker.append($0) }

    let completed = tracker.updates.map(\.completed)
    #expect(site.client.downloadCallCount == 4)
    #expect(tracker.updates.allSatisfy { $0.completed <= $0.total })
    #expect(tracker.updates.last?.completed == tracker.updates.last?.total)
    #expect(completed == completed.sorted())
  }

  // MARK: - Test Helpers

  /// URL-based response handler for EditorService.prepare() tests.
  private static func editorServiceResponseHandler(_ url: URL) -> Data {
    let urlString = url.absoluteString

    switch true {
    case urlString.contains("editor-assets"):
      return Data(#"{"scripts":"","styles":"","allowed_block_types":[]}"#.utf8)
    case urlString.contains("wp-block-editor/v1/settings"):
      return Data(#"{"styles":[]}"#.utf8)
    case urlString.contains("/wp/v2/types/") && urlString.contains("context=edit"):
      return Data(#"{"name":"Posts","slug":"post"}"#.utf8)
    case urlString.contains("/wp/v2/types"):
      return Data(#"{"post":{"name":"Posts","slug":"post"}}"#.utf8)
    case urlString.contains("/wp/v2/themes"):
      return Data(#"[{"name":"Twenty Twenty-Four"}]"#.utf8)
    case urlString.contains("/wp/v2/settings"):
      return Data(#"{"title":"Test Site"}"#.utf8)
    case urlString.contains("/wp/v2/posts/"):
      return Data(#"{"id":123,"title":{"rendered":"Test"}}"#.utf8)
    default:
      return Data("{}".utf8)
    }
  }

  /// The dependencies `preparation` says weren't fetched, each with whether its copy on disk stands
  /// in for it.
  private func dependenciesNotFetched(in preparation: EditorPreparation) -> [EditorPreparation.Dependency: Bool] {
    var dependencies: [EditorPreparation.Dependency: Bool] = [:]
    for case .notFetched(let dependency, _, let usingCopyOnDisk) in preparation.failures {
      dependencies[dependency] = usingCopyOnDisk
    }
    return dependencies
  }

  /// The assets `preparation` says its bundle is missing.
  private func assetsMissing(in preparation: EditorPreparation) -> [URL] {
    var assets: [URL] = []
    for case .assetsMissing(let missing) in preparation.failures {
      assets += missing
    }
    return assets
  }

  /// The assets `preparation` says its bundle holds an earlier copy of.
  private func assetsNotRefreshed(in preparation: EditorPreparation) -> [URL] {
    var assets: [URL] = []
    for case .assetsNotRefreshed(let notRefreshed) in preparation.failures {
      assets += notRefreshed
    }
    return assets
  }

  /// The error a site answers with when it has nothing at a URL.
  private static func notFound(_ url: URL) -> any Error {
    EditorHTTPClient.ClientError.unknown(response: Data(), statusCode: 404, requestURL: url)
  }

  private static let pluginScript = URL(string: "https://example.com/plugin.js?ver=1")!

  /// A manifest with one plugin script, whose URL carries `version` the way WordPress versions its
  /// assets.
  private static func pluginManifest(version: String) -> String {
    #"{"scripts":"<script src=\"https://example.com/plugin.js?ver=\#(version)\"></script>","styles":"","allowed_block_types":[]}"#
  }

  /// One site's server and storage, shared by every service a test makes for it — as a host's
  /// services for one site share them.
  private final class TestSite {
    let configuration: EditorConfiguration
    let client = EditorAssetLibraryMockHTTPClient()
    let storageRoot = URL.randomTemporaryDirectory
    let cacheRoot = URL.randomTemporaryDirectory

    /// What the site's `editor-assets` endpoint answers.
    var manifest: String {
      didSet { serve() }
    }

    /// Whether every request to the site fails as it would with no connection.
    var isOffline = false {
      didSet { serve() }
    }

    /// The error a request for a URL fails with, for the requests that should fail.
    var failure: (@Sendable (URL) -> (any Error)?)? {
      didSet { serve() }
    }

    var manifestRequestCount: Int {
      client.requestedURLs.filter { $0.absoluteString.contains("editor-assets") }.count
    }

    var postRequestCount: Int {
      client.requestedURLs.filter { $0.absoluteString.contains("/wp/v2/posts/") }.count
    }

    init(configuration: EditorConfiguration, manifest: String) {
      self.configuration = configuration
      self.manifest = manifest
      serve()
    }

    func service(cachePolicy: EditorCachePolicy) -> EditorService {
      EditorService(
        configuration: configuration,
        httpClient: client,
        cachePolicy: cachePolicy,
        storageRoot: storageRoot,
        cacheRoot: cacheRoot
      )
    }

    /// Makes it look as though the site's manifest was last found to match `bundle` at `date`.
    func setLastManifestCheck(of bundle: EditorAssetBundle, to date: Date) throws {
      try EditorAssetBundle(
        manifest: bundle.manifest,
        downloadDate: bundle.downloadDate,
        lastCheckedDate: date,
        bundleRoot: bundle.bundleRoot
      ).writeManifest()
    }

    private func serve() {
      client.urlResponseHandler = { [manifest, isOffline, failure] url in
        guard !isOffline else { throw URLError(.notConnectedToInternet) }
        if let error = failure?(url) { throw error }
        return url.absoluteString.contains("editor-assets")
          ? Data(manifest.utf8) : EditorServiceTests.editorServiceResponseHandler(url)
      }
    }
  }

  /// A site no other test, and no earlier run, has prepared.
  private static func uniqueSiteURL() -> URL {
    URL(string: "https://\(UUID().uuidString.lowercased()).example")!
  }

  /// Removes the record of when each site's bundles were last cleaned up automatically, which
  /// would otherwise outlive the test in the user defaults.
  private static func forgetAutomaticCleanups(of sites: [TestSite]) {
    let hosts = sites.compactMap { $0.configuration.siteURL.host() }
    for key in UserDefaults.standard.dictionaryRepresentation().keys
    where key.hasPrefix("once-every-") && hosts.contains(where: key.contains) {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }
}

/// Answers every request from `respond`, but holds each one until the test releases the caller
/// that made it — named by ``caller``, which a test sets around the work it starts.
private final class GatedHTTPClient: EditorHTTPClientProtocol, @unchecked Sendable {
  @TaskLocal static var caller = ""

  private let respond: @Sendable (URL) -> Data
  private let lock = NSLock()
  private var holding: [String: Int] = [:]
  private var released: Set<String> = []

  init(respond: @escaping @Sendable (URL) -> Data) {
    self.respond = respond
  }

  /// Whether a request from `caller` is being held.
  func isHolding(_ caller: String) -> Bool {
    lock.withLock { holding[caller, default: 0] > 0 }
  }

  /// Lets every request from `caller`, held or still to come, through.
  func release(_ caller: String) {
    lock.withLock { _ = released.insert(caller) }
  }

  func perform(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let caller = Self.caller
    lock.withLock { holding[caller, default: 0] += 1 }
    defer { lock.withLock { holding[caller, default: 0] -= 1 } }
    while !lock.withLock({ released.contains(caller) }) {
      try await Task.sleep(for: .milliseconds(5))
    }
    let url = try #require(urlRequest.url)
    return (respond(url), try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
  }

  func download(_ urlRequest: URLRequest) async throws -> (URL, HTTPURLResponse) {
    throw URLError(.unsupportedURL)
  }
}
