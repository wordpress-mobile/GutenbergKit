import Foundation
import Testing

@testable import GutenbergKit

@Suite
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

  @Test("prepare() under .ignore checks the manifest, and keeps the bundle when it hasn't changed")
  func prepareUnderIgnoreKeepsUnchangedBundle() async throws {
    let site = TestSite(configuration: makeConfiguration(), manifest: Self.pluginManifest(version: "1"))
    let bundle = try await site.service(cachePolicy: .always).prepare().assetBundle

    let refreshed = try await site.service(cachePolicy: .ignore).prepare().assetBundle

    #expect(refreshed.id == bundle.id)
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

    var manifestRequestCount: Int {
      client.requestedURLs.filter { $0.absoluteString.contains("editor-assets") }.count
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
      client.urlResponseHandler = { [manifest, isOffline] url in
        guard !isOffline else { throw URLError(.notConnectedToInternet) }
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
