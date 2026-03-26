import Foundation

extension FileHandle {

    /// Opens a file for reading, passes the handle to `body`, and guarantees the handle
    /// is closed when `body` returns — whether normally or by throwing.
    ///
    /// ```swift
    /// let data = try FileHandle.withReadHandle(forUrl: fileURL) { handle in
    ///     try handle.seek(toOffset: 100)
    ///     return try handle.read(upToCount: 50) ?? Data()
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - url: The file URL to open for reading.
    ///   - body: A closure that receives the open `FileHandle`.
    /// - Returns: The value returned by `body`.
    /// - Throws: Rethrows any error from opening the file or from `body`.
    static func withReadHandle<T>(forUrl url: URL, _ body: (FileHandle) throws -> T) throws -> T {
        let handle = try FileHandle(forReadingFrom: url)
        // Read-only handle — close errors (EBADF, EINTR) are harmless; no buffered writes to lose.
        defer { try? handle.close() }
        return try body(handle)
    }
}
