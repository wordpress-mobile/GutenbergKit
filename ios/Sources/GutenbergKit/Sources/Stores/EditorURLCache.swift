import CryptoKit
import Foundation
import OSLog

/// A URL-based cache for storing HTTP responses keyed by URL and HTTP method.
///
/// Responses are stored on disk and survive process termination. Responses are keyed
/// by both URL and HTTP method, so GET and OPTIONS requests to the same URL are
/// stored independently.
///
/// Backed by a synchronous, file-per-entry layout under `cacheRoot`. Each entry is a
/// single file whose name is the SHA-256 hex digest of `"<METHOD>:<absoluteURL>"` and
/// whose contents are a small envelope: a 4-byte big-endian metadata length, the
/// JSON-encoded metadata (storage date + headers), then the raw body bytes. Writes
/// are atomic (`Data.write(options: .atomic)`), and `clear()` removes the directory
/// outright — neither operation has the async-flush semantics that `URLCache` does.
public struct EditorURLCache: Sendable {
    private let cacheRoot: URL
    private let cachePolicy: EditorCachePolicy
    private let diskCapacity: Int
    private let performanceMonitor = SignpostMonitor(for: Logger.performance)

    /// Creates a new URL cache.
    ///
    /// - Parameters:
    ///   - cacheRoot: The directory where cached responses will be stored.
    ///     If `nil`, a default location under the system caches directory is used.
    ///   - cachePolicy: The policy that determines when cached responses are
    ///     considered valid.
    ///   - diskCapacity: Soft cap (in bytes) on the combined size of cache entries.
    ///     After every successful store, an opportunistic LRU sweep evicts oldest
    ///     entries (by file mtime) until total entry size is at or below this cap.
    ///     Pass `0` to disable the sweep entirely.
    public init(
        cacheRoot: URL? = nil,
        cachePolicy: EditorCachePolicy = .always,
        diskCapacity: Int = 100 * 1024 * 1024
    ) {
        self.cacheRoot = cacheRoot ?? URL.cachesDirectory.appending(path: "GutenbergKit-EditorURLCache")
        self.cachePolicy = cachePolicy
        self.diskCapacity = diskCapacity
        try? FileManager.default.createDirectory(at: self.cacheRoot, withIntermediateDirectories: true)
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
        try self.writeEntry(
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
        try self.writeEntry(
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
        performanceMonitor.measure { () -> EditorURLResponse? in
            let entryURL = self.entryURL(for: url, httpMethod: httpMethod)
            guard let envelope = try? Data(contentsOf: entryURL),
                  let entry = try? Self.decode(envelope),
                  self.cachePolicy.allowsResponseWith(date: entry.storageDate, currentDate: currentDate)
            else {
                return nil
            }
            return EditorURLResponse(data: entry.body, responseHeaders: entry.headers)
        }
    }

    /// Removes all cached responses.
    public func clear() throws {
        let fm = FileManager.default
        try? fm.removeItem(at: self.cacheRoot)
        try fm.createDirectory(at: self.cacheRoot, withIntermediateDirectories: true)
    }

    // MARK: - Private

    private struct Metadata: Codable {
        let storageDate: Date
        let headers: EditorHTTPHeaders
    }

    private struct Entry {
        let storageDate: Date
        let headers: EditorHTTPHeaders
        let body: Data
    }

    private enum DecodeError: Error { case malformed }

    private func writeEntry(
        body: Data,
        headers: EditorHTTPHeaders,
        url: URL,
        httpMethod: EditorHttpMethod,
        currentDate: Date
    ) throws {
        let metadata = Metadata(storageDate: currentDate, headers: headers)
        let envelope = try Self.encode(metadata: metadata, body: body)
        let entryURL = self.entryURL(for: url, httpMethod: httpMethod)
        try envelope.write(to: entryURL, options: .atomic)
        self.sweepIfNeeded()
    }

    private func entryURL(for url: URL, httpMethod: EditorHttpMethod) -> URL {
        let key = "\(httpMethod.rawValue):\(url.absoluteString)"
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return self.cacheRoot.appending(path: hex)
    }

    private static func encode(metadata: Metadata, body: Data) throws -> Data {
        let metadataData = try JSONEncoder().encode(metadata)
        var envelope = Data(capacity: 4 + metadataData.count + body.count)
        var lengthBE = UInt32(metadataData.count).bigEndian
        withUnsafeBytes(of: &lengthBE) { envelope.append(contentsOf: $0) }
        envelope.append(metadataData)
        envelope.append(body)
        return envelope
    }

    private static func decode(_ envelope: Data) throws -> Entry {
        guard envelope.count >= 4 else { throw DecodeError.malformed }
        let lengthBytes = envelope.subdata(in: 0..<4)
        let metadataLength = Int(lengthBytes.withUnsafeBytes {
            UInt32(bigEndian: $0.load(as: UInt32.self))
        })
        guard envelope.count >= 4 + metadataLength else { throw DecodeError.malformed }
        let metadataData = envelope.subdata(in: 4..<(4 + metadataLength))
        let body = envelope.subdata(in: (4 + metadataLength)..<envelope.count)
        let metadata = try JSONDecoder().decode(Metadata.self, from: metadataData)
        return Entry(storageDate: metadata.storageDate, headers: metadata.headers, body: body)
    }

    /// Walks the cache directory and evicts the oldest entries (by mtime) until the
    /// total size of recognized entry files is at or below `diskCapacity`. Files that
    /// don't match the 64-char hex key format are ignored, so any foreign files
    /// in `cacheRoot` are left untouched.
    private func sweepIfNeeded() {
        guard self.diskCapacity > 0 else { return }
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let urls = try? fm.contentsOfDirectory(
            at: self.cacheRoot,
            includingPropertiesForKeys: Array(keys)
        ) else {
            return
        }
        var attributes = urls.compactMap { url -> (url: URL, size: Int, mtime: Date)? in
            guard Self.isEntryFilename(url.lastPathComponent),
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  let size = values.fileSize,
                  let mtime = values.contentModificationDate
            else { return nil }
            return (url, size, mtime)
        }
        var totalSize = attributes.reduce(0) { $0 + $1.size }
        guard totalSize > self.diskCapacity else { return }
        attributes.sort { $0.mtime < $1.mtime }
        for entry in attributes {
            try? fm.removeItem(at: entry.url)
            totalSize -= entry.size
            if totalSize <= self.diskCapacity { return }
        }
    }

    private static func isEntryFilename(_ name: String) -> Bool {
        guard name.count == 64 else { return false }
        return name.allSatisfy { $0.isHexDigit }
    }
}
