import CryptoKit
import Foundation
import OSLog

/// A URL-based cache for storing HTTP responses keyed by URL and HTTP method.
///
/// Responses are stored on disk and survive process termination. Responses are keyed by both URL and HTTP method, so GET and OPTIONS requests to the
/// same URL are stored independently.
public struct EditorURLCache: Sendable {
    private let cache: URLCache
    private let cachePolicy: EditorCachePolicy
    private let performanceMonitor = SignpostMonitor(for: Logger.performance)

    /// Creates a new URL cache.
    ///
    /// - Parameters:
    ///   - cacheRoot: The directory where cached responses will be stored.
    ///     If `nil`, the system default cache directory is used. The cache has a
    ///     maximum disk capacity of 100 MB.
    ///   - cachePolicy: The policy that determines when cached responses are considered valid.
    ///     Use `.ignore` to always fetch fresh data, `.maxAge(_:)` to expire entries after
    ///     a time interval, or `.always` (the default) to use cached data regardless of age.
    public init(cacheRoot: URL? = nil, cachePolicy: EditorCachePolicy = .always) {
        // About enough for 10 sites
        self.cache = URLCache(memoryCapacity: 0, diskCapacity: 100 * 1024 * 1024, directory: cacheRoot)
        self.cachePolicy = cachePolicy
    }

    /// Stores a response for the given URL and HTTP method.
    ///
    /// If a response already exists for this URL and method combination, it will be overwritten.
    ///
    /// - Parameters:
    ///   - response: The response to store.
    ///   - url: The URL to associate with the response.
    ///   - httpMethod: The HTTP method to associate with the response.
    /// - Throws: An error if the response cannot be stored.
    public func store(_ response: EditorURLResponse, for url: URL, httpMethod: EditorHttpMethod) throws {
        try self.store(response, for: url, httpMethod: httpMethod, currentDate: .now)
    }

    internal func store(
        _ response: EditorURLResponse,
        for url: URL,
        httpMethod: EditorHttpMethod,
        currentDate: Date
    ) throws {
        let response = CachedURLResponse(
            response: HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: response.responseHeaders.dictionaryValue
            )!,
            data: __fixEmptyDataBugEncode(response.data),
            userInfo: [
                "storageDate": currentDate
            ],
            storagePolicy: .allowed
        )

        self.cache.storeCachedResponse(response, for: URLRequest(method: httpMethod, url: url))
        Thread.sleep(forTimeInterval: 0.05)  // Hack to make `URLCache` work
    }

    /// Stores the contents of a downloaded file as a cached response for the given URL and HTTP method.
    ///
    /// If a response already exists for this URL and method combination, it will be overwritten.
    ///
    /// - Parameters:
    ///   - path: The file URL whose contents should be stored.
    ///   - headers: The HTTP headers to associate with the response.
    ///   - url: The URL to associate with the response.
    ///   - httpMethod: The HTTP method to associate with the response.
    /// - Throws: An error if the file cannot be read or the response cannot be stored.
    public func store(
        fileAt path: URL,
        headers: EditorHTTPHeaders,
        for url: URL,
        httpMethod: EditorHttpMethod
    ) throws {
        try self.store(fileAt: path, headers: headers, for: url, httpMethod: httpMethod, currentDate: .now)
    }

    internal func store(
        fileAt path: URL,
        headers: EditorHTTPHeaders,
        for url: URL,
        httpMethod: EditorHttpMethod,
        currentDate: Date
    ) throws {

        let response = CachedURLResponse(
            response: HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: headers.dictionaryValue
            )!,
            data: __fixEmptyDataBugEncode(try Data(contentsOf: path)),
            userInfo: [
                "storageDate": currentDate
            ],
            storagePolicy: .allowed
        )

        self.cache.storeCachedResponse(response, for: URLRequest(method: httpMethod, url: url))
        Thread.sleep(forTimeInterval: 0.05)  // Hack to make `URLCache` work
    }

    /// Checks whether a cached response exists for the given URL and HTTP method.
    ///
    /// - Parameters:
    ///   - url: The URL to check.
    ///   - httpMethod: The HTTP method to check.
    /// - Returns: `true` if a cached response exists, `false` otherwise.
    /// - Throws: An error if the check cannot be performed.
    public func hasData(for url: URL, httpMethod: EditorHttpMethod) throws -> Bool {
        try self.response(for: url, httpMethod: httpMethod, currentDate: .now) != nil
    }

    internal func hasData(for url: URL, httpMethod: EditorHttpMethod, currentDate: Date) throws -> Bool {
        try self.response(for: url, httpMethod: httpMethod, currentDate: currentDate) != nil
    }

    /// Retrieves the cached response for the given URL and HTTP method.
    ///
    /// - Parameters:
    ///   - url: The URL to look up.
    ///   - httpMethod: The HTTP method to look up.
    /// - Returns: The cached response, or `nil` if no response is cached.
    /// - Throws: An error if the response cannot be retrieved.
    public func response(for url: URL, httpMethod: EditorHttpMethod) throws -> EditorURLResponse? {
        try self.response(for: url, httpMethod: httpMethod, currentDate: .now)
    }

    internal func response(
        for url: URL,
        httpMethod: EditorHttpMethod,
        currentDate: Date
    ) throws -> EditorURLResponse? {
        performanceMonitor.measure { () -> EditorURLResponse? in
            guard
                let response = self.cache.cachedResponse(for: URLRequest(method: httpMethod, url: url)),
                let storageDate = response.userInfo?["storageDate"] as? Date,
                self.cachePolicy.allowsResponseWith(date: storageDate, currentDate: currentDate)
            else {
                return nil
            }

            let headers = EditorHTTPHeaders((response.response as! HTTPURLResponse).allHeaderFields)
            return EditorURLResponse(
                data: __fixEmptyDataBugDecode(response.data),
                responseHeaders: headers
            )
        }
    }

    /// Removes all cached responses.
    ///
    /// - Throws: An error if the cache cannot be cleared.
    public func clear() throws {
        self.cache.removeAllCachedResponses()
        Thread.sleep(forTimeInterval: 0.05)  // Hack to make `URLCache` work
    }

    /// Encodes data to work around a `URLCache` bug with empty data.
    ///
    /// `URLCache` doesn't properly store an empty `Data` object, so we use a sentinel
    /// value to represent empty data.
    ///
    /// - Parameter data: The data to encode.
    /// - Returns: The encoded data, or a sentinel value if the data is empty.
    private func __fixEmptyDataBugEncode(_ data: Data) -> Data {
        guard data.isEmpty else { return data }
        return Data("__is_empty__".utf8)
    }

    /// Decodes data that was encoded with `__fixEmptyDataBugEncode`.
    ///
    /// - Parameter data: The data to decode.
    /// - Returns: The original data, or empty data if the sentinel value was detected.
    private func __fixEmptyDataBugDecode(_ data: Data) -> Data {
        guard data.count == 12, data == Data("__is_empty__".utf8) else { return data }
        return Data()
    }
}
