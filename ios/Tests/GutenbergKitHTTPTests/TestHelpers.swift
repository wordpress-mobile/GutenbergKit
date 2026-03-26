import Foundation
@testable import GutenbergKitHTTP

/// Reads the full contents of a `RequestBody` by streaming through its `InputStream`.
///
/// Shared across test files that need to verify body data. This version uses
/// `hasBytesAvailable`, which is correct for data-backed and file-backed streams.
/// For bound stream pairs, use a `while true` loop instead (see `ChunkedMultipartTests`).
func readAll(_ body: RequestBody) throws -> Data {
    let stream = try body.makeInputStream()
    stream.open()
    defer { stream.close() }

    var data = Data()
    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    while stream.hasBytesAvailable {
        let bytesRead = stream.read(buffer, maxLength: bufferSize)
        guard bytesRead > 0 else { break }
        data.append(buffer, count: bytesRead)
    }

    return data
}
