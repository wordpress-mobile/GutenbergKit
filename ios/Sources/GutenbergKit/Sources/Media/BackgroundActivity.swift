#if canImport(UIKit)
import UIKit

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
/// The assertion is always balanced, including when the OS expires it first: its expiration
/// handler ends it and marks the token spent, so the `end()` after `operation` is a no-op.
func withBackgroundActivity<T>(_ name: String, _ operation: () async -> T) async -> T {
    let token = await BackgroundActivityToken(name: name)
    let result = await operation()
    await token.end()
    return result
}

/// A single `UIApplication` background-task assertion with once-only teardown.
@MainActor
private final class BackgroundActivityToken {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            // The OS is about to reclaim the assertion; end it promptly or the app is killed.
            self?.end()
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
#endif
