import Foundation
import OSLog

/// A URL-based cache for storing HTTP responses keyed by URL and HTTP method.
///
/// Responses are stored on disk and survive process termination. Responses are keyed by both URL and HTTP method, so GET and OPTIONS requests to the
/// same URL are stored independently.
///
/// Backed by `SQLiteKVCache`. The "one instance per backing file" contract from
/// `SQLiteKVCache` carries over: two `EditorURLCache` instances pointed at the
/// same `cacheRoot` is undefined behavior.
public struct EditorURLCache: Sendable {
    /// About enough for 10 sites of cached responses.
    private static let diskCapacity = 100 * 1024 * 1024

    private let store: SQLiteKVCache
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
        self.store = SQLiteKVCache(
            handle: "editorurlcache",
            directory: cacheRoot ?? URL.cachesDirectory,
            diskCapacity: Self.diskCapacity
        )
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

    func store(
        _ response: EditorURLResponse,
        for url: URL,
        httpMethod: EditorHttpMethod,
        currentDate: Date
    ) throws {
        try self.store.put(
            key: Self.key(url: url, httpMethod: httpMethod),
            storageDate: currentDate,
            metadata: try JSONEncoder().encode(response.responseHeaders),
            value: response.data
        )
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

    func store(
        fileAt path: URL,
        headers: EditorHTTPHeaders,
        for url: URL,
        httpMethod: EditorHttpMethod,
        currentDate: Date
    ) throws {
        try self.store.put(
            key: Self.key(url: url, httpMethod: httpMethod),
            storageDate: currentDate,
            metadata: try JSONEncoder().encode(headers),
            value: try Data(contentsOf: path)
        )
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

    func hasData(for url: URL, httpMethod: EditorHttpMethod, currentDate: Date) throws -> Bool {
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

    func response(
        for url: URL,
        httpMethod: EditorHttpMethod,
        currentDate: Date
    ) throws -> EditorURLResponse? {
        try performanceMonitor.measure { () throws -> EditorURLResponse? in
            guard
                let entry = try self.store.get(key: Self.key(url: url, httpMethod: httpMethod)),
                self.cachePolicy.allowsResponseWith(date: entry.storageDate, currentDate: currentDate)
            else {
                return nil
            }
            let headers = try JSONDecoder().decode(EditorHTTPHeaders.self, from: entry.metadata)
            return EditorURLResponse(data: entry.value, responseHeaders: headers)
        }
    }

    /// Removes all cached responses.
    ///
    /// - Throws: An error if the cache cannot be cleared.
    public func clear() throws {
        try self.store.clear()
    }

    /// Combines the HTTP method and URL into a single string key. `SQLiteKVCache`
    /// hashes the key with SHA-256 before binding to SQLite, so length, escaping,
    /// and encoding aren't concerns here.
    private static func key(url: URL, httpMethod: EditorHttpMethod) -> String {
        "\(httpMethod.rawValue) \(url.absoluteString)"
    }
}
