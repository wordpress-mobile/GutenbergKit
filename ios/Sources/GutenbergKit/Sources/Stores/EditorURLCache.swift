import Foundation
import OSLog
import SQLite3

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

    // MARK: - Debugging
    //
    // Backed by a single SQLite database at `<cacheRoot>/EditorURLCache.sqlite`.
    // Useful queries from a shell:
    //
    //     # List entries by recency, with size and date
    //     sqlite3 EditorURLCache.sqlite \
    //         "SELECT key, length(body), datetime(storage_date + 978307200, 'unixepoch') \
    //          FROM entries ORDER BY storage_date DESC"
    //
    //     # Export a specific body to a file
    //     sqlite3 EditorURLCache.sqlite \
    //         "SELECT writefile('/tmp/body.bin', body) FROM entries \
    //          WHERE key='GET:https://example.com/...'"
    //
    // `storage_date` is `Date.timeIntervalSinceReferenceDate` (seconds since
    // 2001-01-01); +978307200 shifts to unix epoch for `datetime(..., 'unixepoch')`.

    private let db: OpaquePointer
    private let cachePolicy: EditorCachePolicy
    private let diskCapacity: Int
    private let performanceMonitor = SignpostMonitor(for: Logger.performance)

    /// SQLite expects this sentinel to indicate that bound data should be copied.
    private static let SQLITE_TRANSIENT = unsafeBitCast(
        OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self
    )

    /// Creates a new URL cache.
    ///
    /// - Parameters:
    ///   - cacheRoot: The directory where the SQLite database will be stored.
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
        self.cachePolicy = cachePolicy
        self.diskCapacity = diskCapacity
        let root = cacheRoot ?? URL.cachesDirectory.appending(path: "GutenbergKit-EditorURLCache")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dbPath = root.appending(path: "EditorURLCache.sqlite").path(percentEncoded: false)

        var connection: OpaquePointer?
        let openResult = sqlite3_open_v2(
            dbPath,
            &connection,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        if openResult != SQLITE_OK {
            // Fall back to an in-memory database. This loses persistence but keeps
            // the cache functional within the process.
            sqlite3_close(connection)
            connection = nil
            sqlite3_open_v2(":memory:", &connection, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        }
        self.db = connection!

        sqlite3_exec(self.db, "PRAGMA journal_mode = WAL;", nil, nil, nil)
        sqlite3_exec(self.db, """
            CREATE TABLE IF NOT EXISTS entries (
                key TEXT PRIMARY KEY NOT NULL,
                storage_date REAL NOT NULL,
                headers BLOB NOT NULL,
                body BLOB NOT NULL
            ) WITHOUT ROWID;
            CREATE INDEX IF NOT EXISTS entries_storage_date_idx ON entries(storage_date);
            """, nil, nil, nil)
    }

    deinit {
        sqlite3_close(db)
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
        try self.upsert(
            body: response.data,
            headers: response.responseHeaders,
            url: url,
            httpMethod: httpMethod,
            currentDate: currentDate
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
        try self.upsert(
            body: body,
            headers: headers,
            url: url,
            httpMethod: httpMethod,
            currentDate: currentDate
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
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(
                self.db,
                "SELECT storage_date, headers, body FROM entries WHERE key = ?1;",
                -1, &stmt, nil
            )
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, key, -1, Self.SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

            let storageDate = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 0))
            guard self.cachePolicy.allowsResponseWith(date: storageDate, currentDate: currentDate) else {
                return nil
            }
            let headers = try Self.readHeadersBlob(stmt: stmt, column: 1)
            let body = Self.readBlobAsData(stmt: stmt, column: 2)
            return EditorURLResponse(data: body, responseHeaders: headers)
        }
    }

    /// Removes all cached responses.
    public func clear() throws {
        sqlite3_exec(self.db, "DELETE FROM entries;", nil, nil, nil)
    }

    // MARK: - Private

    private func upsert(
        body: Data,
        headers: EditorHTTPHeaders,
        url: URL,
        httpMethod: EditorHttpMethod,
        currentDate: Date
    ) throws {
        let key = Self.cacheKey(httpMethod: httpMethod, url: url)
        let headersBlob = try JSONEncoder().encode(headers)

        var stmt: OpaquePointer?
        sqlite3_prepare_v2(
            self.db,
            """
            INSERT INTO entries (key, storage_date, headers, body)
            VALUES (?1, ?2, ?3, ?4)
            ON CONFLICT(key) DO UPDATE SET
                storage_date = excluded.storage_date,
                headers = excluded.headers,
                body = excluded.body;
            """,
            -1, &stmt, nil
        )
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, Self.SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, currentDate.timeIntervalSinceReferenceDate)
        _ = headersBlob.withUnsafeBytes {
            sqlite3_bind_blob(stmt, 3, $0.baseAddress, Int32(headersBlob.count), Self.SQLITE_TRANSIENT)
        }
        _ = body.withUnsafeBytes {
            sqlite3_bind_blob(stmt, 4, $0.baseAddress, Int32(body.count), Self.SQLITE_TRANSIENT)
        }
        sqlite3_step(stmt)

        self.evictPastCapacity()
    }

    /// Evicts oldest entries (by storage date) until total stored size is at or
    /// below `diskCapacity`. Run after every store. Cheap: a single DELETE-with-
    /// window-function query handled entirely inside SQLite.
    private func evictPastCapacity() {
        guard self.diskCapacity > 0 else { return }
        sqlite3_exec(
            self.db,
            """
            DELETE FROM entries WHERE key IN (
                SELECT key FROM (
                    SELECT key,
                           SUM(length(body) + length(headers))
                               OVER (ORDER BY storage_date DESC, key DESC
                                     ROWS UNBOUNDED PRECEDING) AS running
                    FROM entries
                ) WHERE running > \(self.diskCapacity)
            );
            """,
            nil, nil, nil
        )
    }

    private static func cacheKey(httpMethod: EditorHttpMethod, url: URL) -> String {
        "\(httpMethod.rawValue):\(url.absoluteString)"
    }

    private static func readHeadersBlob(stmt: OpaquePointer?, column: Int32) throws -> EditorHTTPHeaders {
        let blob = readBlobAsData(stmt: stmt, column: column)
        return try JSONDecoder().decode(EditorHTTPHeaders.self, from: blob)
    }

    private static func readBlobAsData(stmt: OpaquePointer?, column: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(stmt, column) else { return Data() }
        let count = Int(sqlite3_column_bytes(stmt, column))
        return Data(bytes: bytes, count: count)
    }
}
