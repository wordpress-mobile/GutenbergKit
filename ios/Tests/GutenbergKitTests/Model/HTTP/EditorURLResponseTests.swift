import Foundation
import Testing

@testable import GutenbergKit

@Suite
struct EditorURLResponseTests {

  // MARK: - Initialization Tests

  @Test("Initializes with data and headers")
  func initializesWithDataAndHeaders() {
    let data = Data("test content".utf8)
    let headers: EditorHTTPHeaders = ["Content-Type": "text/plain"]

    let response = EditorURLResponse(data: data, responseHeaders: headers)

    #expect(response.data == data)
    #expect(response.responseHeaders == headers)
  }

  @Test("Initializes with string and headers")
  func initializesWithStringAndHeaders() {
    let content = "test content"
    let headers: EditorHTTPHeaders = ["Content-Type": "text/plain"]

    let response = EditorURLResponse(string: content, responseHeaders: headers)

    #expect(String(data: response.data, encoding: .utf8) == content)
    #expect(response.responseHeaders == headers)
  }

  @Test("Initializes from HTTPURLResponse")
  func initializesFromHTTPURLResponse() {
    let data = Data("test".utf8)
    let url = URL(string: "https://example.com")!
    let httpResponse = HTTPURLResponse(
      url: url,
      statusCode: 200,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!

    let response = EditorURLResponse(data: data, httpUrlResponse: httpResponse)

    #expect(response.data == data)
    #expect(response.responseHeaders["Content-Type"] == "application/json")
  }

  @Test("Initializes from tuple")
  func initializesFromTuple() {
    let data = Data("test".utf8)
    let url = URL(string: "https://example.com")!
    let httpResponse = HTTPURLResponse(
      url: url,
      statusCode: 200,
      httpVersion: "HTTP/1.1",
      headerFields: ["Accept": "text/html"]
    )!

    let response = EditorURLResponse((data, httpResponse))

    #expect(response.data == data)
    #expect(response.responseHeaders["Accept"] == "text/html")
  }

  // MARK: - Equatable Tests

  @Test("Equal responses are equal")
  func equalResponsesAreEqual() {
    let data = Data("test".utf8)
    let headers: EditorHTTPHeaders = ["Content-Type": "text/plain"]

    let response1 = EditorURLResponse(data: data, responseHeaders: headers)
    let response2 = EditorURLResponse(data: data, responseHeaders: headers)

    #expect(response1 == response2)
  }

  @Test("Responses with different data are not equal")
  func responsesWithDifferentDataAreNotEqual() {
    let headers: EditorHTTPHeaders = ["Content-Type": "text/plain"]

    let response1 = EditorURLResponse(data: Data("test1".utf8), responseHeaders: headers)
    let response2 = EditorURLResponse(data: Data("test2".utf8), responseHeaders: headers)

    #expect(response1 != response2)
  }

  @Test("Responses with different headers are not equal")
  func responsesWithDifferentHeadersAreNotEqual() {
    let data = Data("test".utf8)

    let response1 = EditorURLResponse(data: data, responseHeaders: ["Content-Type": "text/plain"])
    let response2 = EditorURLResponse(
      data: data, responseHeaders: ["Content-Type": "application/json"])

    #expect(response1 != response2)
  }

  // MARK: - Codable Tests

  @Test("Response can be encoded and decoded")
  func responseCanBeEncodedAndDecoded() throws {
    let data = Data("test content".utf8)
    let headers: EditorHTTPHeaders = [
      "Content-Type": "application/json",
      "X-Request-Id": "123"
    ]
    let original = EditorURLResponse(data: data, responseHeaders: headers)

    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(EditorURLResponse.self, from: encoded)

    #expect(decoded == original)
  }
}
