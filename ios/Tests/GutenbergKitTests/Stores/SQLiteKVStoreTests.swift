import Foundation
import SQLite3
import Testing

@testable import GutenbergKit

@Suite
struct SQLiteKVStoreTests {

    private func makeStore(diskCapacity: Int = 0) -> SQLiteKVStore {
        SQLiteKVStore(directory: .randomTemporaryDirectory, diskCapacity: diskCapacity)
    }

    private let referenceDate = Date(timeIntervalSinceReferenceDate: 0)

    // MARK: - Round-trip

    @Test("put and get round-trips a value with metadata")
    func putGetRoundTrip() throws {
        let store = makeStore()
        store.put(key: "k", storageDate: referenceDate, metadata: Data("meta"), value: Data("hello"))

        let entry = try #require(store.get(key: "k"))
        #expect(entry.value == Data("hello"))
        #expect(entry.metadata == Data("meta"))
        #expect(entry.storageDate == referenceDate)
    }

    @Test("get returns nil for a missing key")
    func getMissingKey() {
        let store = makeStore()
        #expect(store.get(key: "missing") == nil)
    }

    @Test("put overwrites the existing entry for the same key")
    func putOverwrites() throws {
        let store = makeStore()
        store.put(key: "k", storageDate: referenceDate, metadata: Data(), value: Data("first"))
        store.put(key: "k", storageDate: referenceDate.addingTimeInterval(60), metadata: Data("new"), value: Data("second"))

        let entry = try #require(store.get(key: "k"))
        #expect(entry.value == Data("second"))
        #expect(entry.metadata == Data("new"))
        #expect(entry.storageDate == referenceDate.addingTimeInterval(60))
    }

    @Test("clear removes all entries")
    func clearRemovesAll() {
        let store = makeStore()
        store.put(key: "a", storageDate: referenceDate, metadata: Data(), value: Data("A"))
        store.put(key: "b", storageDate: referenceDate, metadata: Data(), value: Data("B"))
        store.clear()
        #expect(store.get(key: "a") == nil)
        #expect(store.get(key: "b") == nil)
    }

    @Test("distinct keys are independent")
    func distinctKeysIndependent() throws {
        let store = makeStore()
        store.put(key: "a", storageDate: referenceDate, metadata: Data(), value: Data("A"))
        store.put(key: "b", storageDate: referenceDate, metadata: Data(), value: Data("B"))
        #expect(try #require(store.get(key: "a")).value == Data("A"))
        #expect(try #require(store.get(key: "b")).value == Data("B"))
    }

    @Test("empty value and empty metadata round-trip")
    func emptyBlobsRoundTrip() throws {
        let store = makeStore()
        store.put(key: "empty", storageDate: referenceDate, metadata: Data(), value: Data())
        let entry = try #require(store.get(key: "empty"))
        #expect(entry.value == Data())
        #expect(entry.metadata == Data())
    }

    // MARK: - Persistence

    @Test("entries persist across instances against the same directory and filename")
    func persistsAcrossInstances() throws {
        let directory = URL.randomTemporaryDirectory
        let first = SQLiteKVStore(directory: directory, diskCapacity: 0)
        first.put(key: "durable", storageDate: referenceDate, metadata: Data("m"), value: Data("v"))

        let reopened = SQLiteKVStore(directory: directory, diskCapacity: 0)
        let entry = try #require(reopened.get(key: "durable"))
        #expect(entry.value == Data("v"))
        #expect(entry.metadata == Data("m"))
    }

    @Test("different filenames in the same directory are independent stores")
    func filenamesIndependentInSameDirectory() {
        let directory = URL.randomTemporaryDirectory
        let storeA = SQLiteKVStore(directory: directory, filename: "A.sqlite", diskCapacity: 0)
        let storeB = SQLiteKVStore(directory: directory, filename: "B.sqlite", diskCapacity: 0)

        storeA.put(key: "shared-key", storageDate: referenceDate, metadata: Data(), value: Data("from A"))
        storeB.put(key: "shared-key", storageDate: referenceDate, metadata: Data(), value: Data("from B"))

        #expect(storeA.get(key: "shared-key")?.value == Data("from A"))
        #expect(storeB.get(key: "shared-key")?.value == Data("from B"))
    }

    // MARK: - LRU eviction

    @Test("entries within capacity are not evicted")
    func underCapacityKeepsAll() {
        let store = makeStore(diskCapacity: 10 * 1024)
        store.put(key: "a", storageDate: referenceDate, metadata: Data(), value: Data(repeating: 0xAA, count: 100))
        store.put(key: "b", storageDate: referenceDate.addingTimeInterval(1), metadata: Data(), value: Data(repeating: 0xBB, count: 100))
        #expect(store.get(key: "a") != nil)
        #expect(store.get(key: "b") != nil)
    }

    @Test("oldest entries are evicted when capacity is exceeded")
    func evictsOldestOverCapacity() {
        // 600-byte cap. Each entry is 300 bytes (300-byte value + empty metadata).
        // Two fit; the third forces eviction of the oldest by storage_date.
        let store = makeStore(diskCapacity: 600)
        store.put(key: "oldest", storageDate: referenceDate, metadata: Data(), value: Data(repeating: 0x11, count: 300))
        store.put(key: "middle", storageDate: referenceDate.addingTimeInterval(100), metadata: Data(), value: Data(repeating: 0x22, count: 300))
        store.put(key: "newest", storageDate: referenceDate.addingTimeInterval(200), metadata: Data(), value: Data(repeating: 0x33, count: 300))

        #expect(store.get(key: "oldest") == nil)
        #expect(store.get(key: "middle") != nil)
        #expect(store.get(key: "newest") != nil)
    }

    @Test("diskCapacity of 0 disables eviction")
    func zeroCapacityDisablesEviction() {
        let store = makeStore(diskCapacity: 0)
        store.put(key: "a", storageDate: referenceDate, metadata: Data(), value: Data(repeating: 0x11, count: 4096))
        store.put(key: "b", storageDate: referenceDate.addingTimeInterval(1), metadata: Data(), value: Data(repeating: 0x22, count: 4096))
        #expect(store.get(key: "a") != nil)
        #expect(store.get(key: "b") != nil)
    }

    // MARK: - Schema mismatch recovery

    @Test("opens a database with a mismatched schema version by recreating the table")
    func recoversFromSchemaMismatch() throws {
        let directory = URL.randomTemporaryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dbPath = directory.appending(path: "Store.sqlite").path(percentEncoded: false)

        // Set up a database with an incompatible schema and a non-matching version.
        var legacyDb: OpaquePointer?
        sqlite3_open_v2(
            dbPath, &legacyDb,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil
        )
        sqlite3_exec(legacyDb, "CREATE TABLE entries (key TEXT, legacy_field TEXT);", nil, nil, nil)
        sqlite3_exec(legacyDb, "INSERT INTO entries (key, legacy_field) VALUES ('legacy', 'data');", nil, nil, nil)
        sqlite3_exec(legacyDb, "PRAGMA user_version = 999;", nil, nil, nil)
        sqlite3_close(legacyDb)

        // Open via SQLiteKVStore — should detect the version mismatch, drop the
        // legacy table, and recreate the expected schema.
        let store = SQLiteKVStore(directory: directory, diskCapacity: 0)

        // Legacy data is gone.
        #expect(store.get(key: "legacy") == nil)

        // Store works normally against the recreated schema.
        store.put(key: "fresh", storageDate: referenceDate, metadata: Data("m"), value: Data("v"))
        let entry = try #require(store.get(key: "fresh"))
        #expect(entry.value == Data("v"))
        #expect(entry.metadata == Data("m"))
    }
}
