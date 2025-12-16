import Foundation
import OSLog

let clock = ContinuousClock()

/// A helper function for performance logging – makes it easy to check how long any code block takes
///
func logExecutionTime<T>(_ label: String, _ work: () throws -> T) rethrows -> T {
    let startInstant = clock.now
    defer { Logger.timing.trace("⏱️ \(label): \(clock.now - startInstant)") }
    return try work()
}

/// A helper function for performance logging – makes it easy to check how long any code block takes
///
func logExecutionTime<T>(_ label: String, _ work: @Sendable () async throws -> T) async rethrows -> T {
    let startInstant = clock.now
    defer { Logger.timing.trace("⏱️ \(label): \(clock.now - startInstant)") }
    return try await work()
}

public func onceEvery(
    _ duration: ContinuousClock.Instant.Duration,
    _ work: @Sendable () async throws -> Void,
    handle: String = #function,
    currentDate: Date = Date()
) async rethrows {
    let lastRunTimestamp = UserDefaults.standard.double(forKey: "once-every-" + handle)

    if lastRunTimestamp + TimeInterval(duration.components.seconds) <= currentDate.timeIntervalSince1970 {
        try await work()
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "once-every-" + handle)
    }
}
