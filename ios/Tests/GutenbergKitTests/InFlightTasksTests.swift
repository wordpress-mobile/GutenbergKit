import Foundation
import Testing

@testable import GutenbergKit

@Suite("InFlightTasks", .timeLimit(.minutes(1)))
struct InFlightTasksTests {

    /// Each test's own table, so tests running in parallel can't meet in it.
    private let tasks = InFlightTasks<String, Int>()

    // MARK: - Sharing

    @Test("callers for the same key share one task, and all hear its progress")
    func callersForTheSameKeyShareOneTask() async throws {
        let work = ParkedWork()
        let (first, second) = (ProgressTracker(), ProgressTracker())
        let a = startCaller(for: "key", running: work, progress: first)
        let b = startCaller(for: "key", running: work, progress: second)
        try await waitUntil { tasks.waiterCount(for: "key") == 2 }
        try await waitUntil { !first.updates.isEmpty && !second.updates.isEmpty }

        work.release()
        #expect(try await a.value == ParkedWork.value)
        #expect(try await b.value == ParkedWork.value)
        #expect(work.runs == 1)
    }

    @Test("callers for different keys run separately")
    func callersForDifferentKeysRunSeparately() async throws {
        let work = ParkedWork()
        let one = startCaller(for: "one", running: work)
        let other = startCaller(for: "other", running: work)
        try await waitUntil { work.runs == 2 }

        work.release()
        #expect(try await one.value == ParkedWork.value)
        #expect(try await other.value == ParkedWork.value)
    }

    @Test("a failed task fails every caller waiting on it")
    func aFailedTaskFailsEveryCaller() async throws {
        let work = ParkedWork()
        let a = startCaller(for: "key", running: work)
        let b = startCaller(for: "key", running: work)
        try await waitUntil { tasks.waiterCount(for: "key") == 2 }

        work.release(throwing: URLError(.timedOut))
        await #expect(throws: URLError.self) { try await a.value }
        await #expect(throws: URLError.self) { try await b.value }
    }

    // MARK: - Cancellation

    @Test("cancelling a caller ends its wait at once, and leaves the task running for the rest")
    func cancellingACallerLeavesTheTaskRunning() async throws {
        let work = ParkedWork()
        let leaving = startCaller(for: "key", running: work)
        let staying = startCaller(for: "key", running: work)
        try await waitUntil { tasks.waiterCount(for: "key") == 2 }

        leaving.cancel()
        // Returns while the task is still parked — it doesn't wait for it.
        await #expect(throws: CancellationError.self) { try await leaving.value }
        #expect(!work.wasCancelled)

        work.release()
        #expect(try await staying.value == ParkedWork.value)
    }

    @Test("the last caller leaving cancels the task, and the next caller starts afresh")
    func theLastCallerLeavingCancelsTheTask() async throws {
        let work = ParkedWork()
        let first = startCaller(for: "key", running: work)
        try await waitUntil { work.runs == 1 }

        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        try await waitUntil { work.wasCancelled }

        let next = startCaller(for: "key", running: work)
        try await waitUntil { work.runs == 2 }
        work.release()
        #expect(try await next.value == ParkedWork.value)
    }

    @Test("a caller that has left hears no more progress, even from a report already under way")
    func aCallerThatHasLeftHearsNoMoreProgress() async throws {
        let work = ParkedWork()
        let gate = ProgressGate()
        let leaver = ProgressTracker()
        let staying = startCaller(for: "key", running: work, onProgress: { await gate.pass($0) })
        try await waitUntil { tasks.waiterCount(for: "key") == 1 }
        let leaving = startCaller(for: "key", running: work, progress: leaver)
        try await waitUntil { !leaver.updates.isEmpty }

        // Hold a report in the staying caller's callback. The leaving caller had already heard
        // one, so it is on this report's list too, waiting its turn.
        gate.close()
        try await waitUntil { gate.isHolding }
        leaving.cancel()
        await #expect(throws: CancellationError.self) { try await leaving.value }
        let heard = leaver.count

        // Let the held report finish and the next one start, so the leaving caller's turn is past.
        let passes = gate.passes
        gate.open()
        try await waitUntil { gate.passes >= passes + 2 }
        #expect(leaver.count == heard, "the leaving caller should hear nothing once it has left")

        work.release()
        #expect(try await staying.value == ParkedWork.value)
    }

    // MARK: - Priority

    @Test("a caller joining at a higher priority raises the task to match")
    func aHigherPriorityCallerRaisesTheTask() async throws {
        guard #available(iOS 26, macOS 26, *) else { return }
        let work = ParkedWork()
        let low = startCaller(for: "key", running: work, priority: .utility)
        try await waitUntil { work.runs == 1 }
        #expect(work.priority.rawValue < TaskPriority.userInitiated.rawValue)

        let high = startCaller(for: "key", running: work, priority: .userInitiated)
        try await waitUntil { work.priority.rawValue >= TaskPriority.userInitiated.rawValue }

        work.release()
        #expect(try await low.value == ParkedWork.value)
        #expect(try await high.value == ParkedWork.value)
    }

    // MARK: - Helpers

    /// A caller waiting on `key`, which runs `work` if nothing is in flight for it yet. It hears
    /// progress through `onProgress`, or else records it in `progress`.
    private func startCaller(
        for key: String,
        running work: ParkedWork,
        priority: TaskPriority? = nil,
        progress: ProgressTracker? = nil,
        onProgress: EditorProgressCallback? = nil
    ) -> Task<Int, any Error> {
        let callback: EditorProgressCallback? = onProgress ?? progress.map { tracker in
            { @Sendable (update: EditorProgress) async in tracker.append(update) }
        }
        return Task(priority: priority) { [tasks] in
            try await tasks.value(for: key, progress: callback) { report in
                try await work.run(reporting: report)
            }
        }
    }
}

/// A progress callback the test can close, holding whichever report reaches it until it reopens.
private final class ProgressGate: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false
    private var holding = false
    private var passCount = 0

    /// Whether a report is held here right now.
    var isHolding: Bool { lock.withLock { holding } }

    /// How many reports have been let through.
    var passes: Int { lock.withLock { passCount } }

    func close() { lock.withLock { closed = true } }
    func open() { lock.withLock { closed = false } }

    func pass(_ progress: EditorProgress) async {
        while lock.withLock({ holding = closed; return closed }) {
            try? await Task.sleep(for: .milliseconds(5))
        }
        lock.withLock {
            holding = false
            passCount += 1
        }
    }
}

/// Work that runs until released: it counts its runs, reports progress while it waits, and
/// records whether it was cancelled.
private final class ParkedWork: @unchecked Sendable {
    static let value = 42

    private let lock = NSLock()
    private var runCount = 0
    private var cancelled = false
    private var released = false
    private var failure: (any Error)?
    private var latestPriority = TaskPriority.medium

    var runs: Int { lock.withLock { runCount } }
    var wasCancelled: Bool { lock.withLock { cancelled } }

    /// The priority the latest run was going at when it last checked.
    var priority: TaskPriority { lock.withLock { latestPriority } }

    /// Lets every run finish: with `failure` if there is one, or with ``value``.
    func release(throwing failure: (any Error)? = nil) {
        lock.withLock {
            self.failure = failure
            released = true
        }
    }

    func run(reporting report: EditorProgressCallback) async throws -> Int {
        lock.withLock {
            latestPriority = Task.currentPriority
            runCount += 1
        }
        while !lock.withLock({ released }) {
            lock.withLock { latestPriority = Task.currentPriority }
            await report(EditorProgress(completed: 1, total: 100))
            do {
                try await Task.sleep(for: .milliseconds(10))
            } catch {
                lock.withLock { cancelled = true }
                throw error
            }
        }
        if let failure = lock.withLock({ failure }) {
            throw failure
        }
        return Self.value
    }
}
