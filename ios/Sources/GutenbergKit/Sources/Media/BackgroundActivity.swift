#if !os(macOS)
import Foundation

/// Keeps the app running for the system's background grace period (~30s) while `operation`
/// runs, so a media upload already in flight can finish if the user locks the phone mid-
/// transfer — rather than the app being suspended and its loopback socket reclaimed before
/// the upload completes.
///
/// Best-effort by design: the OS grants a short, fixed window and no more, so a long upload
/// on a slow link still ends when the grace expires. The upload then fails and the user
/// retries, exactly as before — the assertion only widens the window that already works, it
/// doesn't make an arbitrarily long upload survive suspension. Real background continuation
/// belongs with a host ``MediaUploader`` over its own background `URLSession`.
///
/// Takes the assertion through `ProcessInfo` rather than `UIApplication`, so it needs neither
/// `UIApplication.shared` nor the main thread. That matters because the upload server serves
/// every connection inside this, including its own liveness probe. A probe that had to wait
/// out a busy main thread (while a WebView launches, say) would time out and restart a healthy
/// server, cancelling any upload on it.
///
/// The assertion is always released: when `operation` finishes, or earlier if the system
/// expires it first.
func withBackgroundActivity<T>(_ reason: String, _ operation: () async -> T) async -> T {
    let activity = ExpiringActivity(reason: reason)
    let result = await operation()
    activity.end()
    return result
}

/// One `ProcessInfo` expiring activity, held until ``end()`` or until the system expires it.
///
/// The activity lasts as long as its block runs, so the block parks on a semaphore until
/// `end()` signals it. That holds one dispatch thread per activity, and there's at most one
/// activity per connection, which `HTTPServer` caps.
///
/// If the system expires the activity first, it calls the block a second time with `expired`
/// set, and that call releases the parked one, so the activity ends promptly as the system
/// requires. If it can't grant the activity at all, that `expired` call is the only one. Every
/// order of these calls and `end()` comes out balanced: a signal that arrives before the wait
/// just lets the wait through, and a spare one is harmless.
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
