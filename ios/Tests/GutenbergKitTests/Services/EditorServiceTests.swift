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
}
