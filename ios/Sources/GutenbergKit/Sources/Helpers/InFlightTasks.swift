import Foundation

/// Work in flight, one task per key, each shared by every caller asking for that key.
///
/// A second caller for a key joins the task already running for it rather than starting the
/// same work again. The task belongs to no caller: it runs on its own, so one caller's
/// cancellation can't end it for the others. Cancelling a caller ends that caller's wait at once,
/// and the task is cancelled only when no caller is left waiting on it. A caller that has left
/// hears no further progress, though a progress call already under way when it leaves runs on.
/// A caller that joins at a higher priority than the task's raises the task to match.
final class InFlightTasks<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {

    /// Guards `joinable`, and every ``Entry`` and ``Waiter``.
    private let lock = NSLock()

    /// The tasks a new caller joins. A task leaves when it finishes, or when its last waiter leaves.
    private var joinable: [Key: Entry] = [:]

    /// Returns the value for `key` from the task in flight for it, or from a new one that `run`
    /// performs. `progress` hears the task's progress from when this caller joins until it leaves.
    func value(
        for key: Key,
        progress: EditorProgressCallback? = nil,
        run: @escaping @Sendable (_ report: @escaping EditorProgressCallback) async throws -> Value
    ) async throws -> Value {
        let waiter = Waiter(progress: progress)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                join(key, waiter, continuation, run)
            }
        } onCancel: {
            leave(waiter)
        }
    }

    /// For tests: how many callers are waiting on the task in flight for `key`.
    func waiterCount(for key: Key) -> Int {
        lock.withLock { joinable[key]?.waiters.count ?? 0 }
    }

    private func join(
        _ key: Key,
        _ waiter: Waiter,
        _ continuation: CheckedContinuation<Value, any Error>,
        _ run: @escaping @Sendable (_ report: @escaping EditorProgressCallback) async throws -> Value
    ) {
        let (isCancelled, joined) = lock.withLock { () -> (Bool, Task<Void, Never>?) in
            // Cancelled before getting here, its `onCancel` has run and found nothing to leave.
            guard !Task.isCancelled else { return (true, nil) }
            let running = joinable[key]
            let entry = running ?? start(key, run)
            waiter.continuation = continuation
            waiter.entry = entry
            entry.waiters.append(waiter)
            return (false, running?.task)
        }
        if isCancelled {
            continuation.resume(throwing: CancellationError())
        } else if let joined {
            raise(joined)
        }
    }

    /// Raises `task` to the calling task's priority. A task runs at the priority of the caller
    /// that started it, and a caller waiting on a continuation doesn't escalate it the way one
    /// awaiting `task.value` would — so an editor joining a background prefetch would otherwise
    /// wait at the prefetch's priority. Escalation needs iOS 26 or macOS 26; before that, the
    /// task keeps the priority it started with.
    private func raise(_ task: Task<Void, Never>) {
        if #available(iOS 26, macOS 26, *) {
            task.escalatePriority(to: Task.currentPriority)
        }
    }

    /// Starts the task for `key`. Called with `lock` held.
    private func start(
        _ key: Key,
        _ run: @escaping @Sendable (_ report: @escaping EditorProgressCallback) async throws -> Value
    ) -> Entry {
        let entry = Entry(key: key)
        joinable[key] = entry
        entry.task = Task {
            let result: Result<Value, any Error>
            do {
                result = .success(try await run { progress in await self.report(progress, from: entry) })
            } catch {
                result = .failure(error)
            }
            self.finish(entry, with: result)
        }
        return entry
    }

    /// Tells every waiter still waiting, one at a time. Each is checked again just before its
    /// turn: an earlier waiter's callback can suspend for as long as it likes, and a later waiter
    /// can leave meanwhile — after which its own caller has moved on.
    private func report(_ progress: EditorProgress, from entry: Entry) async {
        let waiters = lock.withLock { entry.waiters }
        for waiter in waiters {
            let callback = lock.withLock { entry.waiters.contains { $0 === waiter } ? waiter.progress : nil }
            await callback?(progress)
        }
    }

    private func finish(_ entry: Entry, with result: Result<Value, any Error>) {
        let continuations = lock.withLock {
            if joinable[entry.key] === entry {
                joinable[entry.key] = nil
            }
            entry.task = nil
            defer { entry.waiters = [] }
            return entry.waiters.compactMap(\.continuation)
        }
        for continuation in continuations {
            continuation.resume(with: result)
        }
    }

    private func leave(_ waiter: Waiter) {
        let (continuation, abandoned) = lock.withLock { () -> (CheckedContinuation<Value, any Error>?, Task<Void, Never>?) in
            guard let entry = waiter.entry, let index = entry.waiters.firstIndex(where: { $0 === waiter }) else {
                return (nil, nil)
            }
            entry.waiters.remove(at: index)
            guard entry.waiters.isEmpty else {
                return (waiter.continuation, nil)
            }
            // No one is left waiting: stop the task, and let the next caller start afresh rather
            // than join one on its way out.
            if joinable[entry.key] === entry {
                joinable[entry.key] = nil
            }
            return (waiter.continuation, entry.task)
        }
        continuation?.resume(throwing: CancellationError())
        abandoned?.cancel()
    }

    /// One task and the callers waiting on it. Guarded by `lock`.
    private final class Entry: @unchecked Sendable {
        let key: Key
        var task: Task<Void, Never>?
        var waiters: [Waiter] = []

        init(key: Key) {
            self.key = key
        }
    }

    /// One ``value(for:progress:run:)`` call. Guarded by `lock`.
    private final class Waiter: @unchecked Sendable {
        let progress: EditorProgressCallback?
        var continuation: CheckedContinuation<Value, any Error>?
        var entry: Entry?

        init(progress: EditorProgressCallback?) {
            self.progress = progress
        }
    }
}
