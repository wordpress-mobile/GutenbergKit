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
    let mockClient = EditorServiceURLTrackingMockHTTPClient()
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
    let mockClient = EditorServiceURLTrackingMockHTTPClient()
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
    let mockClient = EditorServiceURLTrackingMockHTTPClient()
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
}

// MARK: - Mock HTTP Client for URL Tracking

final class EditorServiceURLTrackingMockHTTPClient: EditorHTTPClientProtocol, @unchecked Sendable {
  private let lock = NSLock()
  private var _requestedURLs: [URL] = []

  var requestedURLs: [URL] {
    lock.withLock { _requestedURLs }
  }

  func perform(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let url = urlRequest.url!
    lock.withLock { _requestedURLs.append(url) }

    let responseData: Data
    let urlString = url.absoluteString

    // Return appropriate mock responses based on URL
    if urlString.contains("editor-assets") {
      responseData = Data(#"{"scripts":"","styles":"","allowed_block_types":[]}"#.utf8)
    } else if urlString.contains("wp-block-editor/v1/settings") {
      responseData = Data(#"{"styles":[]}"#.utf8)
    } else if urlString.contains("/wp/v2/types/") && urlString.contains("context=edit") {
      responseData = Data(#"{"name":"Posts","slug":"post"}"#.utf8)
    } else if urlString.contains("/wp/v2/types") {
      responseData = Data(#"{"post":{"name":"Posts","slug":"post"}}"#.utf8)
    } else if urlString.contains("/wp/v2/themes") {
      responseData = Data(#"[{"name":"Twenty Twenty-Four"}]"#.utf8)
    } else if urlString.contains("/wp/v2/settings") {
      responseData = Data(#"{"title":"Test Site"}"#.utf8)
    } else if urlString.contains("/wp/v2/posts/") {
      responseData = Data(#"{"id":123,"title":{"rendered":"Test"}}"#.utf8)
    } else {
      responseData = Data("{}".utf8)
    }

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
    lock.withLock { _requestedURLs.append(url) }

    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data("mock content".utf8).write(to: tempURL)

    let response = HTTPURLResponse(
      url: url,
      statusCode: 200,
      httpVersion: "HTTP/1.1",
      headerFields: nil
    )!

    return (tempURL, response)
  }
}
