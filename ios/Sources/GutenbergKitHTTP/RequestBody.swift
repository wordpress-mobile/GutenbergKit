import Foundation

/// Process-wide registry of temp files currently backing an in-flight request.
///
/// ``HTTPServer/cleanOrphanedTempFiles(in:)`` runs a delete-all sweep of a
/// server's temp directory on start to reclaim files orphaned by a crash. Two
/// server instances that share a name share that directory (e.g. two editors
/// open at once, or one being torn down as another starts), so the sweep would
/// otherwise delete the other instance's live buffers. Registering a file here
/// while it is in use makes the sweep skip it; files not registered are crash
/// orphans (no live owner in this process) and are removed.
///
/// Keyed by file name (a unique UUID), which is stable however the directory is
/// later enumerated.
enum ActiveTempFiles {
    private static let lock = NSLock()
    // Guarded by `lock` on every access.
    nonisolated(unsafe) private static var names = Set<String>()

    static func register(_ name: String) { lock.withLock { _ = names.insert(name) } }
    static func unregister(_ name: String) { lock.withLock { _ = names.remove(name) } }
    static func contains(_ name: String) -> Bool { lock.withLock { names.contains(name) } }
}

/// Reference-counted owner for a temporary file.
///
/// The file is deleted when the last reference is released. This allows
/// ``RequestBody`` (a value type) to share ownership of a temp file across
/// copies — including multipart part bodies that reference byte ranges within
/// the same file. While owned, the file is registered in ``ActiveTempFiles`` so
/// a concurrent server's orphan sweep won't delete it.
final class TempFileOwner: Sendable {
    let url: URL
    init(url: URL) {
        self.url = url
        ActiveTempFiles.register(url.lastPathComponent)
    }
    deinit {
        ActiveTempFiles.unregister(url.lastPathComponent)
        try? FileManager.default.removeItem(at: url)
    }
}

/// An HTTP request body with stream semantics.
///
/// `RequestBody` abstracts over the underlying storage (in-memory data or a file on disk)
/// and provides uniform access regardless of backing:
/// - **Stream access**: Use ``makeInputStream()`` to read without loading everything into memory.
/// - **Materialized access**: Use ``data`` to get the full contents. For file-backed bodies,
///   this reads the entire file into memory.
public struct RequestBody: Sendable, Equatable {

    enum Storage: Sendable, Equatable {
        case data(Data)
        case file(URL)
        case fileSlice(url: URL, offset: UInt64, length: Int)
    }

    let storage: Storage

    /// Retains the backing file for parser-created bodies.
    /// Ignored in equality comparisons.
    private let _owner: TempFileOwner?

    public static func == (lhs: RequestBody, rhs: RequestBody) -> Bool {
        lhs.storage == rhs.storage
    }

    /// Creates a body backed by in-memory data.
    public init(data: Data) {
        self.storage = .data(data)
        self._owner = nil
    }

    /// Creates a body backed by a file on disk.
    ///
    /// The caller is responsible for ensuring the file exists for the lifetime of the body.
    public init(fileURL: URL) {
        self.storage = .file(fileURL)
        self._owner = nil
    }

    /// Creates a body backed by a byte range within a file on disk.
    ///
    /// The bytes are not read until ``makeInputStream()`` is called, keeping the
    /// representation lightweight for use cases like multipart part bodies.
    init(fileURL: URL, offset: UInt64, length: Int) {
        self.storage = .fileSlice(url: fileURL, offset: offset, length: length)
        self._owner = nil
    }

    /// Creates a body backed by an owned temporary file.
    ///
    /// The file is automatically deleted when the last `RequestBody` referencing it
    /// (including multipart part bodies derived from it) is released.
    init(ownedFileURL: URL) {
        self.storage = .file(ownedFileURL)
        self._owner = TempFileOwner(url: ownedFileURL)
    }

    /// Creates a body backed by a byte range within a file, sharing ownership
    /// with the source body's temp file.
    init(fileURL: URL, offset: UInt64, length: Int, owner: TempFileOwner?) {
        self.storage = .fileSlice(url: fileURL, offset: offset, length: length)
        self._owner = owner
    }

    /// The temp file owner, if any. Used to propagate ownership to derived bodies
    /// (e.g., multipart part slices).
    var fileOwner: TempFileOwner? { _owner }

    /// The number of bytes in the body.
    ///
    /// For in-memory and file-slice bodies this is O(1). For file-backed bodies
    /// this queries the file system without reading any data.
    public var count: Int {
        switch storage {
        case .data(let data):
            return data.count
        case .file(let url):
            return (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        case .fileSlice(_, _, let length):
            return length
        }
    }

    /// The file URL backing this body, or `nil` for in-memory bodies.
    public var fileURL: URL? {
        switch storage {
        case .data: return nil
        case .file(let url), .fileSlice(let url, _, _): return url
        }
    }

    /// The byte offset within the backing file where this body begins.
    /// Returns 0 for in-memory and whole-file bodies.
    public var fileOffset: UInt64 {
        switch storage {
        case .fileSlice(_, let offset, _): return offset
        default: return 0
        }
    }

    /// The in-memory data backing this body, or `nil` for file-backed bodies.
    ///
    /// Unlike ``data``, this does **not** read from disk.
    public var inMemoryData: Data? {
        switch storage {
        case .data(let data): return data
        default: return nil
        }
    }

    /// The full body contents as `Data`.
    ///
    /// For in-memory bodies this returns the data directly. For file-backed
    /// bodies the file is read on a background thread to avoid blocking.
    ///
    /// You should almost always use `InputStream` instead.
    public var data: Data {
        get async throws {
            switch storage {
            case .data(let data):
                return data
            case .file(let url):
                return try Data(contentsOf: url)
            case .fileSlice(let url, let offset, let length):
                return try FileHandle.withReadHandle(forUrl: url) {
                    try $0.seek(toOffset: offset)
                    return try $0.read(upToCount: length) ?? Data()
                }
            }
        }
    }

    /// Creates an `InputStream` for reading the body contents.
    ///
    /// For file-slice bodies, a bound stream pair is used instead of subclassing
    /// `InputStream`. Subclassing `InputStream` with `super.init(data:)` triggers
    /// Foundation's class cluster design, causing `URLSession` to read from the
    /// empty superclass `Data` instead of the overridden `read(_:maxLength:)`.
    /// The bound stream pair avoids this because `Stream.getBoundStreams` returns
    /// a native `InputStream` that `URLSession` handles correctly.
    ///
    /// - Throws: A `CocoaError` if the backing file does not exist, is not readable, or is a directory.
    public func makeInputStream() throws -> InputStream {
        switch storage {
        case .data(let data):
            return InputStream(data: data)
        case .file(let url):
            return try Self.openFileStream(url: url)
        case .fileSlice(let url, let offset, let length):
            return try Self.makePipedFileSliceStream(url: url, offset: offset, length: length)
        }
    }

    /// Reads the entire body contents into memory and returns the data along with the
    /// file offset at which the data begins (0 for in-memory bodies).
    ///
    /// This is intended for scanning operations (e.g., multipart boundary detection)
    /// where the full body must be examined. The caller should release the returned
    /// `Data` as soon as scanning is complete.
    func readAllData() throws -> (Data, UInt64) {
        return switch storage {
        case .data(let data): (data, 0)
        case .file(let url): try (Data(contentsOf: url), 0)
        case .fileSlice(let url, let offset, let length):
            try FileHandle.withReadHandle(forUrl: url) {
                try $0.seek(toOffset: offset)
                return (try $0.read(upToCount: length) ?? Data(), offset)
            }
        }
    }

    /// Creates an `InputStream` backed by a bound stream pair that reads a byte
    /// range from a file on a background thread.
    ///
    /// The writer thread reads chunks from the file and pushes them into the
    /// `OutputStream` end of the pair. The returned `InputStream` is a native
    /// Foundation stream that `URLSession` and other consumers handle correctly.
    /// Backpressure is automatic: `OutputStream.write` blocks when the internal
    /// buffer is full.
    private static func makePipedFileSliceStream(url: URL, offset: UInt64, length: Int) throws -> InputStream {
        guard length > 0 else {
            return InputStream(data: Data())
        }

        let fileHandle = try FileHandle(forReadingFrom: url)
        try fileHandle.seek(toOffset: offset)

        var readStream: InputStream?
        var writeStream: OutputStream?
        Stream.getBoundStreams(withBufferSize: 65_536, inputStream: &readStream, outputStream: &writeStream)

        guard let inputStream = readStream, let outputStream = writeStream else {
            try? fileHandle.close()
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }

        outputStream.open()

        // OutputStream is not Sendable but is safely transferred to the
        // writer thread — only the thread accesses it after this point.
        nonisolated(unsafe) let output = outputStream

        Thread.detachNewThread {
            defer {
                output.close()
                try? fileHandle.close()
            }

            var remaining = length
            while remaining > 0 {
                let chunkSize = min(65_536, remaining)
                guard let chunk = try? fileHandle.read(upToCount: chunkSize),
                      !chunk.isEmpty else {
                    break
                }

                var written = 0
                chunk.withUnsafeBytes { buffer in
                    guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                    while written < chunk.count {
                        let result = output.write(base.advanced(by: written), maxLength: chunk.count - written)
                        if result <= 0 { return }
                        written += result
                    }
                }

                if written < chunk.count { break }
                remaining -= chunk.count
            }
        }

        return inputStream
    }

    private static func openFileStream(url: URL) throws -> InputStream {
        let path = url.path
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: path])
        }

        guard !isDirectory.boolValue else {
            throw CocoaError(.fileReadInvalidFileName, userInfo: [NSFilePathErrorKey: path])
        }

        guard FileManager.default.isReadableFile(atPath: path) else {
            throw CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: path])
        }

        guard let stream = InputStream(url: url) else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: path])
        }

        return stream
    }
}
