import Foundation
import OSLog

/// Feeds a multipart body — a preamble, a file's bytes, then the closing boundary — to
/// the write half of a bound stream pair, as fast as the reader takes it.
///
/// It is driven by the stream's own events on a dispatch queue, not by a thread of its
/// own: it writes when the stream has room and does nothing otherwise. An upload that is
/// waiting for a connection, or for a slow one to drain, costs a 64 KB buffer and an open
/// file, so how many uploads run at once is up to the network. A thread that blocked in
/// `write` for each upload would be a thread per upload instead.
///
/// The closing boundary is **not** written if the file can't be fully read: a read
/// error, or the file ending short of the `fileSize` the caller measured (it shrank
/// since). The request's `Content-Length` reflects that measured size, so a short body
/// can't be dressed up as a complete multipart — the stream ends early, which fails the
/// upload rather than silently corrupting it, and the cause is logged.
final class MultipartBodyWriter: NSObject, StreamDelegate, @unchecked Sendable {
    /// One queue for every writer. Each event is a read of at most one buffer and a write
    /// that doesn't wait, so writers don't hold one another up.
    private static let queue = DispatchQueue(label: "org.wordpress.gutenbergkit.multipart-body")

    // Everything below is touched only on `queue` once `start` has run.
    private let output: OutputStream
    private let fileHandle: FileHandle
    private let preamble: Data
    private let epilogue: Data
    private var preambleSent = 0
    private var fileRemaining: Int
    private var epilogueSent = 0

    /// One buffer for the whole body, refilled in place.
    private let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 65_536, alignment: MemoryLayout<UInt8>.alignment)
    /// The bytes of `buffer` the stream has yet to take.
    private var pending = 0..<0

    private var isFinished = false
    private var completion: (@Sendable (Bool) -> Void)?
    /// A stream doesn't keep its delegate alive, so the writer does, until it finishes.
    private var keepAlive: MultipartBodyWriter?

    init(fileHandle: FileHandle, fileSize: Int, preamble: Data, epilogue: Data, output: OutputStream) {
        self.fileHandle = fileHandle
        self.fileRemaining = fileSize
        self.preamble = preamble
        self.epilogue = epilogue
        self.output = output
    }

    deinit {
        buffer.deallocate()
    }

    /// Starts writing. The writer closes the stream and the file itself when it finishes.
    ///
    /// - Parameter completion: Called once, on the writer's queue, with whether the whole
    ///   body was written.
    func start(completion: (@Sendable (Bool) -> Void)? = nil) {
        self.completion = completion
        keepAlive = self
        output.delegate = self
        CFWriteStreamSetDispatchQueue(output, Self.queue)
        output.open()
    }

    /// Stops writing and lets go of the stream and the file. Does nothing to a writer
    /// that has finished.
    ///
    /// A reader that closes its end of the stream tells the writer so, but one that never
    /// opened it does not, and neither does one that is simply released. Whoever asked
    /// for the body calls this once it is no longer wanted.
    func cancel() {
        Self.queue.async { [self] in
            finish(wroteEverything: false)
        }
    }

    func stream(_ stream: Stream, handle event: Stream.Event) {
        switch event {
        case .hasSpaceAvailable:
            writeNext()
        case .endEncountered, .errorOccurred:
            // The reader has gone.
            finish(wroteEverything: false)
        default:
            break
        }
    }

    /// One write for each event: the stream reports room again once this one is taken.
    private func writeNext() {
        guard !isFinished else { return }
        if pending.isEmpty {
            guard refill() else {
                finish(wroteEverything: false)
                return
            }
        }
        guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
            finish(wroteEverything: false)
            return
        }
        let written = output.write(base.advanced(by: pending.lowerBound), maxLength: pending.count)
        guard written > 0 else {
            finish(wroteEverything: false)
            return
        }
        pending = (pending.lowerBound + written)..<pending.upperBound
        if pending.isEmpty && nothingLeft {
            finish(wroteEverything: true)
        }
    }

    private var nothingLeft: Bool {
        preambleSent == preamble.count && fileRemaining == 0 && epilogueSent == epilogue.count
    }

    /// Puts the body's next bytes in the buffer. `false` if the file could not supply them.
    private func refill() -> Bool {
        if preambleSent < preamble.count {
            preambleSent += fill(from: preamble, at: preambleSent)
            return true
        }
        if fileRemaining > 0 {
            return fillFromFile()
        }
        epilogueSent += fill(from: epilogue, at: epilogueSent)
        return true
    }

    private func fill(from data: Data, at offset: Int) -> Int {
        let count = min(buffer.count, data.count - offset)
        data.copyBytes(to: buffer, from: offset..<(offset + count))
        pending = 0..<count
        return count
    }

    private func fillFromFile() -> Bool {
        // Read straight into the buffer: `FileHandle.read(upToCount:)` would hand back a
        // new autoreleased buffer for every chunk.
        var count = read(fileHandle.fileDescriptor, buffer.baseAddress, min(buffer.count, fileRemaining))
        while count < 0 && errno == EINTR {
            count = read(fileHandle.fileDescriptor, buffer.baseAddress, min(buffer.count, fileRemaining))
        }
        if count < 0 {
            Logger.mediaUpload.error("Reading the upload file failed mid-stream: \(String(cString: strerror(errno)))")
            return false
        }
        guard count > 0 else {
            // The file ended before `fileSize` bytes — it shrank since it was measured.
            // Stop rather than emit a truncated multipart.
            Logger.mediaUpload.error("Upload file ended \(self.fileRemaining) bytes short of its measured size")
            return false
        }
        fileRemaining -= count
        pending = 0..<count
        return true
    }

    private func finish(wroteEverything: Bool) {
        guard !isFinished else { return }
        isFinished = true
        output.delegate = nil
        CFWriteStreamSetDispatchQueue(output, nil)
        output.close()
        try? fileHandle.close()
        let completion = completion
        self.completion = nil
        completion?(wroteEverything)
        keepAlive = nil
    }
}
