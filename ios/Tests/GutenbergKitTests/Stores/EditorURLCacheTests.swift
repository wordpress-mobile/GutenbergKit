import Foundation
import Testing

@testable import GutenbergKit

@Suite
struct EditorURLCacheTests {
    private let testURL = URL(string: "https://example.com/api/posts")!

    let cache = EditorURLCache(cacheRoot: .randomTemporaryDirectory, cachePolicy: .always)

    private func makeResponse(data: Data = .sample, headers: EditorHTTPHeaders = [:])
    -> EditorURLResponse {
        EditorURLResponse(data: data, responseHeaders: headers)
    }

    // MARK: - store(_:for:httpMethod:) and response(for:httpMethod:)

    @Test("store and retrieve response by URL")
    func storeAndRetrieve() throws {
        let response = makeResponse()
        try cache.store(response, for: testURL, httpMethod: .GET)
        let fetched = try cache.response(for: testURL, httpMethod: .GET)
        #expect(fetched == response)
    }

    @Test("storing response overwrites the previous value")
    func storeOverwrites() throws {
        try cache.store(makeResponse(), for: testURL, httpMethod: .GET)
        let newResponse = makeResponse(data: Data("new value"))
        try cache.store(newResponse, for: testURL, httpMethod: .GET)
        #expect(try cache.response(for: testURL, httpMethod: .GET) == newResponse)
    }

    @Test("storing response with empty data works")
    func storeEmptyData() throws {
        let response = makeResponse(data: Data())
        try cache.store(response, for: testURL, httpMethod: .GET)
        let fetched = try cache.response(for: testURL, httpMethod: .GET)
        #expect(fetched?.data == Data())
    }

    @Test("response for non-existent URL returns nil")
    func nonExistentUrl() throws {
        let missingURL = URL(string: "https://example.com/missing")!
        #expect(try cache.response(for: missingURL, httpMethod: .GET) == nil)
    }

    @Test("different URLs are independent")
    func urlsAreIndependent() throws {
        let url1 = URL(string: "https://example.com/posts/1")!
        let url2 = URL(string: "https://example.com/posts/2")!
        let response1 = makeResponse(data: Data("post 1"))
        let response2 = makeResponse(data: Data("post 2"))
        try cache.store(response1, for: url1, httpMethod: .GET)
        try cache.store(response2, for: url2, httpMethod: .GET)

        let fetchedResponse1 = try cache.response(for: url1, httpMethod: .GET)
        let fetchedResponse2 = try cache.response(for: url2, httpMethod: .GET)

        #expect(fetchedResponse1 == response1)
        #expect(fetchedResponse2 == response2)
    }

    @Test("response includes headers")
    func responseIncludesHeaders() throws {
        let headers: EditorHTTPHeaders = ["Content-Type": "application/json", "X-Custom": "value"]
        let response = makeResponse(headers: headers)
        try cache.store(response, for: testURL, httpMethod: .GET)
        let retrieved = try cache.response(for: testURL, httpMethod: .GET)
        #expect(retrieved?.responseHeaders["Content-Type"] == "application/json")
        #expect(retrieved?.responseHeaders["X-Custom"] == "value")
    }

    // MARK: - store(fileAt:headers:for:httpMethod:)

    @Test("store fileAt URL copies file data")
    func storeFileReadsData() throws {
        let filePath = Bundle.module.url(forResource: "post-test-case-1", withExtension: "json")!
        let headers: EditorHTTPHeaders = ["Content-Type": "application/json"]
        try cache.store(fileAt: filePath, headers: headers, for: testURL, httpMethod: .GET)
        let expectedData = try Data(contentsOf: filePath)
        #expect(try cache.response(for: testURL, httpMethod: .GET)?.data == expectedData)
    }

    @Test("store fileAt URL preserves headers")
    func storeFilePreservesHeaders() throws {
        let filePath = Bundle.module.url(forResource: "post-test-case-1", withExtension: "json")!
        let headers: EditorHTTPHeaders = ["Content-Type": "application/json", "X-Version": "1.0"]
        try cache.store(fileAt: filePath, headers: headers, for: testURL, httpMethod: .GET)
        let retrieved = try cache.response(for: testURL, httpMethod: .GET)
        #expect(retrieved?.responseHeaders["Content-Type"] == "application/json")
        #expect(retrieved?.responseHeaders["X-Version"] == "1.0")
    }

    @Test("store fileAt URL twice overwrites prior value")
    func storeFileTwiceOverwrites() throws {
        let firstFile = Bundle.module.url(forResource: "post-test-case-1", withExtension: "json")!
        let secondFile = Bundle.module.url(forResource: "post-test-case-163", withExtension: "json")!
        let headers: EditorHTTPHeaders = [:]
        try cache.store(fileAt: firstFile, headers: headers, for: testURL, httpMethod: .GET)
        try cache.store(fileAt: secondFile, headers: headers, for: testURL, httpMethod: .GET)
        let expectedData = try Data(contentsOf: secondFile)
        #expect(try cache.response(for: testURL, httpMethod: .GET)?.data == expectedData)
    }

    @Test("store fileAt URL leaves original file")
    func storeFileKeepsOriginal() throws {
        let filePath = Bundle.module.url(forResource: "post-test-case-1", withExtension: "json")!
        try cache.store(fileAt: filePath, headers: [:], for: testURL, httpMethod: .GET)
        #expect(FileManager.default.fileExists(at: filePath))
    }

    @Test("store fileAt invalid URL throws")
    func storeInvalidFileThrows() throws {
        let invalidPath = URL(fileURLWithPath: "/nonexistent/path/file.txt")
        #expect(throws: Error.self) {
            try cache.store(fileAt: invalidPath, headers: [:], for: testURL, httpMethod: .GET)
        }
    }

    // MARK: - hasData(for:httpMethod:)

    @Test("hasData returns true for existing entry stored via response")
    func hasDataWorksForResponseStore() throws {
        try cache.store(makeResponse(), for: testURL, httpMethod: .GET)
        #expect(try cache.hasData(for: testURL, httpMethod: .GET) == true)
    }

    @Test("hasData returns true for existing entry stored via file")
    func hasDataWorksForFileStore() throws {
        let filePath = Bundle.module.url(forResource: "post-test-case-1", withExtension: "json")!
        try cache.store(fileAt: filePath, headers: [:], for: testURL, httpMethod: .GET)
        #expect(try cache.hasData(for: testURL, httpMethod: .GET) == true)
    }

    @Test("hasData returns false for missing entry")
    func hasDataWorksForFalse() throws {
        let missingURL = URL(string: "https://example.com/missing")!
        #expect(try cache.hasData(for: missingURL, httpMethod: .GET) == false)
    }

    // MARK: - clear()

    @Test("clear removes all entries")
    func clearRemovesAll() throws {
        try cache.store(makeResponse(), for: testURL, httpMethod: .GET)
        let otherURL = URL(string: "https://example.com/other")!
        try cache.store(makeResponse(), for: otherURL, httpMethod: .GET)
        try cache.clear()

        #expect(try cache.response(for: testURL, httpMethod: .GET) == nil)
        #expect(try cache.response(for: otherURL, httpMethod: .GET) == nil)
    }

    @Test("store succeeds after clear")
    func storeAfterClear() throws {
        try cache.store(makeResponse(), for: testURL, httpMethod: .GET)
        try cache.clear()

        let newResponse = makeResponse(data: Data("after clear"))
        try cache.store(newResponse, for: testURL, httpMethod: .GET)
        #expect(try cache.response(for: testURL, httpMethod: .GET) == newResponse)
    }

    // MARK: - URLs with query parameters

    @Test("URLs with different query parameters are independent")
    func queryParametersAreIndependent() throws {
        let url1 = URL(string: "https://example.com/posts?page=1")!
        let url2 = URL(string: "https://example.com/posts?page=2")!
        let response1 = makeResponse(data: Data("page 1"))
        let response2 = makeResponse(data: Data("page 2"))
        try cache.store(response1, for: url1, httpMethod: .GET)
        try cache.store(response2, for: url2, httpMethod: .GET)
        #expect(try cache.response(for: url1, httpMethod: .GET) == response1)
        #expect(try cache.response(for: url2, httpMethod: .GET) == response2)
    }

    @Test("URL with and without query parameters are independent")
    func urlWithAndWithoutQueryAreIndependent() throws {
        let urlWithQuery = URL(string: "https://example.com/posts?context=edit")!
        let urlWithoutQuery = URL(string: "https://example.com/posts")!
        let response1 = makeResponse(data: Data("with query"))
        let response2 = makeResponse(data: Data("without query"))
        try cache.store(response1, for: urlWithQuery, httpMethod: .GET)
        try cache.store(response2, for: urlWithoutQuery, httpMethod: .GET)
        #expect(try cache.response(for: urlWithQuery, httpMethod: .GET) == response1)
        #expect(try cache.response(for: urlWithoutQuery, httpMethod: .GET) == response2)
    }
}

// MARK: - Cache Policy Tests

@Suite("EditorURLCache with ignore policy")
struct EditorURLCacheIgnorePolicyTests {
    private let testURL = URL(string: "https://example.com/api/posts")!

    /// A fixed reference date for deterministic testing.
    private let referenceDate = Date(timeIntervalSinceReferenceDate: 0)

    /// A cache configured with the `.ignore` policy, which should never return cached responses.
    let cache = EditorURLCache(cacheRoot: .randomTemporaryDirectory, cachePolicy: .ignore)

    private func makeResponse(data: Data = .sample, headers: EditorHTTPHeaders = [:]) -> EditorURLResponse {
        EditorURLResponse(data: data, responseHeaders: headers)
    }

    @Test("ignore policy: response returns nil even after storing")
    func ignorePolicy_responseReturnsNilAfterStore() throws {
        let response = makeResponse()
        try cache.store(response, for: testURL, httpMethod: .GET, currentDate: self.referenceDate)

        // With ignore policy, cached responses should never be returned
        #expect(try cache.response(for: testURL, httpMethod: .GET, currentDate: self.referenceDate) == nil)
    }

    @Test("ignore policy: hasData returns false even after storing")
    func ignorePolicy_hasDataReturnsFalseAfterStore() throws {
        try cache.store(makeResponse(), for: testURL, httpMethod: .GET, currentDate: self.referenceDate)

        // With ignore policy, hasData should return false
        #expect(try cache.hasData(for: testURL, httpMethod: .GET, currentDate: self.referenceDate) == false)
    }

    @Test("ignore policy: multiple stores still return nil")
    func ignorePolicy_multipleStoresReturnNil() throws {
        let url1 = URL(string: "https://example.com/posts/1")!
        let url2 = URL(string: "https://example.com/posts/2")!

        try cache.store(makeResponse(data: Data("post 1")), for: url1, httpMethod: .GET, currentDate: self.referenceDate)
        try cache.store(makeResponse(data: Data("post 2")), for: url2, httpMethod: .GET, currentDate: self.referenceDate)

        #expect(try cache.response(for: url1, httpMethod: .GET, currentDate: self.referenceDate) == nil)
        #expect(try cache.response(for: url2, httpMethod: .GET, currentDate: self.referenceDate) == nil)
    }

    @Test("ignore policy: file store also returns nil")
    func ignorePolicy_fileStoreReturnsNil() throws {
        let filePath = Bundle.module.url(forResource: "post-test-case-1", withExtension: "json")!
        try cache.store(fileAt: filePath, headers: [:], for: testURL, httpMethod: .GET, currentDate: self.referenceDate)

        #expect(try cache.response(for: testURL, httpMethod: .GET, currentDate: self.referenceDate) == nil)
    }
}

@Suite("EditorURLCache with maxAge policy")
struct EditorURLCacheMaxAgePolicyTests {
    private let testURL = URL(string: "https://example.com/api/posts")!

    /// A fixed reference date for deterministic testing.
    private let referenceDate = Date(timeIntervalSinceReferenceDate: 0)

    private func makeResponse(data: Data = .sample, headers: EditorHTTPHeaders = [:]) -> EditorURLResponse {
        EditorURLResponse(data: data, responseHeaders: headers)
    }

    @Test("maxAge policy: fresh response is returned")
    func maxAgePolicy_freshResponseReturned() throws {
        let cache = EditorURLCache(cacheRoot: .randomTemporaryDirectory, cachePolicy: .maxAge(60))
        let response = makeResponse()

        // Store at reference date
        try cache.store(response, for: testURL, httpMethod: .GET, currentDate: self.referenceDate)

        // Retrieve at the same time - should be fresh
        #expect(try cache.response(for: testURL, httpMethod: .GET, currentDate: self.referenceDate) == response)
    }

    @Test("maxAge policy: response within interval is returned")
    func maxAgePolicy_responseWithinIntervalReturned() throws {
        let cache = EditorURLCache(cacheRoot: .randomTemporaryDirectory, cachePolicy: .maxAge(60))
        let response = makeResponse()

        // Store at reference date
        try cache.store(response, for: testURL, httpMethod: .GET, currentDate: self.referenceDate)

        // Retrieve 30 seconds later - should still be fresh
        let thirtySecondsLater = self.referenceDate.addingTimeInterval(30)
        #expect(try cache.response(for: testURL, httpMethod: .GET, currentDate: thirtySecondsLater) == response)
    }

    @Test("maxAge policy: hasData returns true for fresh response")
    func maxAgePolicy_hasDataTrueForFresh() throws {
        let cache = EditorURLCache(cacheRoot: .randomTemporaryDirectory, cachePolicy: .maxAge(60))

        try cache.store(makeResponse(), for: testURL, httpMethod: .GET, currentDate: self.referenceDate)

        #expect(try cache.hasData(for: testURL, httpMethod: .GET, currentDate: self.referenceDate) == true)
    }

    @Test("maxAge policy: expired response returns nil")
    func maxAgePolicy_expiredResponseReturnsNil() throws {
        let cache = EditorURLCache(cacheRoot: .randomTemporaryDirectory, cachePolicy: .maxAge(60))
        let response = makeResponse()

        // Store at reference date
        try cache.store(response, for: testURL, httpMethod: .GET, currentDate: self.referenceDate)

        // Retrieve 2 minutes later - should be expired
        let twoMinutesLater = self.referenceDate.addingTimeInterval(120)
        #expect(try cache.response(for: testURL, httpMethod: .GET, currentDate: twoMinutesLater) == nil)
    }

    @Test("maxAge policy: hasData returns false for expired response")
    func maxAgePolicy_hasDataFalseForExpired() throws {
        let cache = EditorURLCache(cacheRoot: .randomTemporaryDirectory, cachePolicy: .maxAge(60))

        try cache.store(makeResponse(), for: testURL, httpMethod: .GET, currentDate: self.referenceDate)

        let twoMinutesLater = self.referenceDate.addingTimeInterval(120)
        #expect(try cache.hasData(for: testURL, httpMethod: .GET, currentDate: twoMinutesLater) == false)
    }

    @Test("maxAge policy: response at exact boundary is expired")
    func maxAgePolicy_responseAtExactBoundaryIsExpired() throws {
        let cache = EditorURLCache(cacheRoot: .randomTemporaryDirectory, cachePolicy: .maxAge(60))

        try cache.store(makeResponse(), for: testURL, httpMethod: .GET, currentDate: self.referenceDate)

        // At exactly 60 seconds, the response expires (using > comparison)
        let exactlySixtySecondsLater = self.referenceDate.addingTimeInterval(60)
        #expect(try cache.response(for: testURL, httpMethod: .GET, currentDate: exactlySixtySecondsLater) == nil)
    }

    @Test("maxAge policy: response just before boundary is fresh")
    func maxAgePolicy_responseJustBeforeBoundaryIsFresh() throws {
        let cache = EditorURLCache(cacheRoot: .randomTemporaryDirectory, cachePolicy: .maxAge(60))
        let response = makeResponse()

        try cache.store(response, for: testURL, httpMethod: .GET, currentDate: self.referenceDate)

        // At 59 seconds, the response is still fresh
        let fiftyNineSecondsLater = self.referenceDate.addingTimeInterval(59)
        #expect(try cache.response(for: testURL, httpMethod: .GET, currentDate: fiftyNineSecondsLater) == response)
    }

    @Test("maxAge policy: zero interval means immediate expiration")
    func maxAgePolicy_zeroIntervalExpiresImmediately() throws {
        let cache = EditorURLCache(cacheRoot: .randomTemporaryDirectory, cachePolicy: .maxAge(0))

        try cache.store(makeResponse(), for: testURL, httpMethod: .GET, currentDate: self.referenceDate)

        // Even at the same moment, the response should be expired (since maxAge(0) means date + 0 == currentDate, not >)
        #expect(try cache.response(for: testURL, httpMethod: .GET, currentDate: self.referenceDate) == nil)
    }

    @Test("maxAge policy: re-storing refreshes the expiration")
    func maxAgePolicy_restoreRefreshesExpiration() throws {
        let cache = EditorURLCache(cacheRoot: .randomTemporaryDirectory, cachePolicy: .maxAge(60))

        // Store initial response at reference date
        try cache.store(makeResponse(data: Data("first")), for: testURL, httpMethod: .GET, currentDate: self.referenceDate)

        // 50 seconds later, re-store with new data
        let fiftySecondsLater = self.referenceDate.addingTimeInterval(50)
        let newResponse = makeResponse(data: Data("second"))
        try cache.store(newResponse, for: testURL, httpMethod: .GET, currentDate: fiftySecondsLater)

        // 80 seconds from original store - original would have expired, but re-store refreshed it
        let eightySecondsLater = self.referenceDate.addingTimeInterval(80)
        #expect(try cache.response(for: testURL, httpMethod: .GET, currentDate: eightySecondsLater) == newResponse)
    }

    @Test("maxAge policy: different URLs expire independently")
    func maxAgePolicy_urlsExpireIndependently() throws {
        let cache = EditorURLCache(cacheRoot: .randomTemporaryDirectory, cachePolicy: .maxAge(60))

        let url1 = URL(string: "https://example.com/posts/1")!
        let url2 = URL(string: "https://example.com/posts/2")!

        // Store first URL at reference date
        try cache.store(makeResponse(data: Data("post 1")), for: url1, httpMethod: .GET, currentDate: self.referenceDate)

        // Store second URL 30 seconds later
        let thirtySecondsLater = self.referenceDate.addingTimeInterval(30)
        let response2 = makeResponse(data: Data("post 2"))
        try cache.store(response2, for: url2, httpMethod: .GET, currentDate: thirtySecondsLater)

        // At 70 seconds from start: url1 should be expired, url2 should still be fresh
        let seventySecondsLater = self.referenceDate.addingTimeInterval(70)

        // First URL expired (stored at 0, maxAge 60, current time 70)
        #expect(try cache.response(for: url1, httpMethod: .GET, currentDate: seventySecondsLater) == nil)

        // Second URL still fresh (stored at 30, maxAge 60, expires at 90, current time 70)
        #expect(try cache.response(for: url2, httpMethod: .GET, currentDate: seventySecondsLater) == response2)
    }

    @Test("maxAge policy: file store respects cache policy")
    func maxAgePolicy_fileStoreRespectsCachePolicy() throws {
        let cache = EditorURLCache(cacheRoot: .randomTemporaryDirectory, cachePolicy: .maxAge(60))
        let filePath = Bundle.module.url(forResource: "post-test-case-1", withExtension: "json")!
        let expectedData = try Data(contentsOf: filePath)

        try cache.store(fileAt: filePath, headers: [:], for: testURL, httpMethod: .GET, currentDate: self.referenceDate)

        // Fresh: should return data
        #expect(try cache.response(for: testURL, httpMethod: .GET, currentDate: self.referenceDate)?.data == expectedData)

        // Expired: should return nil
        let twoMinutesLater = self.referenceDate.addingTimeInterval(120)
        #expect(try cache.response(for: testURL, httpMethod: .GET, currentDate: twoMinutesLater) == nil)
    }
}

@Suite("EditorURLCache with always policy")
struct EditorURLCacheAlwaysPolicyTests {
    private let testURL = URL(string: "https://example.com/api/posts")!

    /// A fixed reference date for deterministic testing.
    private let referenceDate = Date(timeIntervalSinceReferenceDate: 0)

    let cache = EditorURLCache(cacheRoot: .randomTemporaryDirectory, cachePolicy: .always)

    private func makeResponse(data: Data = .sample, headers: EditorHTTPHeaders = [:]) -> EditorURLResponse {
        EditorURLResponse(data: data, responseHeaders: headers)
    }

    @Test("always policy: response is returned at same time")
    func alwaysPolicy_responseReturnedAtSameTime() throws {
        let response = makeResponse()
        try cache.store(response, for: testURL, httpMethod: .GET, currentDate: self.referenceDate)

        #expect(try cache.response(for: testURL, httpMethod: .GET, currentDate: self.referenceDate) == response)
    }

    @Test("always policy: response is returned regardless of time elapsed")
    func alwaysPolicy_responseReturnedRegardlessOfTime() throws {
        let response = makeResponse()
        try cache.store(response, for: testURL, httpMethod: .GET, currentDate: self.referenceDate)

        // Even years later, response should still be available
        let tenYearsLater = self.referenceDate.addingTimeInterval(10 * 365 * 24 * 60 * 60)
        #expect(try cache.response(for: testURL, httpMethod: .GET, currentDate: tenYearsLater) == response)
    }

    @Test("always policy: hasData returns true regardless of time")
    func alwaysPolicy_hasDataReturnsTrueRegardlessOfTime() throws {
        try cache.store(makeResponse(), for: testURL, httpMethod: .GET, currentDate: self.referenceDate)

        #expect(try cache.hasData(for: testURL, httpMethod: .GET, currentDate: self.referenceDate) == true)

        let tenYearsLater = self.referenceDate.addingTimeInterval(10 * 365 * 24 * 60 * 60)
        #expect(try cache.hasData(for: testURL, httpMethod: .GET, currentDate: tenYearsLater) == true)
    }
}
