import Testing
import Foundation

@testable import GutenbergKit

/// A thread-safe counter for testing async closures.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int = 0

    var value: Int {
        lock.withLock { _value }
    }

    func increment() {
        lock.withLock { _value += 1 }
    }
}

@Suite(.serialized)
struct OnceEveryTests {

    init() {
        // Clean up UserDefaults keys used by tests
        for key in UserDefaults.standard.dictionaryRepresentation().keys {
            if key.hasPrefix("once-every-test-") {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    @Test("executes work on first call")
    func executesWorkOnFirstCall() async throws {
        let counter = Counter()

        await onceEvery(.seconds(60), { counter.increment() }, handle: "test-first-call")

        #expect(counter.value == 1)
    }

    @Test("does not execute work when called again within duration")
    func doesNotExecuteWithinDuration() async throws {
        let counter = Counter()
        let now = Date()

        await onceEvery(.seconds(60), { counter.increment() }, handle: "test-within-duration", currentDate: now)
        await onceEvery(.seconds(60), { counter.increment() }, handle: "test-within-duration", currentDate: now.addingTimeInterval(30))

        #expect(counter.value == 1)
    }

    @Test("executes work again after duration has passed")
    func executesAfterDurationPassed() async throws {
        let counter = Counter()
        let now = Date()

        await onceEvery(.seconds(60), { counter.increment() }, handle: "test-after-duration", currentDate: now)
        await onceEvery(.seconds(60), { counter.increment() }, handle: "test-after-duration", currentDate: now.addingTimeInterval(61))

        #expect(counter.value == 2)
    }

    @Test("different handles are tracked independently")
    func differentHandlesAreIndependent() async throws {
        let counterA = Counter()
        let counterB = Counter()
        let now = Date()

        await onceEvery(.seconds(60), { counterA.increment() }, handle: "test-handle-a", currentDate: now)
        await onceEvery(.seconds(60), { counterB.increment() }, handle: "test-handle-b", currentDate: now)

        #expect(counterA.value == 1)
        #expect(counterB.value == 1)
    }

    @Test("propagates errors from work closure")
    func propagatesErrors() async throws {
        struct TestError: Error {}

        await #expect(throws: TestError.self) {
            try await onceEvery(.seconds(60), { throw TestError() }, handle: "test-error")
        }
    }
}
