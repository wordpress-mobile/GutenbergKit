#if canImport(Network)

import Foundation
import Testing
@testable import GutenbergKitHTTP

@Suite("ConnectionTasks")
struct ConnectionTasksTests {

    @Test("track registers a task")
    func track() async {
        let tasks = ConnectionTasks()
        let id = UUID()
        let task = Task<Void, Never> {}
        tasks.track(id, task)

        // Tracking the same ID again should not crash (overwrites)
        let task2 = Task<Void, Never> {}
        tasks.track(id, task2)
    }

    @Test("cancelAll cancels all tracked tasks")
    func cancelAllCancelsTasks() async {
        let tasks = ConnectionTasks()

        let cancelled1 = ManagedAtomic(false)
        let cancelled2 = ManagedAtomic(false)

        let id1 = UUID()
        let t1 = Task<Void, Never> {
            // Spin until cancelled
            while !Task.isCancelled {
                await Task.yield()
            }
            cancelled1.set(true)
        }
        tasks.track(id1, t1)

        let id2 = UUID()
        let t2 = Task<Void, Never> {
            while !Task.isCancelled {
                await Task.yield()
            }
            cancelled2.set(true)
        }
        tasks.track(id2, t2)

        // Give tasks a moment to start
        await Task.yield()

        tasks.cancelAll()

        // Wait for tasks to finish
        await t1.value
        await t2.value

        #expect(cancelled1.get())
        #expect(cancelled2.get())
    }

    @Test("cancelAll is idempotent")
    func cancelAllIdempotent() async {
        let tasks = ConnectionTasks()

        let id = UUID()
        let task = Task<Void, Never> {
            while !Task.isCancelled {
                await Task.yield()
            }
        }
        tasks.track(id, task)

        tasks.cancelAll()
        await task.value

        // Second cancelAll should not crash
        tasks.cancelAll()
    }

    @Test("cancelAll on already-completed tasks does not crash")
    func cancelAllWithCompletedTasks() async {
        let tasks = ConnectionTasks()
        let id = UUID()
        let task = Task<Void, Never> {}
        tasks.track(id, task)
        await task.value

        // Task is already done — cancelAll should not crash
        tasks.cancelAll()
    }

    @Test("concurrent track does not crash")
    func concurrentAccess() async {
        let tasks = ConnectionTasks()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    let id = UUID()
                    let task = Task<Void, Never> {}
                    tasks.track(id, task)
                }
            }
        }

        // Final cleanup should not crash
        tasks.cancelAll()
    }
}

/// Minimal thread-safe boolean for test assertions.
private final class ManagedAtomic: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    init(_ value: Bool) {
        self.value = value
    }

    func get() -> Bool {
        lock.withLock { value }
    }

    func set(_ newValue: Bool) {
        lock.withLock { value = newValue }
    }
}

#endif // canImport(Network)
