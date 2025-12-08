import Foundation
import Testing

@testable import GutenbergKit

@Suite
struct EditorHTTPHeadersTests {

  // MARK: - Initialization Tests

  @Test("Empty initializer creates empty headers")
  func emptyInitializerCreatesEmptyHeaders() {
    let headers = EditorHTTPHeaders()

    #expect(headers["Content-Type"] == nil)
    #expect(headers["Accept"] == nil)
  }

  @Test("Dictionary literal initializer creates headers with values")
  func dictionaryLiteralInitializerCreatesHeaders() {
    let headers: EditorHTTPHeaders = [
      "Content-Type": "application/json",
      "Accept": "text/html"
    ]

    #expect(headers["Content-Type"] == "application/json")
    #expect(headers["Accept"] == "text/html")
  }

  @Test("Dictionary literal initializer handles empty dictionary")
  func dictionaryLiteralInitializerHandlesEmptyDictionary() {
    let headers: EditorHTTPHeaders = [:]

    #expect(headers["Content-Type"] == nil)
  }

  @Test("Dictionary literal initializer handles single entry")
  func dictionaryLiteralInitializerHandlesSingleEntry() {
    let headers: EditorHTTPHeaders = ["X-Custom-Header": "custom-value"]

    #expect(headers["X-Custom-Header"] == "custom-value")
  }

  @Test("AnyHashable dictionary initializer extracts string key-value pairs")
  func anyHashableDictionaryInitializerExtractsStrings() {
    let dictionary: [AnyHashable: Any] = [
      "Content-Type": "application/json",
      "Content-Length": "1234",
      "Accept": "text/html"
    ]

    let headers = EditorHTTPHeaders(dictionary)

    #expect(headers["Content-Type"] == "application/json")
    #expect(headers["Content-Length"] == "1234")
    #expect(headers["Accept"] == "text/html")
  }

  @Test("AnyHashable dictionary initializer ignores non-string keys")
  func anyHashableDictionaryInitializerIgnoresNonStringKeys() {
    let dictionary: [AnyHashable: Any] = [
      "Content-Type": "application/json",
      123: "numeric-key-value",
      true: "bool-key-value"
    ]

    let headers = EditorHTTPHeaders(dictionary)

    #expect(headers["Content-Type"] == "application/json")
    // Non-string keys should be ignored
    #expect(headers["123"] == nil)
  }

  @Test("AnyHashable dictionary initializer ignores non-string values")
  func anyHashableDictionaryInitializerIgnoresNonStringValues() {
    let dictionary: [AnyHashable: Any] = [
      "Content-Type": "application/json",
      "Content-Length": 1234,
      "Is-Valid": true,
      "Data": Data("test".utf8)
    ]

    let headers = EditorHTTPHeaders(dictionary)

    #expect(headers["Content-Type"] == "application/json")
    // Non-string values should be ignored
    #expect(headers["Content-Length"] == nil)
    #expect(headers["Is-Valid"] == nil)
    #expect(headers["Data"] == nil)
  }

  @Test("AnyHashable dictionary initializer handles empty dictionary")
  func anyHashableDictionaryInitializerHandlesEmptyDictionary() {
    let dictionary: [AnyHashable: Any] = [:]

    let headers = EditorHTTPHeaders(dictionary)

    #expect(headers["Content-Type"] == nil)
  }

  // MARK: - Subscript Tests

  @Test("Subscript getter returns value for existing key")
  func subscriptGetterReturnsValueForExistingKey() {
    let headers: EditorHTTPHeaders = ["Content-Type": "application/json"]

    #expect(headers["Content-Type"] == "application/json")
  }

  @Test("Subscript getter returns nil for missing key")
  func subscriptGetterReturnsNilForMissingKey() {
    let headers: EditorHTTPHeaders = ["Content-Type": "application/json"]

    #expect(headers["Accept"] == nil)
  }

  @Test("Subscript setter adds new value")
  func subscriptSetterAddsNewValue() {
    var headers = EditorHTTPHeaders()

    headers["Content-Type"] = "application/json"

    #expect(headers["Content-Type"] == "application/json")
  }

  @Test("Subscript setter updates existing value")
  func subscriptSetterUpdatesExistingValue() {
    var headers: EditorHTTPHeaders = ["Content-Type": "text/plain"]

    headers["Content-Type"] = "application/json"

    #expect(headers["Content-Type"] == "application/json")
  }

  @Test("Subscript setter removes value when set to nil")
  func subscriptSetterRemovesValueWhenSetToNil() {
    var headers: EditorHTTPHeaders = ["Content-Type": "application/json"]

    headers["Content-Type"] = nil

    #expect(headers["Content-Type"] == nil)
  }

  @Test("Subscript is case-insensitive")
  func subscriptIsCaseInsensitive() {
    let headers: EditorHTTPHeaders = ["Content-Type": "application/json"]

    #expect(headers["Content-Type"] == "application/json")
    #expect(headers["content-type"] == "application/json")
    #expect(headers["CONTENT-TYPE"] == "application/json")
  }

  @Test("Subscript setter is case-insensitive")
  func subscriptSetterIsCaseInsensitive() {
    var headers: EditorHTTPHeaders = ["Content-Type": "text/plain"]

    // Setting with different case should update the same key
    headers["CONTENT-TYPE"] = "application/json"

    #expect(headers["Content-Type"] == "application/json")
    #expect(headers["content-type"] == "application/json")
  }

  @Test("Headers with same keys but different case are equal")
  func headersWithSameKeysDifferentCaseAreEqual() {
    let headers1: EditorHTTPHeaders = ["Content-Type": "application/json"]
    let headers2: EditorHTTPHeaders = ["content-type": "application/json"]

    #expect(headers1 == headers2)
  }

  // MARK: - Equatable Tests

  @Test("Equal headers are equal")
  func equalHeadersAreEqual() {
    let headers1: EditorHTTPHeaders = [
      "Content-Type": "application/json",
      "Accept": "text/html"
    ]
    let headers2: EditorHTTPHeaders = [
      "Content-Type": "application/json",
      "Accept": "text/html"
    ]

    #expect(headers1 == headers2)
  }

  @Test("Empty headers are equal")
  func emptyHeadersAreEqual() {
    let headers1 = EditorHTTPHeaders()
    let headers2 = EditorHTTPHeaders()

    #expect(headers1 == headers2)
  }

  @Test("Headers with different values are not equal")
  func headersWithDifferentValuesAreNotEqual() {
    let headers1: EditorHTTPHeaders = ["Content-Type": "application/json"]
    let headers2: EditorHTTPHeaders = ["Content-Type": "text/plain"]

    #expect(headers1 != headers2)
  }

  @Test("Headers with different keys are not equal")
  func headersWithDifferentKeysAreNotEqual() {
    let headers1: EditorHTTPHeaders = ["Content-Type": "application/json"]
    let headers2: EditorHTTPHeaders = ["Accept": "application/json"]

    #expect(headers1 != headers2)
  }

  @Test("Headers with different counts are not equal")
  func headersWithDifferentCountsAreNotEqual() {
    let headers1: EditorHTTPHeaders = ["Content-Type": "application/json"]
    let headers2: EditorHTTPHeaders = [
      "Content-Type": "application/json",
      "Accept": "text/html"
    ]

    #expect(headers1 != headers2)
  }

  // MARK: - Codable Tests

  @Test("Headers can be encoded and decoded")
  func headersCanBeEncodedAndDecoded() throws {
    let original: EditorHTTPHeaders = [
      "Content-Type": "application/json",
      "Accept": "text/html",
      "X-Custom-Header": "custom-value"
    ]

    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(EditorHTTPHeaders.self, from: encoded)

    #expect(decoded == original)
  }

  @Test("Empty headers can be encoded and decoded")
  func emptyHeadersCanBeEncodedAndDecoded() throws {
    let original = EditorHTTPHeaders()

    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(EditorHTTPHeaders.self, from: encoded)

    #expect(decoded == original)
  }

  @Test("Headers preserve values through encoding round-trip")
  func headersPreserveValuesThroughEncodingRoundTrip() throws {
    let original: EditorHTTPHeaders = [
      "Content-Type": "application/json; charset=utf-8",
      "Authorization": "Bearer token123",
      "X-Request-ID": "550e8400-e29b-41d4-a716-446655440000"
    ]

    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(EditorHTTPHeaders.self, from: encoded)

    #expect(decoded["Content-Type"] == "application/json; charset=utf-8")
    #expect(decoded["Authorization"] == "Bearer token123")
    #expect(decoded["X-Request-ID"] == "550e8400-e29b-41d4-a716-446655440000")
  }

  // MARK: - Edge Cases

  @Test("Headers handle empty string values")
  func headersHandleEmptyStringValues() {
    let headers: EditorHTTPHeaders = ["Empty-Header": ""]

    #expect(headers["Empty-Header"] == "")
  }

  @Test("Headers handle values with special characters")
  func headersHandleValuesWithSpecialCharacters() {
    let headers: EditorHTTPHeaders = [
      "Content-Type": "application/json; charset=utf-8",
      "Link": "<https://example.com/page>; rel=\"next\"",
      "Set-Cookie": "session=abc123; Path=/; HttpOnly"
    ]

    #expect(headers["Content-Type"] == "application/json; charset=utf-8")
    #expect(headers["Link"] == "<https://example.com/page>; rel=\"next\"")
    #expect(headers["Set-Cookie"] == "session=abc123; Path=/; HttpOnly")
  }

  @Test("Headers handle unicode values")
  func headersHandleUnicodeValues() {
    let headers: EditorHTTPHeaders = [
      "X-Greeting": "こんにちは",
      "X-Emoji": "🎉"
    ]

    #expect(headers["X-Greeting"] == "こんにちは")
    #expect(headers["X-Emoji"] == "🎉")
  }

  @Test("Headers handle very long values")
  func headersHandleVeryLongValues() {
    let longValue = String(repeating: "a", count: 10000)
    let headers: EditorHTTPHeaders = ["X-Long-Header": longValue]

    #expect(headers["X-Long-Header"] == longValue)
  }

  @Test("Headers handle keys with hyphens")
  func headersHandleKeysWithHyphens() {
    let headers: EditorHTTPHeaders = [
      "Content-Type": "text/html",
      "X-Custom-Multi-Part-Header": "value",
      "Accept-Language": "en-US"
    ]

    #expect(headers["Content-Type"] == "text/html")
    #expect(headers["X-Custom-Multi-Part-Header"] == "value")
    #expect(headers["Accept-Language"] == "en-US")
  }

  // MARK: - Integration with HTTPURLResponse

  @Test("Headers can be created from HTTPURLResponse.allHeaderFields")
  func headersCanBeCreatedFromHTTPURLResponseAllHeaderFields() {
    // Simulate what HTTPURLResponse.allHeaderFields returns
    let responseHeaders: [AnyHashable: Any] = [
      "Content-Type": "application/json",
      "Content-Length": "256",
      "Cache-Control": "no-cache",
      "X-Request-Id": "abc123"
    ]

    let headers = EditorHTTPHeaders(responseHeaders)

    #expect(headers["Content-Type"] == "application/json")
    #expect(headers["Content-Length"] == "256")
    #expect(headers["Cache-Control"] == "no-cache")
    #expect(headers["X-Request-Id"] == "abc123")
  }

  // MARK: - Filtering Tests

  @Test("Filtering returns only matching headers")
  func filteringReturnsOnlyMatchingHeaders() {
    let headers: EditorHTTPHeaders = [
      "Content-Type": "application/json",
      "Accept": "text/html",
      "Link": "<https://example.com>; rel=\"next\""
    ]

    let filtered = headers.filtering(keys: "Content-Type", "Link")

    #expect(filtered["Content-Type"] == "application/json")
    #expect(filtered["Link"] == "<https://example.com>; rel=\"next\"")
    #expect(filtered["Accept"] == nil)
  }

  @Test("Filtering with no matching keys returns empty headers")
  func filteringWithNoMatchingKeysReturnsEmptyHeaders() {
    let headers: EditorHTTPHeaders = [
      "Content-Type": "application/json",
      "Accept": "text/html"
    ]

    let filtered = headers.filtering(keys: "X-Custom-Header")

    #expect(filtered["Content-Type"] == nil)
    #expect(filtered["Accept"] == nil)
    #expect(filtered["X-Custom-Header"] == nil)
  }

  @Test("Filtering is case-insensitive")
  func filteringIsCaseInsensitive() {
    let headers: EditorHTTPHeaders = [
      "Content-Type": "application/json",
      "Accept": "text/html",
      "Link": "<https://example.com>"
    ]

    // Filter with different case than stored keys
    let filtered = headers.filtering(keys: "content-type", "LINK")

    #expect(filtered["Content-Type"] == "application/json")
    #expect(filtered["Link"] == "<https://example.com>")
    #expect(filtered["Accept"] == nil)
  }
}
