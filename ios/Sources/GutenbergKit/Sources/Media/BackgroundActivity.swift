import Foundation
#if os(iOS)
import UIKit
#endif

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
    SharedBackgroundActivity.process.begin(reason)
    defer { SharedBackgroundActivity.process.end() }
    #endif
    return try await operation()
}

/// One expiring-activity assertion, held for as long as any operation is running.
///
/// `performExpiringActivity` keeps its assertion only while its block runs, so the block
/// parks its thread on a semaphore until the assertion is given back. An assertion for
/// each operation would park a thread for each, out of the pool `DispatchQueue.global()`
/// draws on: with 64 held, nothing else put on a global queue ran until one of them ended.
/// iOS counts an app's background time once, from when it left the foreground, however
/// many assertions it holds and whenever they were taken (measured on iOS 17.5 and 27.0),
/// so one assertion covers every operation, with one thread.
///
/// When iOS expires the assertion it calls the block a second time with
/// `expired == true` — on another thread, while the first call is still parked — and that
/// call gives the assertion back promptly.
///
/// ## Never taken in the background
///
/// An assertion is only ever taken while the app is in the foreground. One taken after
/// iOS has said the time is up is granted, is never told that it has expired, and gets the
/// app **terminated** when the time runs out about five seconds later, where an app
/// holding nothing would only have been suspended (`0x2182BAAD`, "Timed-out waiting for
/// process to invalidate assertion"; measured on iOS 27.0). So an operation that begins in
/// the background shares the assertion already held, if there is one, and otherwise runs
/// without. When the app returns to the foreground with operations still running, an
/// assertion is taken for them again.
final class SharedBackgroundActivity: @unchecked Sendable {
    /// Asks the system for an assertion. `block` is called with `false` once it is held,
    /// and keeps it for as long as that call runs; it is called with `true` when the
    /// assertion expires, or can't be had.
    typealias Acquire = @Sendable (_ reason: String, _ block: @escaping @Sendable (_ expired: Bool) -> Void) -> Void

    #if os(iOS)
    /// The assertion every operation in this process shares, told when the app leaves and
    /// returns to the foreground.
    ///
    /// It starts out believing the app is in the foreground, so create it there:
    /// ``startObservingApplicationState()`` is for that.
    static let process: SharedBackgroundActivity = {
        let activity = SharedBackgroundActivity { reason, block in
            ProcessInfo.processInfo.performExpiringActivity(withReason: reason, using: block)
        }
        activity.observeApplicationState()
        return activity
    }()

    /// Kept for as long as this is; the shared one lives as long as the process.
    private var observers: [any NSObjectProtocol] = []

    private func observeApplicationState() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
                self?.applicationDidEnterBackground()
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { [weak self] _ in
                self?.applicationWillEnterForeground()
            },
        ]
    }
    #endif

    /// Starts following the app's moves between foreground and background, so that the
    /// first operation to begin already knows which it is in. Call it while the app is in
    /// the foreground; calling it again does nothing.
    static func startObservingApplicationState() {
        #if os(iOS)
        _ = process
        #endif
    }

    private let acquire: Acquire
    private let lock = NSLock()
    private var operations = 0
    private var isInBackground = false
    /// The reason the operations running now were given, for an assertion taken on their
    /// behalf when the app returns to the foreground.
    private var reason = ""
    /// Gives back the assertion being held, or `nil` when none is.
    private var held: DispatchSemaphore?

    init(acquire: @escaping Acquire) {
        self.acquire = acquire
    }

    func begin(_ reason: String) {
        let released: DispatchSemaphore? = lock.withLock {
            operations += 1
            self.reason = reason
            return takeIfAllowed()
        }
        if let released {
            request(reason, releasedBy: released)
        }
    }

    func end() {
        let released: DispatchSemaphore? = lock.withLock {
            operations -= 1
            guard operations == 0 else { return nil }
            defer { held = nil }
            return held
        }
        released?.signal()
    }

    /// The app has left the foreground. No assertion is taken from here until it returns.
    func applicationDidEnterBackground() {
        lock.withLock { isInBackground = true }
    }

    /// The app is back in the foreground. Operations still running get an assertion again
    /// if the last one expired while the app was away.
    func applicationWillEnterForeground() {
        let (released, reason): (DispatchSemaphore?, String) = lock.withLock {
            isInBackground = false
            return (operations > 0 ? takeIfAllowed() : nil, self.reason)
        }
        if let released {
            request(reason, releasedBy: released)
        }
    }

    /// Records a new assertion as held and returns what gives it back, or `nil` when one
    /// is already held or none may be taken. Call with the lock held.
    private func takeIfAllowed() -> DispatchSemaphore? {
        guard held == nil, !isInBackground else { return nil }
        let released = DispatchSemaphore(value: 0)
        held = released
        return released
    }

    /// Asks the system for the assertion. Not under the lock: the block may be called
    /// before this returns.
    private func request(_ reason: String, releasedBy released: DispatchSemaphore) {
        acquire(reason) { [self] expired in
            if expired {
                lock.withLock {
                    if held === released { held = nil }
                }
                released.signal()
            } else {
                released.wait()
            }
        }
    }
}
