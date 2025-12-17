import Foundation
import Testing

@testable import GutenbergKit

@Suite
struct EditorPreloadListTests {

  // MARK: - Test Fixtures

  private func makeResponse(data: String = "{}", headers: EditorHTTPHeaders = [:])
    -> EditorURLResponse {
    EditorURLResponse(data: Data(data.utf8), responseHeaders: headers)
  }

  private func loadExpectedJSON(_ name: String) throws -> JSON {
    let url = Bundle.module.url(forResource: name, withExtension: "json")!
    let data = try Data(contentsOf: url)
    return try JSON(data)
  }

  // MARK: - Initialization Tests

  @Test("initializes with postID and postData")
  func initializesWithPostData() {
    let postData = makeResponse(data: #"{"id":42}"#)
    let preloadList = EditorPreloadList(
      postID: 42,
      postData: postData,
      postType: "post",
      postTypeData: makeResponse(),
      postTypesData: makeResponse(),
      activeThemeData: makeResponse(),
      settingsOptionsData: makeResponse()
    )

    #expect(preloadList.postID == 42)
    #expect(preloadList.postData != nil)
  }

  @Test("initializes with custom post type")
  func initializesWithCustomPostType() {
    let preloadList = EditorPreloadList(
      postType: "page",
      postTypeData: makeResponse(),
      postTypesData: makeResponse(),
      activeThemeData: makeResponse(),
      settingsOptionsData: makeResponse()
    )
    #expect(preloadList.postType == "page")
  }

  // MARK: - build(formatted:) Exact Output Tests

  @Test("build produces exact JSON for post type")
  func buildProducesExactJsonForPostType() throws {
    let preloadList = EditorPreloadList(
      postType: "post",
      postTypeData: makeResponse(data: #"{"slug":"post"}"#),
      postTypesData: makeResponse(data: "{}"),
      activeThemeData: makeResponse(data: "[]"),
      settingsOptionsData: makeResponse(data: "{}")
    )

    let expected = try loadExpectedJSON("preload-list-post-type")
    let actual = try preloadList.build()
    #expect(actual == expected)
  }

  @Test("build produces exact JSON for page type")
  func buildProducesExactJsonForPageType() throws {
    let preloadList = EditorPreloadList(
      postType: "page",
      postTypeData: makeResponse(data: #"{"slug":"page"}"#),
      postTypesData: makeResponse(data: "{}"),
      activeThemeData: makeResponse(data: "[]"),
      settingsOptionsData: makeResponse(data: "{}")
    )

    let expected = try loadExpectedJSON("preload-list-page-type")
    let actual = try preloadList.build()
    #expect(actual == expected)
  }

  @Test("build produces exact JSON with post data included")
  func buildProducesExactJsonWithPostData() throws {
    let preloadList = EditorPreloadList(
      postID: 123,
      postData: makeResponse(data: #"{"id":123,"title":"Test"}"#),
      postType: "post",
      postTypeData: makeResponse(data: "{}"),
      postTypesData: makeResponse(data: "{}"),
      activeThemeData: makeResponse(data: "[]"),
      settingsOptionsData: makeResponse(data: "{}")
    )

    let expected = try loadExpectedJSON("preload-list-with-post-data")
    let actual = try preloadList.build()
    #expect(actual == expected)
  }

  @Test("build produces exact JSON with Accept header")
  func buildProducesExactJsonWithAcceptHeader() throws {
    let headers: EditorHTTPHeaders = ["Accept": "application/json"]
    let preloadList = EditorPreloadList(
      postType: "post",
      postTypeData: makeResponse(data: "{}", headers: headers),
      postTypesData: makeResponse(data: "{}"),
      activeThemeData: makeResponse(data: "[]"),
      settingsOptionsData: makeResponse(data: "{}")
    )

    let expected = try loadExpectedJSON("preload-list-with-accept-header")
    let actual = try preloadList.build()
    #expect(actual == expected)
  }

  @Test("build produces exact JSON with Link header")
  func buildProducesExactJsonWithLinkHeader() throws {
    let headers: EditorHTTPHeaders = ["Link": #"<https://example.com>; rel="next""#]
    let preloadList = EditorPreloadList(
      postType: "post",
      postTypeData: makeResponse(data: "{}", headers: headers),
      postTypesData: makeResponse(data: "{}"),
      activeThemeData: makeResponse(data: "[]"),
      settingsOptionsData: makeResponse(data: "{}")
    )

    let expected = try loadExpectedJSON("preload-list-with-link-header")
    let actual = try preloadList.build()
    #expect(actual == expected)
  }

  @Test("build produces exact JSON with multiple headers sorted alphabetically")
  func buildProducesExactJsonWithMultipleHeaders() throws {
    let headers: EditorHTTPHeaders = [
      "Link": "<https://example.com>", "Accept": "application/json"
    ]
    let preloadList = EditorPreloadList(
      postType: "post",
      postTypeData: makeResponse(data: "{}", headers: headers),
      postTypesData: makeResponse(data: "{}"),
      activeThemeData: makeResponse(data: "[]"),
      settingsOptionsData: makeResponse(data: "{}")
    )

    let expected = try loadExpectedJSON("preload-list-with-multiple-headers")
    let actual = try preloadList.build()
    #expect(actual == expected)
  }

  @Test("build excludes post when postID is nil")
  func buildExcludesPostWhenPostIDIsNil() throws {
    let preloadList = EditorPreloadList(
      postID: nil,
      postData: nil,
      postType: "post",
      postTypeData: makeResponse(),
      postTypesData: makeResponse(),
      activeThemeData: makeResponse(),
      settingsOptionsData: makeResponse()
    )

    let expected = try loadExpectedJSON("preload-list-empty-body")
    let actual = try preloadList.build()
    #expect(actual == expected)
  }

  @Test("build excludes post when postData is nil")
  func buildExcludesPostWhenPostDataIsNil() throws {
    let preloadList = EditorPreloadList(
      postID: 42,
      postData: nil,
      postType: "post",
      postTypeData: makeResponse(),
      postTypesData: makeResponse(),
      activeThemeData: makeResponse(),
      settingsOptionsData: makeResponse()
    )

    let expected = try loadExpectedJSON("preload-list-empty-body")
    let actual = try preloadList.build()
    #expect(actual == expected)
  }

  @Test("build produces exact JSON for custom_post_type")
  func buildProducesExactJsonForCustomPostType() throws {
    let preloadList = EditorPreloadList(
      postType: "custom_post_type",
      postTypeData: makeResponse(),
      postTypesData: makeResponse(),
      activeThemeData: makeResponse(),
      settingsOptionsData: makeResponse()
    )

    let expected = try loadExpectedJSON("preload-list-custom-post-type")
    let actual = try preloadList.build()
    #expect(actual == expected)
  }

  // MARK: - build(formatted:) String Output Tests

  @Test("build(formatted: false) returns valid JSON string")
  func buildUnformattedReturnsValidJSON() throws {
    let preloadList = EditorPreloadList(
      postType: "post",
      postTypeData: makeResponse(data: #"{"slug":"post"}"#),
      postTypesData: makeResponse(data: "{}"),
      activeThemeData: makeResponse(data: "[]"),
      settingsOptionsData: makeResponse(data: "{}")
    )

    let jsonString = try preloadList.build(formatted: false)
    let parsed = try JSON(Data(jsonString.utf8))
    #expect(parsed.isObject)
  }

  @Test("build(formatted: true) returns valid JSON string")
  func buildFormattedReturnsValidJSON() throws {
    let preloadList = EditorPreloadList(
      postType: "post",
      postTypeData: makeResponse(data: #"{"slug":"post"}"#),
      postTypesData: makeResponse(data: "{}"),
      activeThemeData: makeResponse(data: "[]"),
      settingsOptionsData: makeResponse(data: "{}")
    )

    let jsonString = try preloadList.build(formatted: true)
    let parsed = try JSON(Data(jsonString.utf8))
    #expect(parsed.isObject)
  }

  @Test("build(formatted: true) produces pretty-printed JSON")
  func buildFormattedProducesPrettyPrintedJSON() throws {
    let preloadList = EditorPreloadList(
      postType: "post",
      postTypeData: makeResponse(data: "{}"),
      postTypesData: makeResponse(data: "{}"),
      activeThemeData: makeResponse(data: "[]"),
      settingsOptionsData: makeResponse(data: "{}")
    )

    let jsonString = try preloadList.build(formatted: true)
    let expected = """
      {
        "/wp/v2/themes?context=edit&status=active" : {
          "body" : [

          ],
          "headers" : {

          }
        },
        "/wp/v2/types?context=view" : {
          "body" : {

          },
          "headers" : {

          }
        },
        "/wp/v2/types/post?context=edit" : {
          "body" : {

          },
          "headers" : {

          }
        },
        "OPTIONS" : {
          "/wp/v2/settings" : {
            "body" : {

            },
            "headers" : {

            }
          }
        }
      }
      """
    #expect(jsonString == expected)
  }

  @Test("build(formatted:) produces same JSON regardless of formatting")
  func buildFormattedAndUnformattedAreSemanticallyEqual() throws {
    let preloadList = EditorPreloadList(
      postID: 123,
      postData: makeResponse(data: #"{"id":123,"title":"Test"}"#),
      postType: "post",
      postTypeData: makeResponse(data: #"{"slug":"post"}"#),
      postTypesData: makeResponse(data: "{}"),
      activeThemeData: makeResponse(data: "[]"),
      settingsOptionsData: makeResponse(data: "{}")
    )

    let unformatted = try preloadList.build(formatted: false)
    let formatted = try preloadList.build(formatted: true)

    let parsedUnformatted = try JSON(Data(unformatted.utf8))
    let parsedFormatted = try JSON(Data(formatted.utf8))

    #expect(parsedUnformatted == parsedFormatted)
  }

  @Test("build(formatted:) matches build() JSON object")
  func buildFormattedMatchesBuildJSON() throws {
    let preloadList = EditorPreloadList(
      postID: 123,
      postData: makeResponse(data: #"{"id":123,"title":"Test"}"#),
      postType: "post",
      postTypeData: makeResponse(data: #"{"slug":"post"}"#),
      postTypesData: makeResponse(data: "{}"),
      activeThemeData: makeResponse(data: "[]"),
      settingsOptionsData: makeResponse(data: "{}")
    )

    let jsonObject = try preloadList.build()
    let jsonString = try preloadList.build(formatted: false)
    let parsedString = try JSON(Data(jsonString.utf8))

    #expect(jsonObject == parsedString)
  }

  // MARK: - Header Filtering Tests

  @Test("filters out Content-Type header")
  func filtersOutContentTypeHeader() {
    let headers: EditorHTTPHeaders = [
      "Accept": "application/json", "Content-Type": "application/json"
    ]
    let preloadList = EditorPreloadList(
      postType: "post",
      postTypeData: makeResponse(headers: headers),
      postTypesData: makeResponse(),
      activeThemeData: makeResponse(),
      settingsOptionsData: makeResponse()
    )

    #expect(preloadList.postTypeData.responseHeaders["Accept"] == "application/json")
    #expect(preloadList.postTypeData.responseHeaders["Content-Type"] == nil)
  }

  @Test("filters out X-Custom header")
  func filtersOutCustomHeader() {
    let headers: EditorHTTPHeaders = ["Accept": "application/json", "X-Custom": "value"]
    let preloadList = EditorPreloadList(
      postType: "post",
      postTypeData: makeResponse(headers: headers),
      postTypesData: makeResponse(),
      activeThemeData: makeResponse(),
      settingsOptionsData: makeResponse()
    )

    #expect(preloadList.postTypeData.responseHeaders["Accept"] == "application/json")
    #expect(preloadList.postTypeData.responseHeaders["X-Custom"] == nil)
  }

  @Test("filters headers for postData")
  func filtersHeadersForPostData() {
    let headers: EditorHTTPHeaders = [
      "Accept": "application/json", "Content-Type": "application/json"
    ]
    let preloadList = EditorPreloadList(
      postID: 1,
      postData: makeResponse(headers: headers),
      postType: "post",
      postTypeData: makeResponse(),
      postTypesData: makeResponse(),
      activeThemeData: makeResponse(),
      settingsOptionsData: makeResponse()
    )

    #expect(preloadList.postData?.responseHeaders["Content-Type"] == nil)
  }

  // MARK: - Equatable Tests

  @Test("two preload lists with same data are equal")
  func equalPreloadListsAreEqual() {
    let response = makeResponse(data: #"{"test":true}"#)
    let preloadList1 = EditorPreloadList(
      postType: "post",
      postTypeData: response,
      postTypesData: response,
      activeThemeData: response,
      settingsOptionsData: response
    )
    let preloadList2 = EditorPreloadList(
      postType: "post",
      postTypeData: response,
      postTypesData: response,
      activeThemeData: response,
      settingsOptionsData: response
    )

    #expect(preloadList1 == preloadList2)
  }

  @Test("preload lists with different post types are not equal")
  func differentPostTypesAreNotEqual() {
    let response = makeResponse()
    let preloadList1 = EditorPreloadList(
      postType: "post",
      postTypeData: response,
      postTypesData: response,
      activeThemeData: response,
      settingsOptionsData: response
    )
    let preloadList2 = EditorPreloadList(
      postType: "page",
      postTypeData: response,
      postTypesData: response,
      activeThemeData: response,
      settingsOptionsData: response
    )

    #expect(preloadList1 != preloadList2)
  }

  @Test("preload lists with different postID are not equal")
  func differentPostIDsAreNotEqual() {
    let response = makeResponse()
    let preloadList1 = EditorPreloadList(
      postID: 1,
      postData: response,
      postType: "post",
      postTypeData: response,
      postTypesData: response,
      activeThemeData: response,
      settingsOptionsData: response
    )
    let preloadList2 = EditorPreloadList(
      postID: 2,
      postData: response,
      postType: "post",
      postTypeData: response,
      postTypesData: response,
      activeThemeData: response,
      settingsOptionsData: response
    )

    #expect(preloadList1 != preloadList2)
  }
}
