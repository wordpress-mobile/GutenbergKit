import Foundation

/// A protocol defining a simple key-value storage interface for caching editor data.
///
/// Implementations of this protocol provide persistent or in-memory storage for arbitrary data
/// indexed by string keys. This is used internally by the editor to cache API responses and other data.
public protocol EditorKeyValueCache: Sendable {
    /// Returns all keys currently stored in the cache.
    ///
    /// - Returns: A set of all stored keys.
    /// - Throws: An error if the keys cannot be retrieved.
    func allKeys() throws -> Set<String>

    /// Checks whether data exists for the given key.
    ///
    /// - Parameter key: The key to check.
    /// - Returns: `true` if data exists for this key, `false` otherwise.
    /// - Throws: An error if the check cannot be performed.
    func hasData(for key: String) throws -> Bool

    /// Stores data for the given key.
    ///
    /// If data already exists for this key, it will be overwritten.
    ///
    /// - Parameters:
    ///   - data: The data to store.
    ///   - key: The key to associate with the data.
    /// - Throws: An error if the data cannot be stored.
    func store(data: Data, for key: String) throws

    /// Stores the contents of a file URL for the given key.
    ///
    /// If data already exists for this key, it will be overwritten.
    ///
    /// - Parameters:
    ///   - url: The file URL whose contents should be stored.
    ///   - key: The key to associate with the data.
    /// - Throws: An error if the file cannot be read or the data cannot be stored.
    func store(contentsOf url: URL, for key: String) throws

    /// Removes the data associated with the given key.
    ///
    /// If no data exists for this key, this method does not throw.
    ///
    /// - Parameter key: The key whose data should be removed.
    /// - Throws: An error if the data cannot be removed.
    func remove(key: String) throws

    /// Retrieves the data associated with the given key.
    ///
    /// - Parameter key: The key to look up.
    /// - Returns: The stored data, or `nil` if no data exists for this key.
    /// - Throws: An error if the data cannot be retrieved.
    func data(for key: String) throws -> Data?

    /// Removes all data from the cache.
    ///
    /// - Throws: An error if the cache cannot be cleared.
    func clear() throws
}

/// An in-memory implementation of `EditorKeyValueCache`.
///
/// This cache stores all data in memory and is thread-safe. Data is lost when the
/// process terminates. Useful for testing or temporary caching scenarios.
final class InMemoryKeyValueCache: EditorKeyValueCache, @unchecked Sendable {

    private var cache = [String: Data]()
    private let lock = NSLock()

    public func allKeys() throws -> Set<String> {
        self.lock.withLock { Set(self.cache.keys) }
    }

    public func hasData(for key: String) throws -> Bool {
        self.lock.withLock { self.cache[key] != nil }
    }

    public func store(data: Data, for key: String) throws {
        self.lock.withLock { self.cache[key] = data }
    }

    public func store(contentsOf url: URL, for key: String) throws {
        try self.lock.withLock { self.cache[key] = try Data(contentsOf: url) }
    }

    public func remove(key: String) throws {
        self.lock.withLock { _ = self.cache.removeValue(forKey: key) }
    }

    public func data(for key: String) throws -> Data? {
        self.lock.withLock { self.cache[key] }
    }

    public func clear() throws {
        self.lock.withLock { self.cache = [:] }
    }
}

/// A disk-based implementation of `EditorKeyValueCache`.
///
/// This cache persists data to the file system, with each key stored as a separate file
/// in the specified root directory. Data survives process termination and device restarts.
public struct DiskKeyValueCache: EditorKeyValueCache {

    private let rootDirectory: URL

    /// Creates a new disk-based cache.
    ///
    /// - Parameter rootDirectory: The directory where cache files will be stored.
    ///   The directory will be created if it doesn't exist.
    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public func allKeys() throws -> Set<String> {
        guard FileManager.default.directoryExists(at: rootDirectory) else {
            return []
        }

        let allKeys = try FileManager.default.contentsOfDirectory(atPath: rootDirectory.path()).sorted()

        return Set(allKeys)
    }

    public func hasData(for key: String) throws -> Bool {
        FileManager.default.fileExists(at: filePath(for: key))
    }

    public func store(data: Data, for key: String) throws {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try data.write(to: filePath(for: key), options: .atomic)
    }

    public func store(contentsOf url: URL, for key: String) throws {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let newPath = filePath(for: key)

        if FileManager.default.fileExists(at: newPath) {
            try FileManager.default.removeItem(at: newPath)
        }
        try FileManager.default.copyItem(at: url, to: newPath)
    }

    public func remove(key: String) throws {
        let filePath = filePath(for: key)
        guard FileManager.default.fileExists(at: filePath) else {
            return
        }
        try FileManager.default.removeItem(at: filePath)
    }

    public func data(for key: String) throws -> Data? {
        let filePath = filePath(for: key)
        guard FileManager.default.fileExists(at: filePath) else {
            return nil
        }

        return try Data(contentsOf: filePath)
    }

    public func clear() throws {
        guard FileManager.default.directoryExists(at: rootDirectory) else {
            return
        }

        for filename in try FileManager.default.contentsOfDirectory(atPath: rootDirectory.path()) {
            try FileManager.default.removeItem(at: rootDirectory.appending(path: filename))
        }
    }

    /// Returns the file path for a given cache key.
    ///
    /// - Parameter key: The cache key.
    /// - Returns: The URL where the key's data is stored.
    private func filePath(for key: String) -> URL {
        rootDirectory.appending(path: key)
    }
}
