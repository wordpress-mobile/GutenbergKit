import Foundation
import Testing
@testable import GutenbergKit

@Suite("WordPressRESTURL")
struct WordPressRESTURLTests {

  @Test("appends the path when no namespace is configured")
  func noNamespace() {
    let url = WordPressRESTURL.namespaced(
      apiRoot: URL(string: "https://example.com/wp-json")!,
      path: "/wp/v2/media",
      namespace: nil
    )
    #expect(url.absoluteString == "https://example.com/wp-json/wp/v2/media")
  }

  @Test("inserts the namespace after the version segment")
  func insertsNamespace() {
    let url = WordPressRESTURL.namespaced(
      apiRoot: URL(string: "https://example.com/wp-json")!,
      path: "/wp/v2/media",
      namespace: "sites/123/"
    )
    #expect(url.absoluteString == "https://example.com/wp-json/wp/v2/sites/123/media")
  }

  @Test("normalizes an unslashed root and namespace")
  func normalizesUnslashed() {
    let url = WordPressRESTURL.namespaced(
      apiRoot: URL(string: "https://example.com/wp-json")!, // no trailing slash
      path: "/wp/v2/media",
      namespace: "sites/123" // no trailing slash
    )
    #expect(url.absoluteString == "https://example.com/wp-json/wp/v2/sites/123/media")
  }

  @Test("does not double the slash when the root already ends in one")
  func trailingSlashRoot() {
    let url = WordPressRESTURL.namespaced(
      apiRoot: URL(string: "https://example.com/wp-json/")!, // trailing slash
      path: "/wp/v2/media",
      namespace: "sites/123"
    )
    #expect(url.absoluteString == "https://example.com/wp-json/wp/v2/sites/123/media")
  }

  @Test("does not double the slash when the root ends in two")
  func doubledTrailingSlashRoot() {
    let url = WordPressRESTURL.namespaced(
      apiRoot: URL(string: "https://example.com/wp-json//")!,
      path: "/wp/v2/media",
      namespace: "sites/123"
    )
    #expect(url.absoluteString == "https://example.com/wp-json/wp/v2/sites/123/media")
  }

  @Test("inserts the namespace after a non-wp/v2 version segment")
  func otherVersionSegment() {
    let url = WordPressRESTURL.namespaced(
      apiRoot: URL(string: "https://example.com/wp-json")!,
      path: "/wp-block-editor/v1/settings",
      namespace: "sites/123"
    )
    #expect(url.absoluteString == "https://example.com/wp-json/wp-block-editor/v1/sites/123/settings")
  }

  @Test("keeps a path query verbatim when inserting the namespace")
  func namespacedPathQuery() {
    let url = WordPressRESTURL.namespaced(
      apiRoot: URL(string: "https://example.com/wp-json")!,
      path: "/wp/v2/media/42?redirect=/a//b/",
      namespace: "sites/123"
    )
    #expect(url.absoluteString == "https://example.com/wp-json/wp/v2/sites/123/media/42?redirect=/a//b/")
  }

  // MARK: - Query-based API Roots (plain permalinks)

  @Test("merges the path query string into a query-based root")
  func mergesQueryIntoQueryRoot() {
    let url = WordPressRESTURL.namespaced(
      apiRoot: URL(string: "https://example.com/?rest_route=/")!,
      path: "/wp/v2/themes?context=edit&status=active",
      namespace: "sites/123"
    )
    #expect(url.absoluteString == "https://example.com/?rest_route=/wp/v2/sites/123/themes&context=edit&status=active")
  }
}
