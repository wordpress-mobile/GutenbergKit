import Foundation
import SQLite3

/// A SQLite-backed persistent key-value store for opaque blobs.
///
/// Each entry is `(key, storageDate, metadata, value)`. Values and metadata are
/// stored as raw bytes; the caller owns any serialization. After every `put`,
/// oldest entries (by storage date) are evicted until total stored size is at
/// or below `diskCapacity`.
///
/// Thread-safe via `SQLITE_OPEN_FULLMUTEX` — concurrent calls from multiple
/// threads on the same instance are serialized internally by SQLite.
final class SQLiteKVStore: @unchecked Sendable {

    // MARK: - Debugging
    //
    // Backed by a single SQLite database at `<directory>/<filename>`.
    // Useful queries from a shell:
    //
    //     # List entries by recency, with size and date
    //     sqlite3 Store.sqlite \
    //         "SELECT key, length(value), datetime(storage_date + 978307200, 'unixepoch') \
    //          FROM entries ORDER BY storage_date DESC"
    //
    //     # Export a specific value to a file
    //     sqlite3 Store.sqlite \
    //         "SELECT writefile('/tmp/value.bin', value) FROM entries \
    //          WHERE key='...'"
    //
    // `storage_date` is `Date.timeIntervalSinceReferenceDate` (seconds since
    // 2001-01-01); +978307200 shifts to unix epoch for `datetime(..., 'unixepoch')`.

    struct Entry {
        let storageDate: Date
        let metadata: Data
        let value: Data
    }

    private let db: OpaquePointer
    private let diskCapacity: Int

    /// Schema version baked into this build. If an existing database is found at a
    /// different version, the entries table is dropped and recreated. Bump on any
    /// schema-changing update.
    private static let schemaVersion: Int32 = 1

    /// SQLite expects this sentinel to indicate that bound data should be copied.
    private static let SQLITE_TRANSIENT = unsafeBitCast(
        OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self
    )

    /// Creates a new store.
    ///
    /// - Parameters:
    ///   - handle: Identifies this store within `directory`. Becomes the database
    ///     filename (`<handle>.sqlite`), so two stores under the same `directory`
    ///     with distinct handles are independent. Must not contain path separators.
    ///   - directory: The directory where the database file lives. Defaults to
    ///     the system caches directory.
    ///   - diskCapacity: Soft cap (in bytes) on the combined size of stored values
    ///     and metadata. After every `put`, oldest entries (by storage date) are
    ///     evicted until total size is at or below this cap. A `put` for an entry
    ///     whose own size exceeds the cap is silently dropped — choose a cap
    ///     comfortably above the largest expected entry. Pass `0` to disable
    ///     eviction entirely.
    init(
        handle: String,
        directory: URL = URL.cachesDirectory,
        diskCapacity: Int
    ) {
        precondition(Self.isValidHandle(handle), "handle must be a valid filename component, not '\(handle)'")
        self.diskCapacity = diskCapacity
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dbPath = directory.appending(path: "\(handle).sqlite").path(percentEncoded: false)

        var connection: OpaquePointer?
        let openResult = sqlite3_open_v2(
            dbPath,
            &connection,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        if openResult != SQLITE_OK {
            // Fall back to an in-memory database. This loses persistence but keeps
            // the store functional within the process.
            sqlite3_close(connection)
            connection = nil
            sqlite3_open_v2(":memory:", &connection,
                            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        }
        self.db = connection!

        // If the on-disk schema version doesn't match what we expect, drop the
        // entries table — losing cached data is acceptable for a cache, and keeps
        // schema migrations to a single bump-and-recreate.
        if Self.readSchemaVersion(db: self.db) != Self.schemaVersion {
            sqlite3_exec(self.db, "DROP TABLE IF EXISTS entries;", nil, nil, nil)
            sqlite3_exec(self.db, "PRAGMA user_version = \(Self.schemaVersion);", nil, nil, nil)
        }
        sqlite3_exec(self.db, """
            CREATE TABLE IF NOT EXISTS entries (
                key TEXT PRIMARY KEY NOT NULL,
                storage_date REAL NOT NULL,
                metadata BLOB NOT NULL,
                value BLOB NOT NULL
            ) WITHOUT ROWID;
            CREATE INDEX IF NOT EXISTS entries_storage_date_idx ON entries(storage_date);
            """, nil, nil, nil)
    }

    /// Whether `handle` is a safe filename component: non-empty, no path
    /// separators, and not a directory reference (`.` or `..`).
    static func isValidHandle(_ handle: String) -> Bool {
        !handle.isEmpty
            && !handle.contains("/")
            && handle != "."
            && handle != ".."
    }

    private static func readSchemaVersion(db: OpaquePointer) -> Int32 {
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return sqlite3_column_int(stmt, 0)
    }

    deinit {
        sqlite3_close(db)
    }

    func get(key: String) -> Entry? {
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(
            self.db,
            "SELECT storage_date, metadata, value FROM entries WHERE key = ?1;",
            -1, &stmt, nil
        )
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, Self.SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        return Entry(
            storageDate: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 0)),
            metadata: Self.readBlobAsData(stmt: stmt, column: 1),
            value: Self.readBlobAsData(stmt: stmt, column: 2)
        )
    }

    /// Inserts or overwrites the entry at `key`. Runs the LRU eviction sweep
    /// afterwards so total stored size stays within `diskCapacity`.
    ///
    /// A `put` for an entry whose own size exceeds `diskCapacity` is silently
    /// dropped — the sweep would evict it immediately anyway, so the disk write
    /// is skipped.
    func put(key: String, storageDate: Date, metadata: Data, value: Data) {
        if self.diskCapacity > 0 && metadata.count + value.count > self.diskCapacity {
            return
        }

        var stmt: OpaquePointer?
        sqlite3_prepare_v2(
            self.db,
            """
            INSERT INTO entries (key, storage_date, metadata, value)
            VALUES (?1, ?2, ?3, ?4)
            ON CONFLICT(key) DO UPDATE SET
                storage_date = excluded.storage_date,
                metadata = excluded.metadata,
                value = excluded.value;
            """,
            -1, &stmt, nil
        )
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, Self.SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, storageDate.timeIntervalSinceReferenceDate)
        _ = metadata.withUnsafeBytes {
            sqlite3_bind_blob(stmt, 3, $0.baseAddress, Int32(metadata.count), Self.SQLITE_TRANSIENT)
        }
        _ = value.withUnsafeBytes {
            sqlite3_bind_blob(stmt, 4, $0.baseAddress, Int32(value.count), Self.SQLITE_TRANSIENT)
        }
        sqlite3_step(stmt)

        self.evictPastCapacity()
    }

    func clear() {
        sqlite3_exec(self.db, "DELETE FROM entries;", nil, nil, nil)
    }

    /// Evicts oldest entries (by storage date) until total stored size is at or
    /// below `diskCapacity`. A single DELETE-with-window-function query handled
    /// entirely inside SQLite.
    private func evictPastCapacity() {
        guard self.diskCapacity > 0 else { return }
        sqlite3_exec(
            self.db,
            """
            DELETE FROM entries WHERE key IN (
                SELECT key FROM (
                    SELECT key,
                           SUM(length(value) + length(metadata))
                               OVER (ORDER BY storage_date DESC, key DESC
                                     ROWS UNBOUNDED PRECEDING) AS running
                    FROM entries
                ) WHERE running > \(self.diskCapacity)
            );
            """,
            nil, nil, nil
        )
    }

    private static func readBlobAsData(stmt: OpaquePointer?, column: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(stmt, column) else { return Data() }
        let count = Int(sqlite3_column_bytes(stmt, column))
        return Data(bytes: bytes, count: count)
    }
}
