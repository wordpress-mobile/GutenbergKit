import Foundation
import Testing

/// Verifies the assumption behind `DefaultMediaUploader.performUpload`'s
/// `defer { request.httpBodyStream?.close() }`: closing the input side of a bound
/// stream pair unblocks a writer that is blocked on a full output buffer. Without
/// that, a consumer (URLSession) that abandons the body stream on cancel/failure
/// without draining it would leave the background writer thread blocked forever,
/// leaking the thread and its open file handle.
@Suite("Bound Stream Teardown")
struct BoundStreamTeardownTests {

    @Test("closing the input stream unblocks a blocked bound-pair writer")
    func closingInputUnblocksBlockedWriter() throws {
        var readStream: InputStream?
        var writeStream: OutputStream?
        Stream.getBoundStreams(withBufferSize: 1024, inputStream: &readStream, outputStream: &writeStream)
        let input = try #require(readStream)
        let output = try #require(writeStream)
        input.open()
        output.open()

        let exited = DispatchSemaphore(value: 0)
        // OutputStream is not Sendable; only the writer thread touches it after this.
        nonisolated(unsafe) let out = output
        Thread.detachNewThread {
            // Write far more than the 1 KB buffer with nobody reading the input —
            // once the buffer fills, `write` blocks (backpressure).
            let chunk = [UInt8](repeating: 0, count: 256 * 1024)
            chunk.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                var written = 0
                while written < chunk.count {
                    let result = out.write(base + written, maxLength: chunk.count - written)
                    if result <= 0 { break }
                    written += result
                }
            }
            out.close()
            exited.signal()
        }

        // The writer should be blocked on the full buffer (nothing is reading).
        #expect(exited.wait(timeout: .now() + .milliseconds(300)) == .timedOut)

        // Closing the input breaks the pair; the blocked `write` should fail and the
        // writer thread should unwind and exit.
        input.close()
        #expect(exited.wait(timeout: .now() + .seconds(3)) == .success)
    }
}
