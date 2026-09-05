import Foundation

/// Whether the editor configuration can reach the configured site for media, and the
/// fail-fast that enforces it.
///
/// Deliberately outside `EditorViewController`. That type is `#if canImport(UIKit)`,
/// so on the macOS host it does not exist and nothing in it can be tested — including
/// this policy, which is a *crash* policy and already diverged silently between iOS
/// and Android once. Living here, it is reachable from the host test suite, where
/// Swift Testing's exit tests (unavailable on iOS/simulator) can assert the trap
/// itself rather than only the predicate.
enum MediaServerCredentials {
    /// Whether a ``InternalMediaClient`` built from this configuration could actually
    /// reach the site.
    ///
    /// Both fields are required. The uploader delivers GutenbergKit's uploads to the
    /// configured site, so it needs somewhere to send them and credentials to be
    /// accepted; with either missing, every media request it makes fails.
    ///
    /// `siteApiRoot` is a `URL` here where Android types it as a `String`, so the
    /// equivalent of Android's `isEmpty()` check is "not absolute" — a URL with no
    /// scheme or host cannot address the site, and every request built from it fails at
    /// the URLSession layer.
    static func areUsable(siteApiRoot: URL, authHeader: String) -> Bool {
        siteApiRoot.scheme != nil && siteApiRoot.host() != nil && !authHeader.isEmpty
    }

    /// Returns whether the upload server can start, trapping if the host set a
    /// ``MediaUploader`` without usable credentials.
    ///
    /// The behavior forks by intent:
    ///
    /// - A ``MediaProcessor`` only enhances GutenbergKit-owned uploads. With no
    ///   credentials there is nothing to deliver through, so nothing to process — the
    ///   caller leaves the server down and uploads fall to the default WebView path.
    ///
    /// - A ``MediaUploader`` means the host is *taking over* uploads. Falling back
    ///   would silently drop it, and its media deletes still need the internal media
    ///   client to reach the configured site. A host that sets an uploader must provide
    ///   credentials too; omitting them is a configuration error, so trap rather than
    ///   start a server whose every delete would fail. (Matches Android's `check`.)
    static func canStartServer(siteApiRoot: URL, authHeader: String, hasUploader: Bool) -> Bool {
        if areUsable(siteApiRoot: siteApiRoot, authHeader: authHeader) {
            return true
        }
        precondition(
            !hasUploader,
            "A mediaUploader needs site credentials so GutenbergKit can relay the "
                + "editor's media deletes to the configured site. Set an absolute "
                + "siteApiRoot and the auth header in the editor configuration."
        )
        return false
    }
}
