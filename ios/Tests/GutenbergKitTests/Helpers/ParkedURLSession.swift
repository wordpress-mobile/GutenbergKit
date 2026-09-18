import Foundation
@testable import GutenbergKit

/// A `URLSessionProtocol` whose requests never finish until the test lets them, so
/// work started against it stays in flight for as long as the test needs, and which
/// records whether the task waiting on a request was cancelled.
final class ParkedURLSession: URLSessionProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private var cancelled = false
    private var released = false
    private var requests = 0

    private var isStarted: Bool { lock.withLock { started } }
    private var isCancelled: Bool { lock.withLock { cancelled } }
    private var isReleased: Bool { lock.withLock { released } }

    /// How many requests have been made against this session.
    var requestCount: Int { lock.withLock { requests } }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await park()
    }

    func download(for request: URLRequest, delegate: (any URLSessionTaskDelegate)?) async throws -> (URL, URLResponse) {
        try await park()
    }

    /// Lets every parked request fail, so the work waiting on them — and the task
    /// running it — finishes. Always call this: a request left parked stays in
    /// flight for the rest of the run.
    func release() {
        lock.withLock { released = true }
    }

    /// Suspends until `release()` or until the calling task is cancelled.
    /// `Never` because every exit throws — it satisfies both return types.
    private func park() async throws -> Never {
        lock.withLock {
            started = true
            requests += 1
        }
        while !isReleased {
            do {
                try await Task.sleep(for: .milliseconds(20))
            } catch {
                lock.withLock { cancelled = true }
                throw URLError(.cancelled)
            }
        }
        throw URLError(.networkConnectionLost)
    }

    func waitUntilStarted(timeout: Duration = .seconds(10)) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if isStarted { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw ParkedURLSessionTimeout.requestNeverStarted
    }

    func waitUntilCancelled(timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if isCancelled { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return isCancelled
    }
}

enum ParkedURLSessionTimeout: Error {
    case requestNeverStarted
}
