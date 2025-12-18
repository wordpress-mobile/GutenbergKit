package org.wordpress.gutenberg

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.wordpress.gutenberg.model.EditorCachePolicy
import org.wordpress.gutenberg.model.TestResources
import org.wordpress.gutenberg.model.http.EditorHTTPHeaders
import org.wordpress.gutenberg.model.http.EditorHttpMethod
import org.wordpress.gutenberg.model.http.EditorURLResponse
import org.wordpress.gutenberg.stores.EditorURLCache
import java.io.File
import java.util.Date
import java.util.UUID

class EditorURLCacheTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private lateinit var cacheRoot: File
    private lateinit var cache: EditorURLCache

    private val testURL = "https://example.com/api/posts"

    @Before
    fun setUp() {
        cacheRoot = tempFolder.newFolder("cache")
        cache = EditorURLCache(cacheRoot, EditorCachePolicy.Always)
    }

    private fun makeResponse(
        data: String = UUID.randomUUID().toString(),
        headers: EditorHTTPHeaders = EditorHTTPHeaders()
    ): EditorURLResponse {
        return EditorURLResponse(data = data, responseHeaders = headers)
    }

    // MARK: - store(_:for:httpMethod:) and getResponse(for:httpMethod:)

    @Test
    fun `store and retrieve response by URL`() {
        val response = makeResponse()
        cache.store(response, testURL, EditorHttpMethod.GET)
        val fetched = cache.getResponse(testURL, EditorHttpMethod.GET)
        assertEquals(response, fetched)
    }

    @Test
    fun `storing response overwrites the previous value`() {
        cache.store(makeResponse(), testURL, EditorHttpMethod.GET)
        val newResponse = makeResponse(data = "new value")
        cache.store(newResponse, testURL, EditorHttpMethod.GET)
        assertEquals(newResponse, cache.getResponse(testURL, EditorHttpMethod.GET))
    }

    @Test
    fun `storing response with empty data works`() {
        val response = makeResponse(data = "")
        cache.store(response, testURL, EditorHttpMethod.GET)
        val fetched = cache.getResponse(testURL, EditorHttpMethod.GET)
        assertEquals("", fetched?.data)
    }

    @Test
    fun `response for non-existent URL returns nil`() {
        val missingURL = "https://example.com/missing"
        assertNull(cache.getResponse(missingURL, EditorHttpMethod.GET))
    }

    @Test
    fun `different URLs are independent`() {
        val url1 = "https://example.com/posts/1"
        val url2 = "https://example.com/posts/2"
        val response1 = makeResponse(data = "post 1")
        val response2 = makeResponse(data = "post 2")
        cache.store(response1, url1, EditorHttpMethod.GET)
        cache.store(response2, url2, EditorHttpMethod.GET)

        val fetchedResponse1 = cache.getResponse(url1, EditorHttpMethod.GET)
        val fetchedResponse2 = cache.getResponse(url2, EditorHttpMethod.GET)

        assertEquals(response1, fetchedResponse1)
        assertEquals(response2, fetchedResponse2)
    }

    @Test
    fun `response includes headers`() {
        val headers = EditorHTTPHeaders(mapOf("Content-Type" to "application/json", "X-Custom" to "value"))
        val response = makeResponse(headers = headers)
        cache.store(response, testURL, EditorHttpMethod.GET)
        val retrieved = cache.getResponse(testURL, EditorHttpMethod.GET)
        assertEquals("application/json", retrieved?.responseHeaders?.get("Content-Type"))
        assertEquals("value", retrieved?.responseHeaders?.get("X-Custom"))
    }

    // MARK: - store(file:headers:url:httpMethod:)

    @Test
    fun `store file copies file data`() {
        val fileContent = TestResources.loadResource("post-test-case-1.json")
        val file = tempFolder.newFile("test.json")
        file.writeText(fileContent)

        val headers = EditorHTTPHeaders(mapOf("Content-Type" to "application/json"))
        cache.store(file, headers, testURL, EditorHttpMethod.GET)
        assertEquals(fileContent, cache.getResponse(testURL, EditorHttpMethod.GET)?.data)
    }

    @Test
    fun `store file preserves headers`() {
        val file = tempFolder.newFile("test.json")
        file.writeText("{}")

        val headers = EditorHTTPHeaders(mapOf("Content-Type" to "application/json", "X-Version" to "1.0"))
        cache.store(file, headers, testURL, EditorHttpMethod.GET)
        val retrieved = cache.getResponse(testURL, EditorHttpMethod.GET)
        assertEquals("application/json", retrieved?.responseHeaders?.get("Content-Type"))
        assertEquals("1.0", retrieved?.responseHeaders?.get("X-Version"))
    }

    @Test
    fun `store file twice overwrites prior value`() {
        val firstContent = TestResources.loadResource("post-test-case-1.json")
        val secondContent = TestResources.loadResource("post-test-case-163.json")

        val firstFile = tempFolder.newFile("first.json")
        firstFile.writeText(firstContent)

        val secondFile = tempFolder.newFile("second.json")
        secondFile.writeText(secondContent)

        val headers = EditorHTTPHeaders()
        cache.store(firstFile, headers, testURL, EditorHttpMethod.GET)
        cache.store(secondFile, headers, testURL, EditorHttpMethod.GET)
        assertEquals(secondContent, cache.getResponse(testURL, EditorHttpMethod.GET)?.data)
    }

    @Test
    fun `store file leaves original file`() {
        val file = tempFolder.newFile("test.json")
        file.writeText("{}")

        cache.store(file, EditorHTTPHeaders(), testURL, EditorHttpMethod.GET)
        assertTrue(file.exists())
    }

    @Test(expected = Exception::class)
    fun `store invalid file throws`() {
        val invalidPath = File("/nonexistent/path/file.txt")
        cache.store(invalidPath, EditorHTTPHeaders(), testURL, EditorHttpMethod.GET)
    }

    // MARK: - hasResponse(url:httpMethod:)

    @Test
    fun `hasResponse returns true for existing entry stored via response`() {
        cache.store(makeResponse(), testURL, EditorHttpMethod.GET)
        assertTrue(cache.hasResponse(testURL, EditorHttpMethod.GET))
    }

    @Test
    fun `hasResponse returns true for existing entry stored via file`() {
        val file = tempFolder.newFile("test.json")
        file.writeText("{}")

        cache.store(file, EditorHTTPHeaders(), testURL, EditorHttpMethod.GET)
        assertTrue(cache.hasResponse(testURL, EditorHttpMethod.GET))
    }

    @Test
    fun `hasResponse returns false for missing entry`() {
        val missingURL = "https://example.com/missing"
        assertFalse(cache.hasResponse(missingURL, EditorHttpMethod.GET))
    }

    // MARK: - clear()

    @Test
    fun `clear removes all entries`() {
        cache.store(makeResponse(), testURL, EditorHttpMethod.GET)
        val otherURL = "https://example.com/other"
        cache.store(makeResponse(), otherURL, EditorHttpMethod.GET)
        cache.clear()

        assertNull(cache.getResponse(testURL, EditorHttpMethod.GET))
        assertNull(cache.getResponse(otherURL, EditorHttpMethod.GET))
    }

    @Test
    fun `store succeeds after clear`() {
        cache.store(makeResponse(), testURL, EditorHttpMethod.GET)
        cache.clear()
        val newResponse = makeResponse(data = "after clear")
        cache.store(newResponse, testURL, EditorHttpMethod.GET)
        assertEquals(newResponse, cache.getResponse(testURL, EditorHttpMethod.GET))
    }

    // MARK: - URLs with query parameters

    @Test
    fun `URLs with different query parameters are independent`() {
        val url1 = "https://example.com/posts?page=1"
        val url2 = "https://example.com/posts?page=2"
        val response1 = makeResponse(data = "page 1")
        val response2 = makeResponse(data = "page 2")
        cache.store(response1, url1, EditorHttpMethod.GET)
        cache.store(response2, url2, EditorHttpMethod.GET)
        assertEquals(response1, cache.getResponse(url1, EditorHttpMethod.GET))
        assertEquals(response2, cache.getResponse(url2, EditorHttpMethod.GET))
    }

    @Test
    fun `URL with and without query parameters are independent`() {
        val urlWithQuery = "https://example.com/posts?context=edit"
        val urlWithoutQuery = "https://example.com/posts"
        val response1 = makeResponse(data = "with query")
        val response2 = makeResponse(data = "without query")
        cache.store(response1, urlWithQuery, EditorHttpMethod.GET)
        cache.store(response2, urlWithoutQuery, EditorHttpMethod.GET)
        assertEquals(response1, cache.getResponse(urlWithQuery, EditorHttpMethod.GET))
        assertEquals(response2, cache.getResponse(urlWithoutQuery, EditorHttpMethod.GET))
    }
}

// MARK: - Cache Policy Tests: Ignore

class EditorURLCacheIgnorePolicyTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private lateinit var cacheRoot: File
    private lateinit var cache: EditorURLCache

    private val testURL = "https://example.com/api/posts"

    /** A fixed reference date for deterministic testing. */
    private val referenceDate = Date(0)

    @Before
    fun setUp() {
        cacheRoot = tempFolder.newFolder("cache")
        cache = EditorURLCache(cacheRoot, EditorCachePolicy.Ignore)
    }

    private fun makeResponse(
        data: String = UUID.randomUUID().toString(),
        headers: EditorHTTPHeaders = EditorHTTPHeaders()
    ): EditorURLResponse {
        return EditorURLResponse(data = data, responseHeaders = headers)
    }

    @Test
    fun `ignore policy - response returns nil even after storing`() {
        val response = makeResponse()
        cache.store(response, testURL, EditorHttpMethod.GET, referenceDate)

        // With ignore policy, cached responses should never be returned
        assertNull(cache.getResponse(testURL, EditorHttpMethod.GET, referenceDate))
    }

    @Test
    fun `ignore policy - hasResponse returns false even after storing`() {
        cache.store(makeResponse(), testURL, EditorHttpMethod.GET, referenceDate)

        // With ignore policy, hasResponse should return false
        assertFalse(cache.hasResponse(testURL, EditorHttpMethod.GET, referenceDate))
    }

    @Test
    fun `ignore policy - multiple stores still return nil`() {
        val url1 = "https://example.com/posts/1"
        val url2 = "https://example.com/posts/2"

        cache.store(makeResponse(data = "post 1"), url1, EditorHttpMethod.GET, referenceDate)
        cache.store(makeResponse(data = "post 2"), url2, EditorHttpMethod.GET, referenceDate)

        assertNull(cache.getResponse(url1, EditorHttpMethod.GET, referenceDate))
        assertNull(cache.getResponse(url2, EditorHttpMethod.GET, referenceDate))
    }

    @Test
    fun `ignore policy - file store also returns nil`() {
        val file = tempFolder.newFile("test.json")
        file.writeText("{}")

        cache.store(file, EditorHTTPHeaders(), testURL, EditorHttpMethod.GET, referenceDate)

        assertNull(cache.getResponse(testURL, EditorHttpMethod.GET, referenceDate))
    }
}

// MARK: - Cache Policy Tests: MaxAge

class EditorURLCacheMaxAgePolicyTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private lateinit var cacheRoot: File

    private val testURL = "https://example.com/api/posts"

    /** A fixed reference date for deterministic testing. */
    private val referenceDate = Date(0)

    @Before
    fun setUp() {
        cacheRoot = tempFolder.newFolder("cache")
    }

    private fun makeResponse(
        data: String = UUID.randomUUID().toString(),
        headers: EditorHTTPHeaders = EditorHTTPHeaders()
    ): EditorURLResponse {
        return EditorURLResponse(data = data, responseHeaders = headers)
    }

    @Test
    fun `maxAge policy - fresh response is returned`() {
        val cache = EditorURLCache(cacheRoot, EditorCachePolicy.MaxAge(60_000))
        val response = makeResponse()

        // Store at reference date
        cache.store(response, testURL, EditorHttpMethod.GET, referenceDate)

        // Retrieve at the same time - should be fresh
        assertEquals(response, cache.getResponse(testURL, EditorHttpMethod.GET, referenceDate))
    }

    @Test
    fun `maxAge policy - response within interval is returned`() {
        val cache = EditorURLCache(cacheRoot, EditorCachePolicy.MaxAge(60_000))
        val response = makeResponse()

        // Store at reference date
        cache.store(response, testURL, EditorHttpMethod.GET, referenceDate)

        // Retrieve 30 seconds later - should still be fresh
        val thirtySecondsLater = Date(referenceDate.time + 30_000)
        assertEquals(response, cache.getResponse(testURL, EditorHttpMethod.GET, thirtySecondsLater))
    }

    @Test
    fun `maxAge policy - hasResponse returns true for fresh response`() {
        val cache = EditorURLCache(cacheRoot, EditorCachePolicy.MaxAge(60_000))

        cache.store(makeResponse(), testURL, EditorHttpMethod.GET, referenceDate)

        assertTrue(cache.hasResponse(testURL, EditorHttpMethod.GET, referenceDate))
    }

    @Test
    fun `maxAge policy - expired response returns nil`() {
        val cache = EditorURLCache(cacheRoot, EditorCachePolicy.MaxAge(60_000))
        val response = makeResponse()

        // Store at reference date
        cache.store(response, testURL, EditorHttpMethod.GET, referenceDate)

        // Retrieve 2 minutes later - should be expired
        val twoMinutesLater = Date(referenceDate.time + 120_000)
        assertNull(cache.getResponse(testURL, EditorHttpMethod.GET, twoMinutesLater))
    }

    @Test
    fun `maxAge policy - hasResponse returns false for expired response`() {
        val cache = EditorURLCache(cacheRoot, EditorCachePolicy.MaxAge(60_000))

        cache.store(makeResponse(), testURL, EditorHttpMethod.GET, referenceDate)

        val twoMinutesLater = Date(referenceDate.time + 120_000)
        assertFalse(cache.hasResponse(testURL, EditorHttpMethod.GET, twoMinutesLater))
    }

    @Test
    fun `maxAge policy - response at exact boundary is expired`() {
        val cache = EditorURLCache(cacheRoot, EditorCachePolicy.MaxAge(60_000))

        cache.store(makeResponse(), testURL, EditorHttpMethod.GET, referenceDate)

        // At exactly 60 seconds, the response expires (using > comparison)
        val exactlySixtySecondsLater = Date(referenceDate.time + 60_000)
        assertNull(cache.getResponse(testURL, EditorHttpMethod.GET, exactlySixtySecondsLater))
    }

    @Test
    fun `maxAge policy - response just before boundary is fresh`() {
        val cache = EditorURLCache(cacheRoot, EditorCachePolicy.MaxAge(60_000))
        val response = makeResponse()

        cache.store(response, testURL, EditorHttpMethod.GET, referenceDate)

        // At 59 seconds, the response is still fresh
        val fiftyNineSecondsLater = Date(referenceDate.time + 59_000)
        assertEquals(response, cache.getResponse(testURL, EditorHttpMethod.GET, fiftyNineSecondsLater))
    }

    @Test
    fun `maxAge policy - zero interval means immediate expiration`() {
        val cache = EditorURLCache(cacheRoot, EditorCachePolicy.MaxAge(0))

        cache.store(makeResponse(), testURL, EditorHttpMethod.GET, referenceDate)

        // Even at the same moment, the response should be expired
        assertNull(cache.getResponse(testURL, EditorHttpMethod.GET, referenceDate))
    }

    @Test
    fun `maxAge policy - re-storing refreshes the expiration`() {
        val cache = EditorURLCache(cacheRoot, EditorCachePolicy.MaxAge(60_000))

        // Store initial response at reference date
        cache.store(makeResponse(data = "first"), testURL, EditorHttpMethod.GET, referenceDate)

        // 50 seconds later, re-store with new data
        val fiftySecondsLater = Date(referenceDate.time + 50_000)
        val newResponse = makeResponse(data = "second")
        cache.store(newResponse, testURL, EditorHttpMethod.GET, fiftySecondsLater)

        // 80 seconds from original store - original would have expired, but re-store refreshed it
        val eightySecondsLater = Date(referenceDate.time + 80_000)
        assertEquals(newResponse, cache.getResponse(testURL, EditorHttpMethod.GET, eightySecondsLater))
    }

    @Test
    fun `maxAge policy - different URLs expire independently`() {
        val cache = EditorURLCache(cacheRoot, EditorCachePolicy.MaxAge(60_000))

        val url1 = "https://example.com/posts/1"
        val url2 = "https://example.com/posts/2"

        // Store first URL at reference date
        cache.store(makeResponse(data = "post 1"), url1, EditorHttpMethod.GET, referenceDate)

        // Store second URL 30 seconds later
        val thirtySecondsLater = Date(referenceDate.time + 30_000)
        val response2 = makeResponse(data = "post 2")
        cache.store(response2, url2, EditorHttpMethod.GET, thirtySecondsLater)

        // At 70 seconds from start: url1 should be expired, url2 should still be fresh
        val seventySecondsLater = Date(referenceDate.time + 70_000)

        // First URL expired (stored at 0, maxAge 60, current time 70)
        assertNull(cache.getResponse(url1, EditorHttpMethod.GET, seventySecondsLater))

        // Second URL still fresh (stored at 30, maxAge 60, expires at 90, current time 70)
        assertEquals(response2, cache.getResponse(url2, EditorHttpMethod.GET, seventySecondsLater))
    }

    @Test
    fun `maxAge policy - file store respects cache policy`() {
        val cache = EditorURLCache(cacheRoot, EditorCachePolicy.MaxAge(60_000))
        val fileContent = TestResources.loadResource("post-test-case-1.json")
        val file = tempFolder.newFile("test.json")
        file.writeText(fileContent)

        cache.store(file, EditorHTTPHeaders(), testURL, EditorHttpMethod.GET, referenceDate)

        // Fresh: should return data
        assertEquals(fileContent, cache.getResponse(testURL, EditorHttpMethod.GET, referenceDate)?.data)

        // Expired: should return nil
        val twoMinutesLater = Date(referenceDate.time + 120_000)
        assertNull(cache.getResponse(testURL, EditorHttpMethod.GET, twoMinutesLater))
    }
}

// MARK: - Cache Policy Tests: Always

class EditorURLCacheAlwaysPolicyTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private lateinit var cacheRoot: File
    private lateinit var cache: EditorURLCache

    private val testURL = "https://example.com/api/posts"

    /** A fixed reference date for deterministic testing. */
    private val referenceDate = Date(0)

    @Before
    fun setUp() {
        cacheRoot = tempFolder.newFolder("cache")
        cache = EditorURLCache(cacheRoot, EditorCachePolicy.Always)
    }

    private fun makeResponse(
        data: String = UUID.randomUUID().toString(),
        headers: EditorHTTPHeaders = EditorHTTPHeaders()
    ): EditorURLResponse {
        return EditorURLResponse(data = data, responseHeaders = headers)
    }

    @Test
    fun `always policy - response is returned at same time`() {
        val response = makeResponse()
        cache.store(response, testURL, EditorHttpMethod.GET, referenceDate)

        assertEquals(response, cache.getResponse(testURL, EditorHttpMethod.GET, referenceDate))
    }

    @Test
    fun `always policy - response is returned regardless of time elapsed`() {
        val response = makeResponse()
        cache.store(response, testURL, EditorHttpMethod.GET, referenceDate)

        // Even years later, response should still be available
        val tenYearsLater = Date(referenceDate.time + (10L * 365 * 24 * 60 * 60 * 1000))
        assertEquals(response, cache.getResponse(testURL, EditorHttpMethod.GET, tenYearsLater))
    }

    @Test
    fun `always policy - hasResponse returns true regardless of time`() {
        cache.store(makeResponse(), testURL, EditorHttpMethod.GET, referenceDate)

        assertTrue(cache.hasResponse(testURL, EditorHttpMethod.GET, referenceDate))

        val tenYearsLater = Date(referenceDate.time + (10L * 365 * 24 * 60 * 60 * 1000))
        assertTrue(cache.hasResponse(testURL, EditorHttpMethod.GET, tenYearsLater))
    }
}
