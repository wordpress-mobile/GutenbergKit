import Foundation
import SQLite3
import Testing

@testable import GutenbergKit

@Suite
struct SQLiteKVCacheTests {

    private func makeStore(diskCapacity: Int = 0) -> SQLiteKVCache {
        SQLiteKVCache(handle: "test", directory: .randomTemporaryDirectory, diskCapacity: diskCapacity)
    }

    private let referenceDate = Date(timeIntervalSinceReferenceDate: 0)

    // MARK: - Round-trip

    @Test("put and get round-trips a value with metadata")
    func putGetRoundTrip() throws {
        let store = makeStore()
        try store.put(key: "k", storageDate: referenceDate, metadata: Data("meta"), value: Data("hello"))

        let entry = try #require(try store.get(key: "k"))
        #expect(entry.value == Data("hello"))
        #expect(entry.metadata == Data("meta"))
        #expect(entry.storageDate == referenceDate)
    }

    @Test("get returns nil for a missing key")
    func getMissingKey() throws {
        let store = makeStore()
        #expect(try store.get(key: "missing") == nil)
    }

    @Test("put overwrites the existing entry for the same key")
    func putOverwrites() throws {
        let store = makeStore()
        try store.put(key: "k", storageDate: referenceDate, metadata: Data(), value: Data("first"))
        try store.put(key: "k", storageDate: referenceDate.addingTimeInterval(60), metadata: Data("new"), value: Data("second"))

        let entry = try #require(try store.get(key: "k"))
        #expect(entry.value == Data("second"))
        #expect(entry.metadata == Data("new"))
        #expect(entry.storageDate == referenceDate.addingTimeInterval(60))
    }

    @Test("clear removes all entries")
    func clearRemovesAll() throws {
        let store = makeStore()
        try store.put(key: "a", storageDate: referenceDate, metadata: Data(), value: Data("A"))
        try store.put(key: "b", storageDate: referenceDate, metadata: Data(), value: Data("B"))
        try store.clear()
        #expect(try store.get(key: "a") == nil)
        #expect(try store.get(key: "b") == nil)
    }

    @Test("delete removes the entry at key and leaves others alone")
    func deleteRemovesOne() throws {
        let store = makeStore()
        try store.put(key: "a", storageDate: referenceDate, metadata: Data(), value: Data("A"))
        try store.put(key: "b", storageDate: referenceDate, metadata: Data(), value: Data("B"))
        try store.delete(key: "a")
        #expect(try store.get(key: "a") == nil)
        #expect(try store.get(key: "b")?.value == Data("B"))
    }

    @Test("delete on a missing key is a no-op")
    func deleteMissingKey() throws {
        let store = makeStore()
        try store.put(key: "kept", storageDate: referenceDate, metadata: Data(), value: Data("ok"))
        try store.delete(key: "never-existed")
        // Existing entries unaffected.
        #expect(try store.get(key: "kept")?.value == Data("ok"))
    }

    @Test("distinct keys are independent")
    func distinctKeysIndependent() throws {
        let store = makeStore()
        try store.put(key: "a", storageDate: referenceDate, metadata: Data(), value: Data("A"))
        try store.put(key: "b", storageDate: referenceDate, metadata: Data(), value: Data("B"))
        #expect(try #require(try store.get(key: "a")).value == Data("A"))
        #expect(try #require(try store.get(key: "b")).value == Data("B"))
    }

    @Test("empty value and empty metadata round-trip")
    func emptyBlobsRoundTrip() throws {
        let store = makeStore()
        try store.put(key: "empty", storageDate: referenceDate, metadata: Data(), value: Data())
        let entry = try #require(try store.get(key: "empty"))
        #expect(entry.value == Data())
        #expect(entry.metadata == Data())
    }

    // MARK: - Persistence

    @Test("entries persist across instances against the same directory and handle")
    func persistsAcrossInstances() throws {
        let directory = URL.randomTemporaryDirectory
        let first = SQLiteKVCache(handle: "test", directory: directory, diskCapacity: 0)
        try first.put(key: "durable", storageDate: referenceDate, metadata: Data("m"), value: Data("v"))

        let reopened = SQLiteKVCache(handle: "test", directory: directory, diskCapacity: 0)
        let entry = try #require(try reopened.get(key: "durable"))
        #expect(entry.value == Data("v"))
        #expect(entry.metadata == Data("m"))
    }

    @Test("different handles in the same directory are independent stores")
    func handlesIndependentInSameDirectory() throws {
        let directory = URL.randomTemporaryDirectory
        let storeA = SQLiteKVCache(handle: "A", directory: directory, diskCapacity: 0)
        let storeB = SQLiteKVCache(handle: "B", directory: directory, diskCapacity: 0)

        try storeA.put(key: "shared-key", storageDate: referenceDate, metadata: Data(), value: Data("from A"))
        try storeB.put(key: "shared-key", storageDate: referenceDate, metadata: Data(), value: Data("from B"))

        #expect(try storeA.get(key: "shared-key")?.value == Data("from A"))
        #expect(try storeB.get(key: "shared-key")?.value == Data("from B"))
    }

    // MARK: - Eviction (oldest-first by storage_date)

    @Test("entries within capacity are not evicted")
    func underCapacityKeepsAll() throws {
        let store = makeStore(diskCapacity: 10 * 1024)
        try store.put(key: "a", storageDate: referenceDate, metadata: Data(), value: Data(repeating: 0xAA, count: 100))
        try store.put(key: "b", storageDate: referenceDate.addingTimeInterval(1), metadata: Data(), value: Data(repeating: 0xBB, count: 100))
        #expect(try store.get(key: "a") != nil)
        #expect(try store.get(key: "b") != nil)
    }

    @Test("oldest entries are evicted when capacity is exceeded")
    func evictsOldestOverCapacity() throws {
        // 600-byte cap. Each entry is 300 bytes (300-byte value + empty metadata).
        // Two fit; the third forces eviction of the oldest by storage_date.
        let store = makeStore(diskCapacity: 600)
        try store.put(key: "oldest", storageDate: referenceDate, metadata: Data(), value: Data(repeating: 0x11, count: 300))
        try store.put(key: "middle", storageDate: referenceDate.addingTimeInterval(100), metadata: Data(), value: Data(repeating: 0x22, count: 300))
        try store.put(key: "newest", storageDate: referenceDate.addingTimeInterval(200), metadata: Data(), value: Data(repeating: 0x33, count: 300))

        #expect(try store.get(key: "oldest") == nil)
        #expect(try store.get(key: "middle") != nil)
        #expect(try store.get(key: "newest") != nil)
    }

    @Test("diskCapacity of 0 disables eviction")
    func zeroCapacityDisablesEviction() throws {
        let store = makeStore(diskCapacity: 0)
        try store.put(key: "a", storageDate: referenceDate, metadata: Data(), value: Data(repeating: 0x11, count: 4096))
        try store.put(key: "b", storageDate: referenceDate.addingTimeInterval(1), metadata: Data(), value: Data(repeating: 0x22, count: 4096))
        #expect(try store.get(key: "a") != nil)
        #expect(try store.get(key: "b") != nil)
    }

    @Test("eviction breaks ties deterministically when storage dates are equal")
    func evictionTiebreaker() throws {
        // 700-byte cap; each entry is 300 bytes. Two same-dated entries plus a
        // newer one forces eviction. The newer entry survives; exactly one of
        // the tied entries is evicted by the hash-DESC tiebreaker (we don't
        // pin which one — the underlying ordering is on SHA-256 digests).
        let store = makeStore(diskCapacity: 700)
        try store.put(key: "a", storageDate: referenceDate, metadata: Data(), value: Data(repeating: 0x01, count: 300))
        try store.put(key: "z", storageDate: referenceDate, metadata: Data(), value: Data(repeating: 0x02, count: 300))
        try store.put(key: "newer", storageDate: referenceDate.addingTimeInterval(1), metadata: Data(), value: Data(repeating: 0x03, count: 300))

        #expect(try store.get(key: "newer") != nil)
        let aSurvives = try store.get(key: "a") != nil
        let zSurvives = try store.get(key: "z") != nil
        #expect(aSurvives != zSurvives, "exactly one of the tied entries should survive")
    }

    @Test("an entry larger than diskCapacity is silently dropped on store")
    func oversizedEntryNotStored() throws {
        // Such an entry couldn't survive the eviction sweep, so put short-circuits
        // and skips the write entirely. The observable contract is the same: the
        // entry is not in the store afterwards. Other entries are unaffected.
        let store = makeStore(diskCapacity: 300)
        try store.put(key: "fits", storageDate: referenceDate, metadata: Data(), value: Data("ok"))
        try store.put(key: "big", storageDate: referenceDate.addingTimeInterval(1), metadata: Data(), value: Data(repeating: 0x42, count: 400))

        #expect(try store.get(key: "big") == nil)
        #expect(try store.get(key: "fits")?.value == Data("ok"))
    }

    // MARK: - Key edge cases
    //
    // Keys are SHA-256 hashed before being bound to SQLite, so most "weird key"
    // concerns (SQL escaping, encoding, embedded nulls, length limits) collapse
    // to "does the hash function distinguish these inputs?" These tests pin the
    // round-trip property — that distinct inputs map to distinct entries —
    // across input shapes that would otherwise have been hazardous if keys were
    // bound verbatim.

    @Test("SQL-shaped keys round-trip without affecting other entries")
    func keysWithSQLSpecialCharacters() throws {
        let store = makeStore()
        let evilKey = "'; DROP TABLE entries; --"
        try store.put(key: evilKey, storageDate: referenceDate, metadata: Data(), value: Data("ok"))

        let entry = try #require(try store.get(key: evilKey))
        #expect(entry.value == Data("ok"))

        try store.put(key: "normal", storageDate: referenceDate, metadata: Data(), value: Data("normal value"))
        #expect(try store.get(key: "normal")?.value == Data("normal value"))
    }

    @Test("unicode and emoji keys round-trip correctly")
    func unicodeKeys() throws {
        let store = makeStore()
        let unicodeKey = "café-日本語-🎉"
        try store.put(key: unicodeKey, storageDate: referenceDate, metadata: Data(), value: Data("unicode value"))

        let entry = try #require(try store.get(key: unicodeKey))
        #expect(entry.value == Data("unicode value"))
    }

    @Test("keys differing only by an embedded null byte don't collide")
    func keysWithEmbeddedNullBytes() throws {
        let store = makeStore()
        // The hash of "abc\0def" differs from the hash of "abc" — the byte
        // sequence is what's hashed, not a C-string view of it.
        let nullKey = "abc\0def"
        let collidingKey = "abc"

        try store.put(key: nullKey, storageDate: referenceDate, metadata: Data(), value: Data("with null"))
        try store.put(key: collidingKey, storageDate: referenceDate, metadata: Data(), value: Data("without null"))

        #expect(try #require(try store.get(key: nullKey)).value == Data("with null"))
        #expect(try #require(try store.get(key: collidingKey)).value == Data("without null"))
    }

    // MARK: - Error messages

    @Test("Error.writeFailed renders sqlite3_errstr description")
    func writeFailedErrorDescription() {
        let err = SQLiteKVCache.Error.writeFailed(sqliteCode: 13)  // SQLITE_FULL
        // Description and localizedDescription both come through the same hook.
        #expect(err.description.contains("disk"))
        #expect(err.description.contains("(code 13)"))
        #expect(err.localizedDescription == err.description)
    }

    @Test("Error.databaseUnavailable renders a description")
    func databaseUnavailableErrorDescription() {
        let err = SQLiteKVCache.Error.databaseUnavailable
        #expect(!err.description.isEmpty)
        #expect(err.localizedDescription == err.description)
    }

    // MARK: - Handle validation

    @Test("isValidHandle accepts ordinary filename components")
    func isValidHandleAccepts() {
        #expect(SQLiteKVCache.isValidHandle("editorurlcache"))
        #expect(SQLiteKVCache.isValidHandle("foo-bar_baz"))
        #expect(SQLiteKVCache.isValidHandle("v1.0"))
        #expect(SQLiteKVCache.isValidHandle("a"))
    }

    @Test("isValidHandle rejects empty, directory references, and unsafe characters")
    func isValidHandleRejects() {
        #expect(!SQLiteKVCache.isValidHandle(""))
        #expect(!SQLiteKVCache.isValidHandle("."))
        #expect(!SQLiteKVCache.isValidHandle(".."))
        #expect(!SQLiteKVCache.isValidHandle("foo/bar"))
        #expect(!SQLiteKVCache.isValidHandle("foo bar"))
        #expect(!SQLiteKVCache.isValidHandle("foo!bar"))
        // Uppercase fails — the assert in init runs after lowercasing,
        // but the validator itself is strict.
        #expect(!SQLiteKVCache.isValidHandle("Foo"))
        // Non-ASCII fails.
        #expect(!SQLiteKVCache.isValidHandle("café"))
        #expect(!SQLiteKVCache.isValidHandle("東京"))
    }

    @Test("init lowercases the handle before using it as a filename")
    func initLowercasesHandle() throws {
        let directory = URL.randomTemporaryDirectory
        // Two stores with handles that differ only by case end up at the same
        // file — the second open finds the first's data.
        let mixedCase = SQLiteKVCache(handle: "EditorURLCache", directory: directory, diskCapacity: 0)
        try mixedCase.put(key: "k", storageDate: referenceDate, metadata: Data(), value: Data("ok"))

        let lowerCase = SQLiteKVCache(handle: "editorurlcache", directory: directory, diskCapacity: 0)
        #expect(try lowerCase.get(key: "k")?.value == Data("ok"))
    }

    // MARK: - Concurrent access

    @Test("survives concurrent put/get from many tasks without crashing or losing data")
    func concurrentAccess() async throws {
        let store = makeStore()
        let iterations = 200
        let distinctKeys = 10

        // Many tasks put and get against overlapping keys. The contract is:
        //   1. SQLite's FULLMUTEX serialization keeps the store from crashing
        //      under concurrent access.
        //   2. Every read returns either nothing or a well-formed value written
        //      by some writer — never a torn / malformed blob.
        // Last-writer-wins is *not* asserted here: under FULLMUTEX, "last writer"
        // depends on FIFO mutex acquisition, which Swift Concurrency doesn't
        // guarantee, and across `Task`s on a cooperative pool the scheduling is
        // intentionally unpredictable.
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    let keyIndex = i % distinctKeys
                    let key = "key-\(keyIndex)"
                    let value = Data("value-\(i)")
                    try store.put(key: key, storageDate: Date().addingTimeInterval(Double(i)), metadata: Data(), value: value)
                    _ = try store.get(key: key)
                }
            }
            try await group.waitForAll()
        }

        // Every key should have *some* well-formed value; we can't pin which
        // exactly because writes race.
        for keyIndex in 0..<distinctKeys {
            let entry = try #require(try store.get(key: "key-\(keyIndex)"))
            #expect(entry.value.starts(with: Data("value-")), "value at key-\(keyIndex) is malformed: \(entry.value)")
        }
    }

    @Test("survives concurrent put/get with eviction firing on most puts")
    func concurrentAccessWithEviction() async throws {
        // Same shape as `concurrentAccess`, but with a small enough cap that
        // eviction fires on most puts. This exercises the eviction-trigger
        // path under contention; the cap-zero case in `concurrentAccess`
        // doesn't install the trigger, so eviction never runs there. Each
        // iteration writes a distinct key so the trigger has rows to choose
        // from rather than UPSERTing the same handful of slots.
        let cap = 5 * 1024
        let valueSize = 1024
        let iterations = 200
        let store = makeStore(diskCapacity: cap)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    let key = "key-\(i)"
                    let value = Data(repeating: UInt8(i % 256), count: valueSize)
                    try store.put(key: key, storageDate: Date().addingTimeInterval(Double(i)), metadata: Data(), value: value)
                    // The just-written entry may already have been evicted by
                    // a later task's put; either outcome is correct here.
                    _ = try store.get(key: key)
                }
            }
            try await group.waitForAll()
        }

        // After all puts settle, every surviving entry is well-formed and the
        // total stored size is at or below the cap. Eviction fires inside the
        // same `AFTER INSERT`/`AFTER UPDATE` trigger as the put, so insert
        // and eviction land or fail as one statement — the cache can't come
        // to rest over-cap.
        var totalSize = 0
        for i in 0..<iterations {
            if let entry = try store.get(key: "key-\(i)") {
                totalSize += entry.value.count + entry.metadata.count
                #expect(entry.value.count == valueSize)
            }
        }
        #expect(totalSize <= cap, "stored size \(totalSize) exceeds cap \(cap)")
    }

    // MARK: - Schema mismatch recovery

    @Test("opens a database with a mismatched schema version by recreating the table")
    func recoversFromSchemaMismatch() throws {
        let directory = URL.randomTemporaryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dbPath = directory.appending(path: "test.sqlite").path(percentEncoded: false)

        // Set up a database with an incompatible schema and a non-matching version.
        var legacyDb: OpaquePointer?
        sqlite3_open_v2(
            dbPath, &legacyDb,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil
        )
        sqlite3_exec(legacyDb, "CREATE TABLE entries (key TEXT, legacy_field TEXT);", nil, nil, nil)
        sqlite3_exec(legacyDb, "INSERT INTO entries (key, legacy_field) VALUES ('legacy', 'data');", nil, nil, nil)
        // Use the maximum possible Int32 as a sentinel so this test stays
        // collision-proof even if `schemaVersion` is bumped to a large value.
        sqlite3_exec(legacyDb, "PRAGMA user_version = \(Int32.max);", nil, nil, nil)
        sqlite3_close(legacyDb)

        // Open via SQLiteKVCache — should detect the version mismatch, drop the
        // legacy table, and recreate the expected schema.
        let store = SQLiteKVCache(handle: "test", directory: directory, diskCapacity: 0)

        // Legacy data is gone.
        #expect(try store.get(key: "legacy") == nil)

        // Store works normally against the recreated schema.
        try store.put(key: "fresh", storageDate: referenceDate, metadata: Data("m"), value: Data("v"))
        let entry = try #require(try store.get(key: "fresh"))
        #expect(entry.value == Data("v"))
        #expect(entry.metadata == Data("m"))
    }

    @Test("a fresh database is initialized at the current schema version")
    func freshDatabaseSchemaSetup() throws {
        // A brand-new SQLite file has `user_version = 0` by default. The open
        // path treats 0 the same as any other "wrong version" — drops the
        // (non-existent) entries table, sets `user_version` to the current
        // `schemaVersion`, and creates the schema. The companion test above
        // covers a non-zero legacy version; this one pins the v0 → current
        // path that every fresh DB takes.
        let directory = URL.randomTemporaryDirectory
        let store = SQLiteKVCache(handle: "test", directory: directory, diskCapacity: 0)

        // Force the lazy open + schema setup by doing any operation. After
        // this, the file exists on disk and the schema setup has run.
        try store.put(key: "k", storageDate: referenceDate, metadata: Data(), value: Data("v"))
        #expect(try store.get(key: "k")?.value == Data("v"))

        // Probe the persisted `user_version` via a separate connection.
        // Pinning the literal `1` matches the `schemaVersion` constant in
        // the source; bumping that constant should trip this assertion as a
        // reminder to think about the migration.
        let dbPath = directory.appending(path: "test.sqlite").path(percentEncoded: false)
        var probe: OpaquePointer?
        #expect(sqlite3_open_v2(dbPath, &probe, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close_v2(probe) }

        var stmt: OpaquePointer?
        sqlite3_prepare_v2(probe, "PRAGMA user_version;", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        sqlite3_step(stmt)
        #expect(sqlite3_column_int(stmt, 0) == 1)
    }

    // MARK: - Pragmas

    @Test("opens the database in WAL journal mode")
    func opensInWALMode() throws {
        let directory = URL.randomTemporaryDirectory
        let store = SQLiteKVCache(handle: "test", directory: directory, diskCapacity: 0)
        // A write triggers the lazy open (which applies the WAL pragma) and
        // materializes the database file on disk so the probe below can see it.
        try store.put(key: "k", storageDate: referenceDate, metadata: Data(), value: Data("ok"))

        // Read journal_mode via a separate connection so we're checking the
        // file's persisted mode, not anything cached on the store's connection.
        let dbPath = directory.appending(path: "test.sqlite").path(percentEncoded: false)
        var probe: OpaquePointer?
        #expect(sqlite3_open_v2(dbPath, &probe, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close_v2(probe) }

        var stmt: OpaquePointer?
        #expect(sqlite3_prepare_v2(probe, "PRAGMA journal_mode;", -1, &stmt, nil) == SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        #expect(sqlite3_step(stmt) == SQLITE_ROW)
        let mode = String(cString: sqlite3_column_text(stmt, 0))
        #expect(mode == "wal")
    }

    // MARK: - Disk reclamation (VACUUM on open)

    @Test("VACUUM on open reclaims free pages after heavy churn")
    func vacuumOnOpenReclaimsFreelist() throws {
        let directory = URL.randomTemporaryDirectory
        let dbPath = directory.appending(path: "test.sqlite").path(percentEncoded: false)
        // ~1 page per entry at SQLite's default 4 KiB page size.
        let pageFiller = Data(repeating: 0xFF, count: 4096)

        // Phase 1: populate, then delete most rows to build up a freelist.
        // Scope the store inside a `do` block so the connection closes (and the
        // WAL is checkpointed against the main file) before the probe below.
        do {
            let store = SQLiteKVCache(handle: "test", directory: directory, diskCapacity: 0)
            for i in 0..<100 {
                try store.put(key: "k-\(i)", storageDate: referenceDate, metadata: Data(), value: pageFiller)
            }
            for i in 0..<95 {
                try store.delete(key: "k-\(i)")
            }
        }

        // Pre-VACUUM sanity: we built a freelist large enough to cross the
        // threshold. If this fails, the test setup needs more entries.
        let beforeFraction = try freelistFraction(at: dbPath)
        #expect(
            beforeFraction > SQLiteKVCache.vacuumFreelistThreshold,
            "test setup did not build a freelist over threshold; got fraction=\(beforeFraction)"
        )

        // Phase 2: reopen — VACUUM should fire during openAndConfigure.
        do {
            let store = SQLiteKVCache(handle: "test", directory: directory, diskCapacity: 0)
            // Force the lazy open + vacuum.
            _ = try store.get(key: "anything")
        }

        // After VACUUM, the freelist is reclaimed.
        let afterFreelist = try probeIntPragma("freelist_count", at: dbPath)
        #expect(afterFreelist == 0, "expected VACUUM to clear freelist; got \(afterFreelist)")
    }

    @Test("VACUUM on open is skipped when freelist is below threshold")
    func vacuumOnOpenSkipsBelowThreshold() throws {
        let directory = URL.randomTemporaryDirectory
        let dbPath = directory.appending(path: "test.sqlite").path(percentEncoded: false)

        // A normal write-only workload — no deletes — leaves the freelist near
        // zero, well below the threshold.
        do {
            let store = SQLiteKVCache(handle: "test", directory: directory, diskCapacity: 0)
            for i in 0..<10 {
                try store.put(key: "k-\(i)", storageDate: referenceDate, metadata: Data(), value: Data("value-\(i)"))
            }
        }

        let pagesBeforeReopen = try probeIntPragma("page_count", at: dbPath)

        // Reopen — VACUUM should be skipped because the freelist is below threshold.
        // We can't directly observe "VACUUM did not run", but we can check that
        // the page count is unchanged (a successful VACUUM almost always shrinks
        // the file by at least a few pages on a non-trivial DB) and that the
        // data round-trips intact.
        do {
            let store = SQLiteKVCache(handle: "test", directory: directory, diskCapacity: 0)
            #expect(try store.get(key: "k-5")?.value == Data("value-5"))
        }

        let pagesAfterReopen = try probeIntPragma("page_count", at: dbPath)
        #expect(
            pagesAfterReopen == pagesBeforeReopen,
            "page_count changed across reopen; VACUUM may have run unexpectedly (\(pagesBeforeReopen) -> \(pagesAfterReopen))"
        )
    }

    /// Reads an integer-valued PRAGMA from `dbPath` via a separate read-only
    /// connection. WAL allows concurrent reads, so this works whether or not
    /// a writer connection is currently live against the file.
    private func probeIntPragma(_ pragma: String, at dbPath: String) throws -> Int32 {
        var probe: OpaquePointer?
        #expect(sqlite3_open_v2(dbPath, &probe, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close_v2(probe) }
        var stmt: OpaquePointer?
        #expect(sqlite3_prepare_v2(probe, "PRAGMA \(pragma);", -1, &stmt, nil) == SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        #expect(sqlite3_step(stmt) == SQLITE_ROW)
        return sqlite3_column_int(stmt, 0)
    }

    private func freelistFraction(at dbPath: String) throws -> Double {
        let freelist = try probeIntPragma("freelist_count", at: dbPath)
        let total = try probeIntPragma("page_count", at: dbPath)
        guard total > 0 else { return 0 }
        return Double(freelist) / Double(total)
    }

    // MARK: - UnitInformationStorage convenience init

    @Test("Measurement-based init forwards the byte count to the designated init")
    func unitInformationStorageInit() throws {
        // 600-byte cap expressed as a Measurement; same eviction behavior as the
        // designated init's `evictsOldestOverCapacity` test.
        let store = SQLiteKVCache(
            handle: "test",
            directory: .randomTemporaryDirectory,
            diskCapacity: Measurement(value: 600, unit: .bytes)
        )
        try store.put(key: "oldest", storageDate: referenceDate, metadata: Data(), value: Data(repeating: 0x11, count: 300))
        try store.put(key: "middle", storageDate: referenceDate.addingTimeInterval(100), metadata: Data(), value: Data(repeating: 0x22, count: 300))
        try store.put(key: "newest", storageDate: referenceDate.addingTimeInterval(200), metadata: Data(), value: Data(repeating: 0x33, count: 300))

        #expect(try store.get(key: "oldest") == nil)
        #expect(try store.get(key: "middle") != nil)
        #expect(try store.get(key: "newest") != nil)
    }

    @Test("Measurement-based init converts non-byte units to bytes")
    func unitInformationStorageInitConvertsUnits() throws {
        // 1 kibibyte == 1024 bytes. A 2000-byte value should be silently dropped
        // (exceeds cap), a 500-byte one should fit. Same short-circuit contract
        // as `oversizedEntryNotStored` but exercising the unit conversion path.
        let store = SQLiteKVCache(
            handle: "test",
            directory: .randomTemporaryDirectory,
            diskCapacity: Measurement(value: 1, unit: .kibibytes)
        )
        try store.put(key: "fits", storageDate: referenceDate, metadata: Data(), value: Data(repeating: 0x01, count: 500))
        try store.put(key: "too-big", storageDate: referenceDate.addingTimeInterval(1), metadata: Data(), value: Data(repeating: 0x02, count: 2000))

        #expect(try store.get(key: "fits")?.value.count == 500)
        #expect(try store.get(key: "too-big") == nil)
    }

    // MARK: - Codable metadata convenience put/get

    private struct SampleMeta: Codable, Equatable {
        let etag: String
        let contentType: String
    }

    @Test("Codable metadata put/get round-trips a value and preserves storageDate and value")
    func codableMetadataRoundTrip() throws {
        let store = makeStore()
        let meta = SampleMeta(etag: "abc123", contentType: "application/json")
        try store.put(key: "k", storageDate: referenceDate, metadata: meta, value: Data("body"))

        let entry = try #require(try store.get(key: "k", metadataAs: SampleMeta.self))
        #expect(entry.metadata == meta)
        #expect(entry.value == Data("body"))
        #expect(entry.storageDate == referenceDate)
    }

    @Test("Codable metadata get returns nil for a missing key")
    func codableMetadataGetMissing() throws {
        let store = makeStore()
        #expect(try store.get(key: "missing", metadataAs: SampleMeta.self) == nil)
    }

    @Test("Codable metadata get throws DecodingError when stored bytes don't match the type")
    func codableMetadataGetMismatchedType() throws {
        // Write raw bytes via the base put, then try to decode them as `SampleMeta`.
        // The convenience get should surface the JSONDecoder error rather than
        // silently returning nil.
        let store = makeStore()
        try store.put(key: "k", storageDate: referenceDate, metadata: Data("not json"), value: Data())
        #expect(throws: DecodingError.self) {
            try store.get(key: "k", metadataAs: SampleMeta.self)
        }
    }

    @Test("Codable metadata put with Data metadata picks the non-generic overload")
    func codableMetadataPutWithDataPrefersNonGeneric() throws {
        // `Data` conforms to `Encodable`, so the generic overload would also
        // match. Swift prefers the non-generic original, which stores the raw
        // bytes — a JSON-encoded `Data` would be a base64 string instead.
        let store = makeStore()
        try store.put(key: "k", storageDate: referenceDate, metadata: Data("raw"), value: Data("v"))
        let entry = try #require(try store.get(key: "k"))
        #expect(entry.metadata == Data("raw"))
    }

    @Test("Codable metadata put accepts a custom encoder")
    func codableMetadataPutWithCustomEncoder() throws {
        let store = makeStore()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let meta = SampleMeta(etag: "z", contentType: "text/plain")
        try store.put(key: "k", storageDate: referenceDate, metadata: meta, value: Data(), encoder: encoder)

        // The bytes should be the deterministically-ordered JSON encoding.
        let entry = try #require(try store.get(key: "k"))
        let expected = try encoder.encode(meta)
        #expect(entry.metadata == expected)
    }
}
