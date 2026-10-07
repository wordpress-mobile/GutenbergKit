import Foundation
import Testing

@testable import GutenbergKit

@Suite("Background activity")
struct BackgroundActivityTests {
    @Test("operations running at once share one assertion")
    func sharesOneAssertion() {
        let system = FakeAssertions()
        let activity = SharedBackgroundActivity(acquire: system.acquire)

        activity.begin("upload")
        activity.begin("upload")
        activity.begin("upload")

        #expect(system.requests == 1)
    }

    @Test("the assertion is held until the last operation ends")
    func heldUntilTheLastEnds() async {
        let system = FakeAssertions()
        let activity = SharedBackgroundActivity(acquire: system.acquire)
        activity.begin("upload")
        activity.begin("upload")
        let holding = system.hold(0)

        activity.end()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(!holding.isFinished, "the assertion was given back with an operation still running")

        activity.end()
        await holding.waitUntilFinished()
        #expect(holding.isFinished)
    }

    @Test("an assertion iOS expires is given back")
    func expiredAssertionIsGivenBack() async {
        let system = FakeAssertions()
        let activity = SharedBackgroundActivity(acquire: system.acquire)
        activity.begin("upload")
        activity.applicationDidEnterBackground()
        let holding = system.hold(0)

        system.expire(0)
        await holding.waitUntilFinished()

        #expect(holding.isFinished)
    }

    // MARK: - Never taken in the background

    @Test("an operation that begins in the background takes no assertion")
    func noAssertionIsTakenInTheBackground() {
        let system = FakeAssertions()
        let activity = SharedBackgroundActivity(acquire: system.acquire)
        activity.applicationDidEnterBackground()

        activity.begin("upload")

        #expect(system.requests == 0)
    }

    @Test("an operation that begins in the background shares the assertion already held")
    func backgroundOperationSharesTheHeldAssertion() async {
        let system = FakeAssertions()
        let activity = SharedBackgroundActivity(acquire: system.acquire)
        activity.begin("upload")
        activity.applicationDidEnterBackground()
        let holding = system.hold(0)

        activity.begin("upload")
        activity.end()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(system.requests == 1)
        #expect(!holding.isFinished, "the assertion was given back with the background operation still running")
        activity.end()
        await holding.waitUntilFinished()
    }

    @Test("once the assertion has expired, an operation that begins in the background takes no new one")
    func noAssertionIsTakenAfterExpiry() {
        // iOS grants one taken now, never says it has expired, and terminates the app
        // when the time runs out.
        let system = FakeAssertions()
        let activity = SharedBackgroundActivity(acquire: system.acquire)
        activity.begin("upload")
        activity.applicationDidEnterBackground()
        system.expire(0)

        activity.begin("upload")

        #expect(system.requests == 1)
    }

    @Test("back in the foreground, operations still running get an assertion again")
    func assertionIsTakenAgainInTheForeground() {
        let system = FakeAssertions()
        let activity = SharedBackgroundActivity(acquire: system.acquire)
        activity.begin("upload")
        activity.applicationDidEnterBackground()
        system.expire(0)

        activity.applicationWillEnterForeground()

        #expect(system.requests == 2)
        #expect(system.reasons == ["upload", "upload"])
    }

    @Test("back in the foreground with nothing running, no assertion is taken")
    func nothingIsTakenForNoOperations() {
        let system = FakeAssertions()
        let activity = SharedBackgroundActivity(acquire: system.acquire)
        activity.begin("upload")
        activity.applicationDidEnterBackground()
        system.expire(0)
        activity.end()

        activity.applicationWillEnterForeground()

        #expect(system.requests == 1)
    }

    @Test("back in the foreground with its assertion still held, no second one is taken")
    func noSecondAssertionWhileOneIsHeld() {
        let system = FakeAssertions()
        let activity = SharedBackgroundActivity(acquire: system.acquire)
        activity.begin("upload")
        activity.applicationDidEnterBackground()

        activity.applicationWillEnterForeground()
        activity.begin("upload")

        #expect(system.requests == 1)
    }

    @Test("an assertion taken after the last operation ended is given straight back")
    func lateAssertionIsNotKept() async {
        // iOS runs the block some time after it is asked; the operation can be over by then.
        let system = FakeAssertions()
        let activity = SharedBackgroundActivity(acquire: system.acquire)
        activity.begin("upload")
        activity.end()

        let holding = system.hold(0)
        await holding.waitUntilFinished()
        #expect(holding.isFinished)
    }

    #if os(iOS)
    @Test("two hundred operations at once leave the global dispatch queue free")
    func manyOperationsLeaveTheDispatchPoolAlone() async {
        let gate = Gate()
        let operations = (0..<200).map { _ in
            Task { await withBackgroundActivity("gutenbergkit-test") { await gate.wait() } }
        }
        // Long enough for an assertion per operation to have parked its thread.
        try? await Task.sleep(for: .seconds(1))

        let ran = await runsOnGlobalQueue(within: 10)

        gate.open()
        for operation in operations { await operation.value }
        #expect(ran, "work put on a global queue did not run while the operations were held")
    }
    #endif
}

/// Stands in for `performExpiringActivity`: records each request and lets a test run its block.
private final class FakeAssertions: @unchecked Sendable {
    private let lock = NSLock()
    private var blocks: [@Sendable (Bool) -> Void] = []
    private var askedWith: [String] = []

    var requests: Int { lock.withLock { blocks.count } }
    var reasons: [String] { lock.withLock { askedWith } }

    var acquire: SharedBackgroundActivity.Acquire {
        { [self] reason, block in
            lock.withLock {
                blocks.append(block)
                askedWith.append(reason)
            }
        }
    }

    /// Runs request `index`'s block as iOS does once the assertion is held: on a thread of its own.
    func hold(_ index: Int) -> Holding {
        let block = lock.withLock { blocks[index] }
        let holding = Holding()
        Thread.detachNewThread {
            block(false)
            holding.finish()
        }
        return holding
    }

    /// Runs request `index`'s block as iOS does when the assertion expires.
    func expire(_ index: Int) {
        lock.withLock { blocks[index] }(true)
    }

    final class Holding: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false

        var isFinished: Bool { lock.withLock { finished } }
        func finish() { lock.withLock { finished = true } }

        func waitUntilFinished(timeout: Duration = patientTimeout) async {
            let deadline = ContinuousClock.now + timeout
            while !isFinished && ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(2))
            }
        }
    }
}

#if os(iOS)
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock { () -> Bool in
                if isOpen { return true }
                waiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func open() {
        let waiting = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isOpen = true
            defer { waiters = [] }
            return waiters
        }
        waiting.forEach { $0.resume() }
    }
}

/// Whether a block put on a global queue gets to run within `seconds`.
private func runsOnGlobalQueue(within seconds: Double) async -> Bool {
    await withCheckedContinuation { continuation in
        let lock = NSLock()
        nonisolated(unsafe) var answered = false
        let answer: @Sendable (Bool) -> Void = { ran in
            let first = lock.withLock { () -> Bool in
                if answered { return false }
                answered = true
                return true
            }
            if first { continuation.resume(returning: ran) }
        }
        DispatchQueue.global().async { answer(true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { answer(false) }
    }
}
#endif
