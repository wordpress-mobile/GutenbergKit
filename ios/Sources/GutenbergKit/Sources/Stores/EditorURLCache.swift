import Foundation
import OSLog

/// A URL-based cache for storing HTTP responses keyed by URL and HTTP method.
///
/// Responses are stored on disk and survive process termination. Responses are keyed
/// by both URL and HTTP method, so GET and OPTIONS requests to the same URL are
/// stored independently.
///
/// Operations are synchronous: a value written by `store(_:for:httpMethod:)` is
/// observable on the next call to `response(for:httpMethod:)`, and entries removed
/// by `clear()` are immediately gone.
public final class EditorURLCache: @unchecked Sendable {
    private let kvStore: SQLiteKVStore
    private let cachePolicy: EditorCachePolicy
    private let performanceMonitor = SignpostMonitor(for: Logger.performance)

    /// Creates a new URL cache.
    ///
    /// - Parameters:
    ///   - cacheRoot: The directory where the persistent cache file lives.
    ///     If `nil`, a default location under the system caches directory is used.
    ///   - cachePolicy: The policy that determines when cached responses are
    ///     considered valid.
    ///   - diskCapacity: Soft cap (in bytes) on the combined size of cached bodies
    ///     and headers. After every successful store, oldest entries (by storage
    ///     date) are evicted until total size is at or below this cap. Pass `0`
    ///     to disable eviction entirely.
    public init(
        cacheRoot: URL? = nil,
        cachePolicy: EditorCachePolicy = .always,
        diskCapacity: Int = 100 * 1024 * 1024
    ) {
        let root = cacheRoot ?? URL.cachesDirectory.appending(path: "GutenbergKit-EditorURLCache")
        self.kvStore = SQLiteKVStore(directory: root, filename: "EditorURLCache.sqlite", diskCapacity: diskCapacity)
        self.cachePolicy = cachePolicy
    }

    /// Stores a response for the given URL and HTTP method.
    ///
    /// If a response already exists for this URL and method combination, it will be
    /// overwritten.
    public func store(_ response: EditorURLResponse, for url: URL, httpMethod: EditorHttpMethod) throws {
        try self.store(response, for: url, httpMethod: httpMethod, currentDate: .now)
    }

    func store(
        _ response: EditorURLResponse,
        for url: URL,
        httpMethod: EditorHttpMethod,
        currentDate: Date
    ) throws {
        let headersBlob = try JSONEncoder().encode(response.responseHeaders)
        self.kvStore.put(
            key: Self.cacheKey(httpMethod: httpMethod, url: url),
            storageDate: currentDate,
            metadata: headersBlob,
            value: response.data
        )
    }

    /// Stores the contents of a downloaded file as a cached response for the given
    /// URL and HTTP method.
    public func store(
        fileAt path: URL,
        headers: EditorHTTPHeaders,
        for url: URL,
        httpMethod: EditorHttpMethod
    ) throws {
        try self.store(fileAt: path, headers: headers, for: url, httpMethod: httpMethod, currentDate: .now)
    }

    func store(
        fileAt path: URL,
        headers: EditorHTTPHeaders,
        for url: URL,
        httpMethod: EditorHttpMethod,
        currentDate: Date
    ) throws {
        let body = try Data(contentsOf: path)
        let headersBlob = try JSONEncoder().encode(headers)
        self.kvStore.put(
            key: Self.cacheKey(httpMethod: httpMethod, url: url),
            storageDate: currentDate,
            metadata: headersBlob,
            value: body
        )
    }

    /// Checks whether a cached response exists for the given URL and HTTP method.
    public func hasData(for url: URL, httpMethod: EditorHttpMethod) throws -> Bool {
        try self.response(for: url, httpMethod: httpMethod, currentDate: .now) != nil
    }

    func hasData(for url: URL, httpMethod: EditorHttpMethod, currentDate: Date) throws -> Bool {
        try self.response(for: url, httpMethod: httpMethod, currentDate: currentDate) != nil
    }

    /// Retrieves the cached response for the given URL and HTTP method.
    public func response(for url: URL, httpMethod: EditorHttpMethod) throws -> EditorURLResponse? {
        try self.response(for: url, httpMethod: httpMethod, currentDate: .now)
    }

    func response(
        for url: URL,
        httpMethod: EditorHttpMethod,
        currentDate: Date
    ) throws -> EditorURLResponse? {
        try performanceMonitor.measure { () -> EditorURLResponse? in
            let key = Self.cacheKey(httpMethod: httpMethod, url: url)
            guard let entry = self.kvStore.get(key: key),
                  self.cachePolicy.allowsResponseWith(date: entry.storageDate, currentDate: currentDate)
            else {
                return nil
            }
            let headers = try JSONDecoder().decode(EditorHTTPHeaders.self, from: entry.metadata)
            return EditorURLResponse(data: entry.value, responseHeaders: headers)
        }
    }

    /// Removes all cached responses.
    public func clear() throws {
        self.kvStore.clear()
    }

    private static func cacheKey(httpMethod: EditorHttpMethod, url: URL) -> String {
        "\(httpMethod.rawValue):\(url.absoluteString)"
    }
}
