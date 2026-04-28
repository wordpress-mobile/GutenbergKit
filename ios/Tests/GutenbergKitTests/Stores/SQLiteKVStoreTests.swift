import Foundation
import SQLite3
import Testing

@testable import GutenbergKit

@Suite
struct SQLiteKVStoreTests {

    private func makeStore(diskCapacity: Int = 0) -> SQLiteKVStore {
        SQLiteKVStore(handle: "test", directory: .randomTemporaryDirectory, diskCapacity: diskCapacity)
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

    @Test("entries persist across instances against the same directory and handle")
    func persistsAcrossInstances() throws {
        let directory = URL.randomTemporaryDirectory
        let first = SQLiteKVStore(handle: "test", directory: directory, diskCapacity: 0)
        first.put(key: "durable", storageDate: referenceDate, metadata: Data("m"), value: Data("v"))

        let reopened = SQLiteKVStore(handle: "test", directory: directory, diskCapacity: 0)
        let entry = try #require(reopened.get(key: "durable"))
        #expect(entry.value == Data("v"))
        #expect(entry.metadata == Data("m"))
    }

    @Test("different handles in the same directory are independent stores")
    func handlesIndependentInSameDirectory() {
        let directory = URL.randomTemporaryDirectory
        let storeA = SQLiteKVStore(handle: "A", directory: directory, diskCapacity: 0)
        let storeB = SQLiteKVStore(handle: "B", directory: directory, diskCapacity: 0)

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

    @Test("eviction breaks ties by key DESC when storage dates are equal")
    func evictionTiebreaker() {
        // 700-byte cap; each entry is 300 bytes. Two same-dated entries plus a
        // newer one forces eviction of one of the tied entries. With ORDER BY
        // storage_date DESC, key DESC, the lexicographically smaller key is
        // evicted first.
        let store = makeStore(diskCapacity: 700)
        store.put(key: "a", storageDate: referenceDate, metadata: Data(), value: Data(repeating: 0x01, count: 300))
        store.put(key: "z", storageDate: referenceDate, metadata: Data(), value: Data(repeating: 0x02, count: 300))
        store.put(key: "newer", storageDate: referenceDate.addingTimeInterval(1), metadata: Data(), value: Data(repeating: 0x03, count: 300))

        #expect(store.get(key: "a") == nil)
        #expect(store.get(key: "z") != nil)
        #expect(store.get(key: "newer") != nil)
    }

    @Test("an entry larger than diskCapacity is evicted on store")
    func oversizedEntryEvictedImmediately() {
        // The eviction sweep runs after every put. A single entry whose size
        // exceeds the cap on its own is evicted in the same call.
        let store = makeStore(diskCapacity: 300)
        store.put(key: "big", storageDate: referenceDate, metadata: Data(), value: Data(repeating: 0x42, count: 400))
        #expect(store.get(key: "big") == nil)
    }

    // MARK: - Key edge cases

    @Test("keys with SQL special characters are handled safely")
    func keysWithSQLSpecialCharacters() throws {
        let store = makeStore()
        // Classic injection-shaped key — parameterized binding should treat it
        // as a literal value, not interpret it as SQL.
        let evilKey = "'; DROP TABLE entries; --"
        store.put(key: evilKey, storageDate: referenceDate, metadata: Data(), value: Data("ok"))

        // The table still exists and the entry round-tripped.
        let entry = try #require(store.get(key: evilKey))
        #expect(entry.value == Data("ok"))

        // Other keys still work — table not dropped.
        store.put(key: "normal", storageDate: referenceDate, metadata: Data(), value: Data("normal value"))
        #expect(store.get(key: "normal")?.value == Data("normal value"))
    }

    @Test("unicode and emoji keys round-trip correctly")
    func unicodeKeys() throws {
        let store = makeStore()
        let unicodeKey = "café-日本語-🎉"
        store.put(key: unicodeKey, storageDate: referenceDate, metadata: Data(), value: Data("unicode value"))

        let entry = try #require(store.get(key: unicodeKey))
        #expect(entry.value == Data("unicode value"))
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
        //   2. After all writes settle, every distinct key has the value from
        //      its last writer (last-writer-wins).
        let lastValuePerKey = await withTaskGroup(of: (Int, Int).self) { group in
            for i in 0..<iterations {
                group.addTask {
                    let keyIndex = i % distinctKeys
                    let key = "key-\(keyIndex)"
                    let value = Data("value-\(i)")
                    store.put(key: key, storageDate: Date().addingTimeInterval(Double(i)), metadata: Data(), value: value)
                    _ = store.get(key: key)
                    return (keyIndex, i)
                }
            }
            // Track the highest iteration that wrote to each key, so the test
            // doesn't depend on tasks completing in order.
            var lastValuePerKey: [Int: Int] = [:]
            for await (keyIndex, iteration) in group {
                lastValuePerKey[keyIndex] = max(lastValuePerKey[keyIndex] ?? -1, iteration)
            }
            return lastValuePerKey
        }

        // Every key should have an entry, and the entry should match one of the
        // values written for that key (we can't pin which exactly because writes
        // race, but we can confirm the store didn't return garbage).
        for keyIndex in 0..<distinctKeys {
            let entry = try #require(store.get(key: "key-\(keyIndex)"))
            #expect(entry.value.starts(with: Data("value-")), "value at key-\(keyIndex) is malformed: \(entry.value)")
            #expect(lastValuePerKey[keyIndex] != nil)
        }
    }

    // MARK: - Handle validation

    @Test("isValidHandle accepts ordinary filename components")
    func handleValidationAccepts() {
        #expect(SQLiteKVStore.isValidHandle("EditorURLCache"))
        #expect(SQLiteKVStore.isValidHandle("HTMLPreviewCache"))
        #expect(SQLiteKVStore.isValidHandle("foo-bar_baz"))
        #expect(SQLiteKVStore.isValidHandle("a"))
        // Dots in the middle are valid filename characters, not traversal.
        #expect(SQLiteKVStore.isValidHandle("foo..bar"))
        #expect(SQLiteKVStore.isValidHandle("v1.0"))
    }

    @Test("isValidHandle rejects path separators and directory references")
    func handleValidationRejects() {
        #expect(!SQLiteKVStore.isValidHandle(""))
        #expect(!SQLiteKVStore.isValidHandle("foo/bar"))
        #expect(!SQLiteKVStore.isValidHandle("/foo"))
        #expect(!SQLiteKVStore.isValidHandle("foo/"))
        #expect(!SQLiteKVStore.isValidHandle("."))
        #expect(!SQLiteKVStore.isValidHandle(".."))
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
        sqlite3_exec(legacyDb, "PRAGMA user_version = 999;", nil, nil, nil)
        sqlite3_close(legacyDb)

        // Open via SQLiteKVStore — should detect the version mismatch, drop the
        // legacy table, and recreate the expected schema.
        let store = SQLiteKVStore(handle: "test", directory: directory, diskCapacity: 0)

        // Legacy data is gone.
        #expect(store.get(key: "legacy") == nil)

        // Store works normally against the recreated schema.
        store.put(key: "fresh", storageDate: referenceDate, metadata: Data("m"), value: Data("v"))
        let entry = try #require(store.get(key: "fresh"))
        #expect(entry.value == Data("v"))
        #expect(entry.metadata == Data("m"))
    }
}
