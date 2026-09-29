import Foundation
import OSLog

/// The uploads waiting for their `finish` request: files the editor's page is sending
/// to native code in chunks, and files native code imported itself and handed the page
/// a reference to.
///
/// Every chunk is written straight to a staging file, so a file's size is bounded by
/// disk, not memory. Sessions are one-shot — ``take(_:)`` removes the session — so a
/// page that sends `finish` twice cannot upload the same file twice.
actor MediaUploadSessionStore {
    enum Failure: Error, Equatable {
        /// No session with that ID. It never existed, was already finished or
        /// cancelled, or was swept after sitting idle.
        case unknownSession
        /// A chunk arrived out of order: `offset` is where it claimed to start,
        /// `expected` is how many bytes the session already has.
        case offsetMismatch(expected: Int, offset: Int)
        /// The file is larger than the store accepts.
        case tooLarge(limit: Int)
        /// `finish` arrived before every byte the page announced.
        case incomplete(expected: Int, received: Int)
        /// A chunk was sent to a session native code registered, which has no bytes
        /// to receive.
        case notReceiving
    }

    /// A finished session, handed to the uploader.
    struct Finished: Sendable {
        let file: MediaUploadFile
        /// Whether the file is a staging copy the store created, which the caller
        /// deletes once the upload is over. A registered file belongs to whoever
        /// registered it.
        let isStagingCopy: Bool

        /// Deletes the staging copy, if this is one.
        func cleanUp() {
            if isStagingCopy {
                try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent())
            }
        }
    }

    private struct Session {
        let file: MediaUploadFile
        let expectedSize: Int?
        var received: Int
        /// Open for writing while the page sends chunks; `nil` for a registered file.
        var handle: FileHandle?
        var lastActivity: Date
    }

    /// The largest file a session accepts: WordPress's own ceiling is far lower on
    /// almost every host, so this only bounds a runaway page.
    static let defaultMaxFileSize = 4 * 1024 * 1024 * 1024

    /// Where every store stages its files. Each store works in its own subdirectory.
    static var stagingRoot: URL {
        FileManager.default.temporaryDirectory.appending(component: "GutenbergKit-uploads", directoryHint: .isDirectory)
    }

    let directory: URL
    let maxFileSize: Int
    private var sessions: [String: Session] = [:]

    init(directory: URL? = nil, maxFileSize: Int = MediaUploadSessionStore.defaultMaxFileSize) {
        self.directory = directory ?? Self.stagingRoot.appending(component: UUID().uuidString, directoryHint: .isDirectory)
        self.maxFileSize = maxFileSize
    }

    /// Starts receiving a file from the page and returns the session ID.
    ///
    /// - Parameter expectedSize: The file's size as the page reported it. When given,
    ///   `finish` refuses a session that received a different number of bytes.
    func begin(filename: String, mimeType: String, expectedSize: Int?) throws -> String {
        if let expectedSize, expectedSize > maxFileSize {
            throw Failure.tooLarge(limit: maxFileSize)
        }
        let id = UUID().uuidString.lowercased()
        let sessionDirectory = directory.appending(component: id, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        let url = sessionDirectory.appending(component: Self.sanitizeFilename(filename))
        guard FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: url)
        sessions[id] = Session(
            file: MediaUploadFile(url: url, mimeType: mimeType, filename: filename),
            expectedSize: expectedSize,
            received: 0,
            handle: handle,
            lastActivity: .now
        )
        return id
    }

    /// Appends a chunk and returns how many bytes the session now has.
    ///
    /// `offset` must equal the bytes already received. Chunks are sent one at a time,
    /// so any other value means one went missing or arrived twice, and appending it
    /// would silently corrupt the file.
    func append(_ data: Data, to id: String, at offset: Int) throws -> Int {
        guard var session = sessions[id] else { throw Failure.unknownSession }
        guard let handle = session.handle else { throw Failure.notReceiving }
        guard offset == session.received else {
            throw Failure.offsetMismatch(expected: session.received, offset: offset)
        }
        let total = session.received + data.count
        guard total <= maxFileSize, total <= (session.expectedSize ?? maxFileSize) else {
            discard(id)
            throw Failure.tooLarge(limit: session.expectedSize.map { min($0, maxFileSize) } ?? maxFileSize)
        }
        try handle.write(contentsOf: data)
        session.received = total
        session.lastActivity = .now
        sessions[id] = session
        return total
    }

    /// Registers a file native code already holds, so the page can finish an upload of
    /// it without sending its bytes. Returns the session ID.
    func register(_ file: MediaUploadFile) -> String {
        let id = UUID().uuidString.lowercased()
        sessions[id] = Session(file: file, expectedSize: nil, received: 0, handle: nil, lastActivity: .now)
        return id
    }

    /// Ends a session and returns its file for upload.
    func take(_ id: String) throws -> Finished {
        guard let session = sessions.removeValue(forKey: id) else { throw Failure.unknownSession }
        guard let handle = session.handle else {
            return Finished(file: session.file, isStagingCopy: false)
        }
        try? handle.close()
        let finished = Finished(file: session.file, isStagingCopy: true)
        if let expected = session.expectedSize, expected != session.received {
            finished.cleanUp()
            throw Failure.incomplete(expected: expected, received: session.received)
        }
        return finished
    }

    /// Abandons a session, deleting what it received. Unknown IDs are ignored.
    func discard(_ id: String) {
        guard let session = sessions.removeValue(forKey: id) else { return }
        if let handle = session.handle {
            try? handle.close()
            Finished(file: session.file, isStagingCopy: true).cleanUp()
        }
    }

    /// Abandons every session that has been idle for longer than `interval`.
    func sweep(idleFor interval: TimeInterval) {
        let cutoff = Date.now.addingTimeInterval(-interval)
        for (id, session) in sessions where session.lastActivity < cutoff {
            Logger.mediaUpload.info("Discarding upload session \(id), idle since \(session.lastActivity)")
            discard(id)
        }
    }

    /// Abandons every session, for when the editor stops handling media.
    func removeAll() {
        for id in Array(sessions.keys) {
            discard(id)
        }
        try? FileManager.default.removeItem(at: directory)
    }

    var sessionCount: Int { sessions.count }

    /// Deletes staging directories left behind by a store that never cleaned up — the
    /// app was killed mid-upload. Anything younger than `age` is kept, so this can't
    /// race another editor's upload in flight.
    static func removeAbandonedStaging(olderThan age: TimeInterval = 3600) {
        let cutoff = Date.now.addingTimeInterval(-age)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: stagingRoot,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        for entry in entries {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: entry)
            }
        }
    }

    /// The last path component of `name`, so a crafted filename can't escape the
    /// session's directory.
    static func sanitizeFilename(_ name: String) -> String {
        let safe = (name as NSString).lastPathComponent
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "\\", with: "")
        return safe.isEmpty || safe == "." || safe == ".." ? "upload" : safe
    }
}
