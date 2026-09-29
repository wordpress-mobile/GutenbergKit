import Foundation

/// Runs `operation` while holding an assertion that asks iOS to keep the app running
/// if it moves to the background.
///
/// iOS suspends an app about a second after it leaves the foreground. An upload that is
/// still sending its body, or waiting for WordPress to answer, then stalls until the app
/// comes back — by which time the request has usually failed. The assertion buys about
/// thirty seconds (measured on iOS 27, with Low Power Mode on or off), which covers the
/// common case of a photo on a working connection. It does not cover a large video on a
/// slow one; nothing that keeps the upload in this process can.
///
/// `ProcessInfo.performExpiringActivity` rather than `UIApplication.beginBackgroundTask`:
/// it needs neither the main thread nor `UIApplication`, so it can be taken from any
/// executor, and it behaves the same in the simulator.
func withBackgroundActivity<T>(
    _ reason: String,
    isolation: isolated (any Actor)? = #isolation,
    _ operation: () async throws -> T
) async rethrows -> T {
    #if os(iOS)
    let activity = ExpiringActivity(reason: reason)
    defer { activity.end() }
    #endif
    return try await operation()
}

#if os(iOS)
/// An expiring-activity assertion held until ``end()``.
///
/// `performExpiringActivity` keeps the assertion only while its block runs, so the
/// block parks on a semaphore until `end()` releases it. When iOS expires the assertion
/// it calls the block a second time with `expired == true` — on another thread, while
/// the first call is still parked — and that call releases the first one so the
/// assertion is returned promptly.
private struct ExpiringActivity {
    private let released = DispatchSemaphore(value: 0)

    init(reason: String) {
        let released = released
        ProcessInfo.processInfo.performExpiringActivity(withReason: reason) { expired in
            if expired {
                released.signal()
            } else {
                released.wait()
            }
        }
    }

    func end() {
        released.signal()
    }
}
#endif
