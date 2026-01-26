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
}
