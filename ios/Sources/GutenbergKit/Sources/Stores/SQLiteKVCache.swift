import CryptoKit
import Foundation
import OSLog
import SQLite3

/// A SQLite-backed persistent key-value cache for opaque blobs.
///
/// **Cache only — not a primary store.** Although entries persist across
/// process restarts, the on-disk contract is intentionally lossy: a schema
/// version mismatch drops the table on open; eviction discards oldest-first
/// when total content exceeds `diskCapacity`; and `synchronous = NORMAL`
/// trades the last few committed writes on power loss for substantially
/// faster small writes. Use this for data that's cheap to refetch from a
/// canonical source — never as the only copy.
///
/// Each entry is `(key, storageDate, metadata, value)`. Values and metadata are
/// stored as raw bytes; the caller owns any serialization. After every `put`,
/// oldest entries (by storage date) are evicted until total stored size is at
/// or below `diskCapacity`.
///
/// **Keys.** The cache accepts any `String` as a key and internally hashes it
/// (SHA-256, raw 32-byte digest) before binding into SQLite. This means callers
/// don't have to think about key length, SQL escaping, embedded null bytes, or
/// character encoding — anything the caller can hand us round-trips. The trade
/// is debuggability: a `sqlite3 ... SELECT hex(key) FROM entries` shows hash
/// digests as hex, not the original input strings.
///
/// **Concurrency.** Thread-safe. Every operation is a single autocommit SQL
/// statement: `put` is `INSERT … ON CONFLICT DO UPDATE` with the eviction
/// sweep happening inside `AFTER INSERT` / `AFTER UPDATE` triggers; `get`,
/// `delete`, and `clear` are also single statements. `SQLITE_OPEN_FULLMUTEX`
/// serializes the C-level API calls on the connection, and SQLite's
/// per-statement atomicity (including trigger bodies) handles the rest —
/// there's no Swift-level lock because there's no multi-statement transaction
/// to fence. Single-thread `put` then `get` always observes the put.
///
/// **One instance per backing file.** Opening two `SQLiteKVCache` instances
/// against the same `<directory>/<handle>.sqlite` (whether in the same process
/// or across processes — main app vs. share extension) is **undefined
/// behavior**. The eviction triggers are recreated unconditionally on every
/// open with the current instance's `diskCapacity` baked into them, so two
/// instances with different caps would clobber each other's triggers; in the
/// best case you get the wrong cap, in the worst case `SQLITE_BUSY` while the
/// recreations race. Each backing file must have exactly one owning
/// `SQLiteKVCache` for the lifetime of the process. Not currently enforced at
/// runtime — this is a usage contract.
///
/// **Schema migrations.** A `schemaVersion` constant baked into the build is
/// compared against `PRAGMA user_version` on open; mismatches drop and recreate
/// the table. The check trusts the version: if a buggy past build wrote a
/// matching `user_version` but the wrong column shape, this won't detect it.
///
/// **Disk reclamation.** `diskCapacity` caps the *content* size — the sum of
/// `length(value) + length(metadata)` across rows. The on-disk file can drift
/// past that cap because evicted/deleted rows leave free pages on the SQLite
/// freelist, which `auto_vacuum = NONE` (the default) doesn't reclaim. Rather
/// than enable `auto_vacuum = FULL` (which would rewrite freelist pages on
/// every transaction), the open path runs a single `VACUUM` if the freelist
/// has grown past `vacuumFreelistThreshold` of total pages — bounding the
/// SSD-churn cost to once per process and skipping launches where there's
/// nothing meaningful to reclaim.
final class SQLiteKVCache: @unchecked Sendable {

    enum Error: Swift.Error {
        /// The cache couldn't be opened or set up. Typically the caches
        /// directory is sandboxed-out, the disk is full, an existing file
        /// at the path is corrupt, or a setup pragma / DDL statement
        /// failed during open. The first operation on the cache throws
        /// this and so does every subsequent operation (the failure is
        /// cached) — callers using `try?` get a uniform "cache
        /// unavailable" fall-through. Silently degrading to a
        /// process-lifetime in-memory store would violate the persistence
        /// contract `put` implies. The originating SQLite error code is
        /// not preserved on this case (setup-time failures collapse to
        /// the same surface) but is logged at the failure site.
        case databaseUnavailable
        /// A read (`get`) failed inside SQLite. The associated value is the
        /// SQLite error code. Cache callers that want the prior "treat read
        /// failures as misses" behavior can wrap the call in `try?`.
        case readFailed(sqliteCode: Int32)
        /// A write (`put`, `delete`, or `clear`) failed inside SQLite. The
        /// associated value is the SQLite error code — common ones include
        /// `SQLITE_FULL` (disk full, code 13), `SQLITE_TOOBIG` (blob over
        /// `SQLITE_MAX_LENGTH`, code 18), and `SQLITE_CORRUPT` (code 11).
        case writeFailed(sqliteCode: Int32)
    }

    // MARK: - Debugging
    //
    // Backed by a single SQLite database at `<directory>/<handle>.sqlite`.
    // Useful queries from a shell:
    //
    //     # List entries by recency, with size and date
    //     sqlite3 Store.sqlite \
    //         "SELECT hex(key), length(value), datetime(storage_date + 978307200, 'unixepoch') \
    //          FROM entries ORDER BY storage_date DESC"
    //
    //     # Export a specific value to a file (key is the SHA-256 digest as hex)
    //     sqlite3 Store.sqlite \
    //         "SELECT writefile('/tmp/value.bin', value) FROM entries \
    //          WHERE key = x'<digest-hex>'"
    //
    // `storage_date` is `Date.timeIntervalSinceReferenceDate` (seconds since
    // 2001-01-01); +978307200 shifts to unix epoch for `datetime(..., 'unixepoch')`.

    struct Entry {
        let storageDate: Date
        let metadata: Data
        let value: Data
    }

    private let diskCapacity: Int
    private let directory: URL
    private let filename: String

    /// Cached open result. `nil` means "open hasn't been attempted yet"; once
    /// set, either holds the live connection or the error we'll keep handing
    /// back for the lifetime of the cache. Reading and writing both happen
    /// under `openLock` — the cached value is read/written via the same code
    /// path, and the open work runs at most once per cache.
    private var dbResult: Result<OpaquePointer, Swift.Error>?
    private let openLock = NSLock()

    /// Schema version baked into this build. The on-disk `PRAGMA user_version`
    /// is checked on open; anything other than this exact value triggers a
    /// drop-and-recreate. That includes the fresh-database case (`user_version`
    /// defaults to 0 on a brand-new SQLite file), so the first open of a new
    /// database also runs the drop path — harmless because there's nothing to
    /// drop. Bump only on changes that hit user devices — pre-ship iteration
    /// shouldn't burn version numbers. Never decrement (a downgrade would
    /// silently wipe users' caches a second time on the next upgrade).
    private static let schemaVersion: Int32 = 1

    private static let logger = Logger(subsystem: "GutenbergKit", category: "sqlite-kv-cache")

    /// SQLite C API: signals that bound data should be copied. Reinvented here
    /// because the `SQLITE_TRANSIENT` C macro doesn't import to Swift.
    private static let SQLITE_TRANSIENT = unsafeBitCast(
        OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self
    )

    /// Creates a new cache. **Non-throwing**: the SQLite connection is opened
    /// lazily on the first `get`/`put`/`delete`/`clear`. If the open or schema
    /// setup fails, the failure is cached and re-thrown from every subsequent
    /// operation — callers using `try?` get a uniform "cache unavailable"
    /// fall-through without a separate error path at the construction site.
    ///
    /// - Parameters:
    ///   - handle: Identifies this cache within `directory`. Becomes the database
    ///     filename (`<lowercasedHandle>.sqlite`). Required to be a string
    ///     literal so it's known at compile time, and required to match
    ///     `[a-zA-Z0-9._-]` after lowercasing. Lowercasing is unconditional;
    ///     the `[a-zA-Z0-9._-]` shape check is enforced by a debug-build
    ///     assertion only — release builds skip the check and use the
    ///     lowercased handle as-is, which can produce an unexpected filename
    ///     if the input contained disallowed characters.
    ///   - directory: The directory where the database file lives. Defaults to
    ///     the system caches directory.
    ///   - diskCapacity: Soft cap (in bytes) on the combined size of stored values
    ///     and metadata. After every `put`, oldest entries (by storage date) are
    ///     evicted until total size is at or below this cap. A `put` for an entry
    ///     whose own size exceeds the cap is silently dropped — choose a cap
    ///     comfortably above the largest expected entry. Pass `0` to disable
    ///     eviction entirely.
    init(
        handle: StaticString,
        directory: URL = URL.cachesDirectory,
        diskCapacity: Int
    ) {
        let filename = "\(handle)".lowercased()
        assert(
            Self.isValidHandle(filename),
            "handle must be a non-empty filename component matching [a-zA-Z0-9._-]; got '\(handle)'"
        )
        self.diskCapacity = diskCapacity
        self.directory = directory
        self.filename = filename
    }

    /// Whether `name` is a safe filename component: non-empty, only
    /// `[a-z0-9._-]`, and not a directory reference (`.` or `..`).
    /// Used by the debug-build assertion in `init`.
    static func isValidHandle(_ name: String) -> Bool {
        let allowed: Set<Character> = Set("abcdefghijklmnopqrstuvwxyz0123456789._-")
        return !name.isEmpty
            && name.allSatisfy { allowed.contains($0) }
            && name != "."
            && name != ".."
    }

    /// Opens the database on first call and caches the result; subsequent
    /// calls return the cached connection (or re-throw the cached error).
    /// Every public operation routes through this helper, so a connection
    /// is opened at most once per cache regardless of which method is
    /// called first.
    private func connection() throws -> OpaquePointer {
        openLock.lock()
        defer { openLock.unlock() }
        if let cached = dbResult {
            return try cached.get()
        }
        let result = Result<OpaquePointer, Swift.Error> {
            try Self.openAndConfigure(directory: self.directory, filename: self.filename, diskCapacity: self.diskCapacity)
        }
        dbResult = result
        return try result.get()
    }

    /// Opens the SQLite file, applies performance pragmas, and either creates
    /// or migrates the schema. Called from `connection()` once per cache. On
    /// any failure after the connection handle is alive, the handle is closed
    /// before the error propagates so we don't leak it into the cached
    /// failure.
    private static func openAndConfigure(directory: URL, filename: String, diskCapacity: Int) throws -> OpaquePointer {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // File protection: files created under the default `URL.cachesDirectory`
        // inherit `NSFileProtectionCompleteUntilFirstUserAuthentication` —
        // unreadable until the user has unlocked the device once since boot.
        // That's the right tier for cached HTTP bodies (which may include
        // cookies / auth headers) but not for highly sensitive secrets.
        // Callers needing a stricter class can pass a `directory` configured
        // with `.completeUnlessOpen` or `.complete`.
        //
        // `appending(component:)` treats the input as a single path component (so a
        // stray `/` would be percent-encoded, not interpreted as a separator), and
        // `appendingPathExtension` keeps us from string-interpolating the suffix.
        let dbPath = directory
            .appending(component: filename)
            .appendingPathExtension("sqlite")
            .path(percentEncoded: false)

        var connection: OpaquePointer?
        let openResult = sqlite3_open_v2(
            dbPath,
            &connection,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        if openResult != SQLITE_OK {
            Self.logger.error("Failed to open '\(dbPath)': \(Self.describe(openResult))")
            // Per the SQLite contract, a failed `sqlite3_open_v2` may still
            // hand back a connection handle that needs closing. `_close_v2`
            // tolerates a nil pointer, so this is safe either way.
            sqlite3_close_v2(connection)
            throw Error.databaseUnavailable
        }
        guard let connection else {
            throw Error.databaseUnavailable
        }

        // Pragmas + schema setup. Pragmas first because `journal_mode`
        // changes must run with no active transaction. `journal_mode = WAL`
        // switches from the default rollback-journal to a write-ahead log:
        // smaller, sequential commits, and readers no longer block at the
        // file level the way they do under rollback-journal mode. Combined
        // with `synchronous = NORMAL` this trades a small slice of
        // durability — last few committed transactions could be lost on
        // power loss, but not on a clean process crash — for substantially
        // faster small writes. Acceptable here because this is a cache:
        // losing the last few writes after a power cut just means a few
        // extra refetches against the network, not data loss against a
        // primary store. (WAL alone doesn't change in-process isolation: a
        // same-connection reader during an in-flight write still sees the
        // uncommitted state — that would only change with a separate reader
        // connection.) WAL is a correctness dependency for `synchronous =
        // NORMAL`, so `enableWAL` verifies the resulting journal mode rather
        // than relying on the pragma's return code; see its doc-comment.
        //
        // If anything from this point fails, the connection is closed before
        // the error propagates so the cached failure result in `connection()`
        // doesn't leak the handle.
        do {
            try Self.enableWAL(on: connection)
            try Self.exec("PRAGMA synchronous = NORMAL;", on: connection)

            // If the on-disk schema version doesn't match what we expect,
            // drop the entries table — losing cached data is acceptable for a
            // cache, and keeps schema migrations to a single bump-and-recreate.
            if try Self.readSchemaVersion(db: connection) != Self.schemaVersion {
                try Self.exec("DROP TABLE IF EXISTS entries;", on: connection)
                try Self.exec("PRAGMA user_version = \(Self.schemaVersion);", on: connection)
            }
            try Self.exec("""
                CREATE TABLE IF NOT EXISTS entries (
                    key BLOB PRIMARY KEY NOT NULL,
                    storage_date REAL NOT NULL,
                    metadata BLOB NOT NULL,
                    value BLOB NOT NULL
                ) WITHOUT ROWID;
                CREATE INDEX IF NOT EXISTS entries_storage_date_idx ON entries(storage_date);
                """, on: connection)
            try Self.installEvictionTriggers(on: connection, diskCapacity: diskCapacity)
            try Self.vacuumIfWorthwhile(on: connection)
        } catch {
            sqlite3_close_v2(connection)
            // Setup-time failures (a setup pragma, DDL, trigger install, or
            // VACUUM rejected by SQLite) all collapse to `databaseUnavailable`
            // here — the originating exec helper threw `writeFailed` for its
            // own reasons, but the user-facing surface is "the cache failed
            // to come up", not "a write failed". The originating SQLite code
            // was already logged at the exec site.
            throw Error.databaseUnavailable
        }

        return connection
    }

    /// Runs `VACUUM` if the freelist is at least `vacuumFreelistThreshold` of
    /// the database's pages. Called once during open after the schema is
    /// settled, so churn from past sessions (eviction sweeps, schema-mismatch
    /// table drops, explicit deletes) is reclaimed at most once per process —
    /// versus `auto_vacuum = FULL` which would touch the freelist on every
    /// transaction. The threshold is tuned so VACUUM's I/O cost (a full DB
    /// rewrite, copying every non-free page) is in the same order of magnitude
    /// as the bytes reclaimed: at 25% freelist the ratio is ~3:1, at 5% it's
    /// ~20:1 — at the lower end the rewrite costs more I/O than it saves on
    /// disk, so we'd rather leave the freelist in place.
    ///
    /// Skipping when `total == 0` covers the brand-new-DB case where SQLite
    /// hasn't allocated any pages yet (a freshly opened, never-written file).
    private static func vacuumIfWorthwhile(on db: OpaquePointer) throws {
        let freelist = try Self.readIntPragma("freelist_count", on: db)
        let total = try Self.readIntPragma("page_count", on: db)
        guard total > 0 else { return }
        let fraction = Double(freelist) / Double(total)
        guard fraction > Self.vacuumFreelistThreshold else { return }
        Self.logger.info("Running VACUUM (freelist=\(freelist)/\(total) pages, fraction=\(fraction))")
        try Self.exec("VACUUM;", on: db)
    }

    /// Freelist-to-total-pages ratio above which `vacuumIfWorthwhile` rewrites
    /// the database on open. See `vacuumIfWorthwhile` for the cost-benefit
    /// reasoning. Exposed (non-private) so tests can pin the threshold without
    /// duplicating the constant.
    static let vacuumFreelistThreshold: Double = 0.25

    /// Drops and recreates the eviction triggers with `diskCapacity` baked
    /// into the trigger SQL. Called on every successful open: `diskCapacity`
    /// is a constructor parameter that can change between opens of the same
    /// file, and the triggers don't auto-update — drop-and-recreate is the
    /// simplest way to ensure the running database always reflects the
    /// current instance's cap. (This same drop-and-recreate is what makes the
    /// "one instance per backing file" contract a real failure mode: a
    /// second instance with a different cap would clobber the first's
    /// triggers.) With `diskCapacity == 0` the triggers are dropped and not
    /// recreated, disabling eviction entirely.
    ///
    /// Two triggers are installed because SQLite fires `AFTER UPDATE` (not
    /// `AFTER INSERT`) on the upsert's `ON CONFLICT DO UPDATE` branch, but
    /// fresh-key inserts fire `AFTER INSERT`. Bodies are identical: a
    /// window-function DELETE that removes oldest-by-`storage_date` rows
    /// until total stored size is at or below `diskCapacity`. The `WHEN`
    /// guard short-circuits the body when the table is already under cap so
    /// the common path is just a cheap aggregate scan, not a window-function
    /// query.
    ///
    /// `diskCapacity` is interpolated into the trigger SQL — it's an `Int`
    /// constant, not user input, so there's no injection vector. Triggers
    /// run inside the firing statement's implicit transaction; if the
    /// eviction DELETE fails (disk full, etc.), SQLite rolls back the entire
    /// statement — the original INSERT/UPDATE is undone with it, with no
    /// Swift-side orchestration needed.
    private static func installEvictionTriggers(on db: OpaquePointer, diskCapacity: Int) throws {
        try Self.exec("DROP TRIGGER IF EXISTS entries_evict_after_insert;", on: db)
        try Self.exec("DROP TRIGGER IF EXISTS entries_evict_after_update;", on: db)
        guard diskCapacity > 0 else { return }
        let evictionBody = """
            DELETE FROM entries WHERE key IN (
                SELECT key FROM (
                    SELECT key,
                           SUM(length(value) + length(metadata))
                               OVER (ORDER BY storage_date DESC, key DESC
                                     ROWS UNBOUNDED PRECEDING) AS running
                    FROM entries
                ) WHERE running > \(diskCapacity)
            );
            """
        let whenGuard = "(SELECT COALESCE(SUM(length(value) + length(metadata)), 0) FROM entries) > \(diskCapacity)"
        try Self.exec("""
            CREATE TRIGGER entries_evict_after_insert AFTER INSERT ON entries
            WHEN \(whenGuard)
            BEGIN
                \(evictionBody)
            END;
            """, on: db)
        try Self.exec("""
            CREATE TRIGGER entries_evict_after_update AFTER UPDATE ON entries
            WHEN \(whenGuard)
            BEGIN
                \(evictionBody)
            END;
            """, on: db)
    }

    /// Sets `PRAGMA journal_mode = WAL;` and verifies that the database
    /// actually switched to WAL. SQLite returns the resulting journal mode
    /// in a row regardless of whether the requested change took effect — if
    /// WAL can't be applied (an exclusive lock is held, the platform doesn't
    /// support shared memory, etc.) the pragma quietly keeps the previous
    /// mode and reports it. We can't tell "succeeded" from "kept the old
    /// mode" via `sqlite3_exec`, so this helper prepares the pragma, steps
    /// it, and reads the row back. WAL is a correctness dependency for
    /// `synchronous = NORMAL` (NORMAL is documented safe under WAL but only
    /// "probably safe" under rollback-journal), so a non-WAL result here
    /// fails the open rather than silently degrading to the unsafe pairing.
    private static func enableWAL(on db: OpaquePointer) throws {
        var stmt: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, "PRAGMA journal_mode = WAL;", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        guard prepareResult == SQLITE_OK else {
            Self.logger.error("enableWAL prepare failed: \(Self.describe(prepareResult))")
            throw Error.databaseUnavailable
        }
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            Self.logger.error("enableWAL step did not return a row")
            throw Error.databaseUnavailable
        }
        guard let cString = sqlite3_column_text(stmt, 0) else {
            Self.logger.error("enableWAL returned NULL mode")
            throw Error.databaseUnavailable
        }
        let mode = String(cString: cString)
        guard mode == "wal" else {
            Self.logger.error("WAL not applied; resulting journal mode is '\(mode)'")
            throw Error.databaseUnavailable
        }
    }

    private static func readSchemaVersion(db: OpaquePointer) throws -> Int32 {
        try Self.readIntPragma("user_version", on: db)
    }

    /// Reads a SQLite integer-valued PRAGMA from `db`. The pragma name is
    /// interpolated into the SQL — only ever called with hardcoded constants
    /// from inside this file, so there's no injection vector. Throws
    /// `databaseUnavailable` on prepare/step failure (matching the open path's
    /// other pragma helpers).
    private static func readIntPragma(_ pragma: String, on db: OpaquePointer) throws -> Int32 {
        var stmt: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, "PRAGMA \(pragma);", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        guard prepareResult == SQLITE_OK else {
            Self.logger.error("readIntPragma(\(pragma)) prepare failed: \(Self.describe(prepareResult))")
            throw Error.databaseUnavailable
        }
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            Self.logger.error("readIntPragma(\(pragma)) step did not return a row")
            throw Error.databaseUnavailable
        }
        return sqlite3_column_int(stmt, 0)
    }

    deinit {
        // Close only if the open succeeded. A cached failure or never-attempted
        // open both leave nothing to close. `sqlite3_close_v2` tolerates
        // outstanding statements (the prepared-statement path uses
        // `defer { finalize }` in the nominal case, but a bug-induced leak
        // would otherwise cause the connection to leak too). No lock here:
        // deinit only fires when refcount hits zero, so no other thread holds
        // a reference to read or mutate `dbResult`.
        if case .success(let db) = dbResult {
            sqlite3_close_v2(db)
        }
    }

    /// Looks up the entry at `key`. Returns `nil` for a genuine miss
    /// (`SQLITE_DONE` from the step). Throws `Error.readFailed` for any other
    /// non-row step result or a prepare failure — cache callers that want the
    /// prior "treat read failures as misses" behavior can wrap the call in
    /// `try?`. Failures are also logged so a wedged or corrupt cache is
    /// visible in the OS log instead of looking like a steady stream of misses.
    func get(key: String) throws -> Entry? {
        let db = try connection()
        var stmt: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(
            db,
            "SELECT storage_date, metadata, value FROM entries WHERE key = ?1;",
            -1, &stmt, nil
        )
        defer { sqlite3_finalize(stmt) }
        if prepareResult != SQLITE_OK {
            Self.logger.error("get failed at sqlite3_prepare_v2: \(Self.describe(prepareResult))")
            throw Error.readFailed(sqliteCode: prepareResult)
        }
        try Self.bindKey(key, stmt: stmt, column: 1, onError: Error.readFailed)

        let stepResult = sqlite3_step(stmt)
        switch stepResult {
        case SQLITE_ROW:
            return Entry(
                storageDate: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 0)),
                metadata: Self.readBlobAsData(stmt: stmt, column: 1),
                value: Self.readBlobAsData(stmt: stmt, column: 2)
            )
        case SQLITE_DONE:
            return nil
        default:
            Self.logger.error("get failed at sqlite3_step: \(Self.describe(stepResult))")
            throw Error.readFailed(sqliteCode: stepResult)
        }
    }

    /// Inserts or overwrites the entry at `key`. The eviction sweep runs
    /// inside an `AFTER INSERT`/`AFTER UPDATE` trigger, so this method is a
    /// single autocommit SQL statement; SQLite handles atomicity (a failure
    /// in the trigger body rolls back the entire statement, including the
    /// inserted row). The trigger body is gated by a `WHEN (SELECT SUM…) >
    /// diskCapacity` aggregate, so puts that don't push the table past cap
    /// pay only that scan, not the full window-function eviction query.
    ///
    /// A `put` for an entry whose own size exceeds `diskCapacity` is silently
    /// dropped — the trigger would insert it then immediately evict it, so we
    /// short-circuit and skip the round trip. Throws `Error.writeFailed` if
    /// SQLite rejects the write (disk full, blob over `SQLITE_MAX_LENGTH`,
    /// database corruption, etc.).
    func put(key: String, storageDate: Date, metadata: Data, value: Data) throws {
        if self.diskCapacity > 0 && metadata.count + value.count > self.diskCapacity {
            return
        }

        let db = try connection()

        var stmt: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(
            db,
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
        if prepareResult != SQLITE_OK {
            Self.logger.error("put failed at sqlite3_prepare_v2: \(Self.describe(prepareResult))")
            throw Error.writeFailed(sqliteCode: prepareResult)
        }
        try Self.bindKey(key, stmt: stmt, column: 1, onError: Error.writeFailed)
        try Self.bindDouble(storageDate.timeIntervalSinceReferenceDate, stmt: stmt, column: 2, onError: Error.writeFailed)
        try Self.bindBlob(metadata, stmt: stmt, column: 3, onError: Error.writeFailed)
        try Self.bindBlob(value, stmt: stmt, column: 4, onError: Error.writeFailed)
        let stepResult = sqlite3_step(stmt)
        if stepResult != SQLITE_DONE {
            Self.logger.error("put failed at sqlite3_step: \(Self.describe(stepResult))")
            throw Error.writeFailed(sqliteCode: stepResult)
        }
    }

    /// Removes the entry at `key`, if any. Throws `Error.writeFailed` if SQLite
    /// rejects the delete.
    func delete(key: String) throws {
        let db = try connection()

        var stmt: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, "DELETE FROM entries WHERE key = ?1;", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        if prepareResult != SQLITE_OK {
            Self.logger.error("delete failed at sqlite3_prepare_v2: \(Self.describe(prepareResult))")
            throw Error.writeFailed(sqliteCode: prepareResult)
        }
        try Self.bindKey(key, stmt: stmt, column: 1, onError: Error.writeFailed)
        let stepResult = sqlite3_step(stmt)
        if stepResult != SQLITE_DONE {
            Self.logger.error("delete failed at sqlite3_step: \(Self.describe(stepResult))")
            throw Error.writeFailed(sqliteCode: stepResult)
        }
    }

    /// Removes all entries. Throws `Error.writeFailed` if SQLite rejects the
    /// delete.
    func clear() throws {
        let db = try connection()
        try Self.exec("DELETE FROM entries;", on: db)
    }

    /// Hashes the caller's key with SHA-256 and binds the raw 32-byte digest as
    /// the SQLite `BLOB` parameter at `column`. Hashing produces a fixed-length
    /// 32-byte digest regardless of the input, which side-steps key length
    /// limits, embedded null bytes, encoding issues, and SQL-special-character
    /// concerns. Throws via `onError` if SQLite rejects the bind.
    private static func bindKey(
        _ key: String,
        stmt: OpaquePointer?,
        column: Int32,
        onError: (Int32) -> Error
    ) throws {
        try Self.bindBlob(Self.hashKey(key), stmt: stmt, column: column, onError: onError)
    }

    /// Binds `data` as the SQLite `BLOB` parameter at `column`. Uses
    /// `sqlite3_bind_blob64` (UInt64 length) instead of `sqlite3_bind_blob`
    /// (Int32) so the byte-count cast can't trap on hypothetical >2 GiB inputs.
    /// SQLite still rejects anything over `SQLITE_MAX_LENGTH` (~1 GiB by
    /// default) with `SQLITE_TOOBIG`, surfaced via `onError`. Read callers
    /// pass `Error.readFailed`, write callers pass `Error.writeFailed`.
    private static func bindBlob(
        _ data: Data,
        stmt: OpaquePointer?,
        column: Int32,
        onError: (Int32) -> Error
    ) throws {
        let result = data.withUnsafeBytes {
            sqlite3_bind_blob64(stmt, column, $0.baseAddress, sqlite3_uint64(data.count), Self.SQLITE_TRANSIENT)
        }
        if result != SQLITE_OK {
            Self.logger.error("bind blob failed at column \(column): \(Self.describe(result))")
            throw onError(result)
        }
    }

    /// Binds `value` as the SQLite `REAL` parameter at `column`. Throws via
    /// `onError` if SQLite rejects the bind.
    private static func bindDouble(
        _ value: Double,
        stmt: OpaquePointer?,
        column: Int32,
        onError: (Int32) -> Error
    ) throws {
        let result = sqlite3_bind_double(stmt, column, value)
        if result != SQLITE_OK {
            Self.logger.error("bind double failed at column \(column): \(Self.describe(result))")
            throw onError(result)
        }
    }

    private static func hashKey(_ key: String) -> Data {
        Data(SHA256.hash(data: Data(key.utf8)))
    }

    /// Wraps `sqlite3_exec`, logs non-OK return codes, and throws on failure.
    /// Used for DDL (table/index/trigger setup) and one-shot writes (`clear`'s
    /// table-wide DELETE) where the caller doesn't need a prepared statement.
    private static func exec(_ sql: String, on db: OpaquePointer) throws {
        let result = sqlite3_exec(db, sql, nil, nil, nil)
        if result != SQLITE_OK {
            Self.logger.error("exec failed: \(Self.describe(result)) — \(sql)")
            throw Error.writeFailed(sqliteCode: result)
        }
    }

    private static func readBlobAsData(stmt: OpaquePointer?, column: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(stmt, column) else { return Data() }
        let count = Int(sqlite3_column_bytes(stmt, column))
        return Data(bytes: bytes, count: count)
    }

    /// Maps a SQLite result code to its human-readable English description via
    /// `sqlite3_errstr`. Used in log messages and `Error` descriptions so
    /// callers see "disk I/O error (code 10)" instead of "code 10".
    fileprivate static func describe(_ code: Int32) -> String {
        if let cString = sqlite3_errstr(code) {
            return "\(String(cString: cString)) (code \(code))"
        }
        return "code \(code)"
    }
}

extension SQLiteKVCache.Error: CustomStringConvertible, LocalizedError {
    var description: String {
        switch self {
        case .databaseUnavailable:
            return "SQLite database is unavailable (open or setup failed)"
        case .readFailed(let sqliteCode):
            return "SQLite read failed: \(SQLiteKVCache.describe(sqliteCode))"
        case .writeFailed(let sqliteCode):
            return "SQLite write failed: \(SQLiteKVCache.describe(sqliteCode))"
        }
    }

    var errorDescription: String? { description }
}

extension SQLiteKVCache {

    /// Convenience initializer that accepts the cap as a
    /// `Measurement<UnitInformationStorage>` so callers can write
    /// `Measurement(value: 100, unit: .mebibytes)` instead of an opaque
    /// `100 * 1024 * 1024`. The measurement is converted to bytes (truncated
    /// to `Int`) and forwarded to the designated initializer.
    convenience init(
        handle: StaticString,
        directory: URL = URL.cachesDirectory,
        diskCapacity: Measurement<UnitInformationStorage>
    ) {
        self.init(
            handle: handle,
            directory: directory,
            diskCapacity: Int(diskCapacity.converted(to: .bytes).value)
        )
    }

    /// JSON-encodes a `Codable` value and stores it. Metadata stays raw `Data`
    /// — callers that want a structured metadata payload should encode it
    /// themselves and use the base `put`. The `value:` argument label here is
    /// shared with the base `put(_:..., value: Data, ...)`; for `Data` values,
    /// Swift's overload resolution picks the non-generic original.
    func put<Value: Encodable>(
        key: String,
        storageDate: Date,
        metadata: Data = Data(),
        value: Value,
        encoder: JSONEncoder = JSONEncoder()
    ) throws {
        try self.put(
            key: key,
            storageDate: storageDate,
            metadata: metadata,
            value: try encoder.encode(value)
        )
    }

    /// Looks up the entry at `key` and JSON-decodes its `value` blob as
    /// `Value`. Returns `nil` for a genuine miss; throws `Error.readFailed` if
    /// SQLite rejects the read, or a `DecodingError` if the stored bytes
    /// don't decode as `Value`. The original `storageDate` and `metadata`
    /// from the entry are returned alongside the decoded value so callers
    /// that need cache-freshness metadata don't have to fall back to the
    /// base `get`.
    func get<Value: Decodable>(
        key: String,
        as valueType: Value.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> (storageDate: Date, metadata: Data, value: Value)? {
        guard let entry = try self.get(key: key) else { return nil }
        let value = try decoder.decode(Value.self, from: entry.value)
        return (entry.storageDate, entry.metadata, value)
    }
}
