package org.wordpress.gutenberg.model

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.wordpress.gutenberg.model.http.EditorHTTPHeaders
import org.wordpress.gutenberg.model.http.EditorURLResponse

class EditorPreloadListTest {

    // MARK: - Test Fixtures

    private val json = Json { ignoreUnknownKeys = true }

    private fun makeResponse(
        data: String = "{}",
        headers: EditorHTTPHeaders = EditorHTTPHeaders()
    ): EditorURLResponse {
        return EditorURLResponse(data = data, responseHeaders = headers)
    }

    private fun loadExpectedJSON(name: String): JsonElement {
        val data = TestResources.loadResource("$name.json")
        return json.parseToJsonElement(data)
    }

    // MARK: - Initialization Tests

    @Test
    fun `initializes with postID and postData`() {
        val postData = makeResponse(data = """{"id":42}""")
        val preloadList = EditorPreloadList(
            postID = 42,
            postData = postData,
            postType = PostTypeDetails.post,
            postTypeData = makeResponse(),
            postTypesData = makeResponse(),
            activeThemeData = makeResponse(),
            settingsOptionsData = makeResponse()
        )

        assertEquals(42, preloadList.postID)
        assertNotNull(preloadList.postData)
    }

    @Test
    fun `initializes with custom post type`() {
        val preloadList = EditorPreloadList(
            postType = PostTypeDetails.page,
            postTypeData = makeResponse(),
            postTypesData = makeResponse(),
            activeThemeData = makeResponse(),
            settingsOptionsData = makeResponse()
        )

        assertEquals(PostTypeDetails.page, preloadList.postType)
    }

    // MARK: - build() Exact Output Tests

    @Test
    fun `build produces exact JSON for post type`() {
        val preloadList = EditorPreloadList(
            postType = PostTypeDetails.post,
            postTypeData = makeResponse(data = """{"slug":"post"}"""),
            postTypesData = makeResponse(data = "{}"),
            activeThemeData = makeResponse(data = "[]"),
            settingsOptionsData = makeResponse(data = "{}")
        )

        val expected = loadExpectedJSON("preload-list-post-type")
        val actual = preloadList.build()
        assertEquals(expected, actual)
    }

    @Test
    fun `build produces exact JSON for page type`() {
        val preloadList = EditorPreloadList(
            postType = PostTypeDetails.page,
            postTypeData = makeResponse(data = """{"slug":"page"}"""),
            postTypesData = makeResponse(data = "{}"),
            activeThemeData = makeResponse(data = "[]"),
            settingsOptionsData = makeResponse(data = "{}")
        )

        val expected = loadExpectedJSON("preload-list-page-type")
        val actual = preloadList.build()
        assertEquals(expected, actual)
    }

    @Test
    fun `build produces exact JSON with post data included`() {
        val preloadList = EditorPreloadList(
            postID = 123,
            postData = makeResponse(data = """{"id":123,"title":"Test"}"""),
            postType = PostTypeDetails.post,
            postTypeData = makeResponse(data = "{}"),
            postTypesData = makeResponse(data = "{}"),
            activeThemeData = makeResponse(data = "[]"),
            settingsOptionsData = makeResponse(data = "{}")
        )

        val expected = loadExpectedJSON("preload-list-with-post-data")
        val actual = preloadList.build()
        assertEquals(expected, actual)
    }

    @Test
    fun `build produces exact JSON with Accept header`() {
        val headers = EditorHTTPHeaders(mapOf("Accept" to "application/json"))
        val preloadList = EditorPreloadList(
            postType = PostTypeDetails.post,
            postTypeData = makeResponse(data = "{}", headers = headers),
            postTypesData = makeResponse(data = "{}"),
            activeThemeData = makeResponse(data = "[]"),
            settingsOptionsData = makeResponse(data = "{}")
        )

        val expected = loadExpectedJSON("preload-list-with-accept-header")
        val actual = preloadList.build()
        assertEquals(expected, actual)
    }

    @Test
    fun `build produces exact JSON with Link header`() {
        val headers = EditorHTTPHeaders(mapOf("Link" to """<https://example.com>; rel="next""""))
        val preloadList = EditorPreloadList(
            postType = PostTypeDetails.post,
            postTypeData = makeResponse(data = "{}", headers = headers),
            postTypesData = makeResponse(data = "{}"),
            activeThemeData = makeResponse(data = "[]"),
            settingsOptionsData = makeResponse(data = "{}")
        )

        val expected = loadExpectedJSON("preload-list-with-link-header")
        val actual = preloadList.build()
        assertEquals(expected, actual)
    }

    @Test
    fun `build produces exact JSON with multiple headers sorted alphabetically`() {
        val headers = EditorHTTPHeaders(
            mapOf("Link" to "<https://example.com>", "Accept" to "application/json")
        )
        val preloadList = EditorPreloadList(
            postType = PostTypeDetails.post,
            postTypeData = makeResponse(data = "{}", headers = headers),
            postTypesData = makeResponse(data = "{}"),
            activeThemeData = makeResponse(data = "[]"),
            settingsOptionsData = makeResponse(data = "{}")
        )

        val expected = loadExpectedJSON("preload-list-with-multiple-headers")
        val actual = preloadList.build()
        assertEquals(expected, actual)
    }

    @Test
    fun `build excludes post when postID is nil`() {
        val preloadList = EditorPreloadList(
            postID = null,
            postData = null,
            postType = PostTypeDetails.post,
            postTypeData = makeResponse(),
            postTypesData = makeResponse(),
            activeThemeData = makeResponse(),
            settingsOptionsData = makeResponse()
        )

        val expected = loadExpectedJSON("preload-list-empty-body")
        val actual = preloadList.build()
        assertEquals(expected, actual)
    }

    @Test
    fun `build excludes post when postData is nil`() {
        val preloadList = EditorPreloadList(
            postID = 42,
            postData = null,
            postType = PostTypeDetails.post,
            postTypeData = makeResponse(),
            postTypesData = makeResponse(),
            activeThemeData = makeResponse(),
            settingsOptionsData = makeResponse()
        )

        val expected = loadExpectedJSON("preload-list-empty-body")
        val actual = preloadList.build()
        assertEquals(expected, actual)
    }

    @Test
    fun `build produces exact JSON for custom_post_type`() {
        val preloadList = EditorPreloadList(
            postType = PostTypeDetails(postType = "custom_post_type", restBase = "custom_post_type"),
            postTypeData = makeResponse(),
            postTypesData = makeResponse(),
            activeThemeData = makeResponse(),
            settingsOptionsData = makeResponse()
        )

        val expected = loadExpectedJSON("preload-list-custom-post-type")
        val actual = preloadList.build()
        assertEquals(expected, actual)
    }

    // MARK: - build(formatted:) String Output Tests

    @Test
    fun `build(formatted = false) returns valid JSON string`() {
        val preloadList = EditorPreloadList(
            postType = PostTypeDetails.post,
            postTypeData = makeResponse(data = """{"slug":"post"}"""),
            postTypesData = makeResponse(data = "{}"),
            activeThemeData = makeResponse(data = "[]"),
            settingsOptionsData = makeResponse(data = "{}")
        )

        val jsonString = preloadList.build(formatted = false)
        val parsed = json.parseToJsonElement(jsonString)
        assertTrue(parsed.toString().isNotEmpty())
    }

    @Test
    fun `build(formatted = true) returns valid JSON string`() {
        val preloadList = EditorPreloadList(
            postType = PostTypeDetails.post,
            postTypeData = makeResponse(data = """{"slug":"post"}"""),
            postTypesData = makeResponse(data = "{}"),
            activeThemeData = makeResponse(data = "[]"),
            settingsOptionsData = makeResponse(data = "{}")
        )

        val jsonString = preloadList.build(formatted = true)
        val parsed = json.parseToJsonElement(jsonString)
        assertTrue(parsed.toString().isNotEmpty())
    }

    @Test
    fun `build(formatted = true) produces pretty-printed JSON`() {
        val preloadList = EditorPreloadList(
            postType = PostTypeDetails.post,
            postTypeData = makeResponse(data = "{}"),
            postTypesData = makeResponse(data = "{}"),
            activeThemeData = makeResponse(data = "[]"),
            settingsOptionsData = makeResponse(data = "{}")
        )

        val jsonString = preloadList.build(formatted = true)
        // Keys are sorted alphabetically to ensure same behaviour between platforms
        val expected = """
            |{
            |    "/wp/v2/themes?context=edit&status=active": {
            |        "body": [],
            |        "headers": {}
            |    },
            |    "/wp/v2/types/post?context=edit": {
            |        "body": {},
            |        "headers": {}
            |    },
            |    "/wp/v2/types?context=view": {
            |        "body": {},
            |        "headers": {}
            |    },
            |    "OPTIONS": {
            |        "/wp/v2/settings": {
            |            "body": {},
            |            "headers": {}
            |        }
            |    }
            |}
        """.trimMargin()
        assertEquals(expected, jsonString)
    }

    @Test
    fun `build(formatted) produces same JSON regardless of formatting`() {
        val preloadList = EditorPreloadList(
            postID = 123,
            postData = makeResponse(data = """{"id":123,"title":"Test"}"""),
            postType = PostTypeDetails.post,
            postTypeData = makeResponse(data = """{"slug":"post"}"""),
            postTypesData = makeResponse(data = "{}"),
            activeThemeData = makeResponse(data = "[]"),
            settingsOptionsData = makeResponse(data = "{}")
        )

        val unformatted = preloadList.build(formatted = false)
        val formatted = preloadList.build(formatted = true)

        val parsedUnformatted = json.parseToJsonElement(unformatted)
        val parsedFormatted = json.parseToJsonElement(formatted)

        assertEquals(parsedUnformatted, parsedFormatted)
    }

    @Test
    fun `build(formatted) matches build() JSON object`() {
        val preloadList = EditorPreloadList(
            postID = 123,
            postData = makeResponse(data = """{"id":123,"title":"Test"}"""),
            postType = PostTypeDetails.post,
            postTypeData = makeResponse(data = """{"slug":"post"}"""),
            postTypesData = makeResponse(data = "{}"),
            activeThemeData = makeResponse(data = "[]"),
            settingsOptionsData = makeResponse(data = "{}")
        )

        val jsonObject = preloadList.build()
        val jsonString = preloadList.build(formatted = false)
        val parsedString = json.parseToJsonElement(jsonString)

        assertEquals(jsonObject, parsedString)
    }

    // MARK: - Header Filtering Tests

    @Test
    fun `filters out Content-Type header`() {
        val headers = EditorHTTPHeaders(
            mapOf("Accept" to "application/json", "Content-Type" to "application/json")
        )
        val preloadList = EditorPreloadList(
            postType = PostTypeDetails.post,
            postTypeData = makeResponse(headers = headers),
            postTypesData = makeResponse(),
            activeThemeData = makeResponse(),
            settingsOptionsData = makeResponse()
        )

        assertEquals("application/json", preloadList.postTypeData.responseHeaders["Accept"])
        assertNull(preloadList.postTypeData.responseHeaders["Content-Type"])
    }

    @Test
    fun `filters out X-Custom header`() {
        val headers = EditorHTTPHeaders(
            mapOf("Accept" to "application/json", "X-Custom" to "value")
        )
        val preloadList = EditorPreloadList(
            postType = PostTypeDetails.post,
            postTypeData = makeResponse(headers = headers),
            postTypesData = makeResponse(),
            activeThemeData = makeResponse(),
            settingsOptionsData = makeResponse()
        )

        assertEquals("application/json", preloadList.postTypeData.responseHeaders["Accept"])
        assertNull(preloadList.postTypeData.responseHeaders["X-Custom"])
    }

    @Test
    fun `filters headers for postData`() {
        val headers = EditorHTTPHeaders(
            mapOf("Accept" to "application/json", "Content-Type" to "application/json")
        )
        val preloadList = EditorPreloadList(
            postID = 1,
            postData = makeResponse(headers = headers),
            postType = PostTypeDetails.post,
            postTypeData = makeResponse(),
            postTypesData = makeResponse(),
            activeThemeData = makeResponse(),
            settingsOptionsData = makeResponse()
        )

        assertEquals("application/json", preloadList.postData?.responseHeaders?.get("Accept"))
        assertNull(preloadList.postData?.responseHeaders?.get("Content-Type"))
    }

    // MARK: - Equatable Tests

    @Test
    fun `two preload lists with same data are equal`() {
        val response = makeResponse(data = """{"test":true}""")
        val preloadList1 = EditorPreloadList(
            postType = PostTypeDetails.post,
            postTypeData = response,
            postTypesData = response,
            activeThemeData = response,
            settingsOptionsData = response
        )
        val preloadList2 = EditorPreloadList(
            postType = PostTypeDetails.post,
            postTypeData = response,
            postTypesData = response,
            activeThemeData = response,
            settingsOptionsData = response
        )

        assertEquals(preloadList1, preloadList2)
    }

    @Test
    fun `preload lists with different post types are not equal`() {
        val response = makeResponse()
        val preloadList1 = EditorPreloadList(
            postType = PostTypeDetails.post,
            postTypeData = response,
            postTypesData = response,
            activeThemeData = response,
            settingsOptionsData = response
        )
        val preloadList2 = EditorPreloadList(
            postType = PostTypeDetails.page,
            postTypeData = response,
            postTypesData = response,
            activeThemeData = response,
            settingsOptionsData = response
        )

        assertNotEquals(preloadList1, preloadList2)
    }

    @Test
    fun `preload lists with different postID are not equal`() {
        val response = makeResponse()
        val preloadList1 = EditorPreloadList(
            postID = 1,
            postData = response,
            postType = PostTypeDetails.post,
            postTypeData = response,
            postTypesData = response,
            activeThemeData = response,
            settingsOptionsData = response
        )
        val preloadList2 = EditorPreloadList(
            postID = 2,
            postData = response,
            postType = PostTypeDetails.post,
            postTypeData = response,
            postTypesData = response,
            activeThemeData = response,
            settingsOptionsData = response
        )

        assertNotEquals(preloadList1, preloadList2)
    }
}
