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
    /// Whether an ``InternalMediaClient`` built from this configuration could actually
    /// reach the site.
    ///
    /// Both fields are required. The client delivers GutenbergKit's uploads to the
    /// configured site, so it needs somewhere to send them and credentials to be
    /// accepted; with either missing, every media request it makes fails.
    ///
    /// "Somewhere to send them" means an *absolute* root: a URL with no scheme or host
    /// cannot address the site, and every request built from it fails at the URLSession
    /// layer. `siteApiRoot` is a `URL` here where Android types it as a `String`, but
    /// the rule is the same on both sides — Android spells it `Uri.parse(...)` with the
    /// same scheme-and-host test, having previously checked only `isEmpty()` and so
    /// accepted roots this rejects.
    static func areUsable(siteApiRoot: URL, authHeader: String) -> Bool {
        siteApiRoot.scheme != nil && siteApiRoot.host() != nil && !authHeader.isEmpty
    }

    /// Traps if the host supplied a ``MediaUploader`` without usable credentials.
    ///
    /// The behavior forks by intent:
    ///
    /// - A ``MediaProcessor`` only enhances GutenbergKit-owned uploads. With no
    ///   credentials there is nothing to deliver through, so nothing to process — the
    ///   server simply stays down and uploads fall to the default WebView path. That
    ///   is ``areUsable``'s job, at the point the server would start.
    ///
    /// - A ``MediaUploader`` means the host is *taking over* uploads, and falling back
    ///   would drop that whole stack — its queueing, its retries — while media appeared
    ///   to keep working. Worth failing over rather than logging.
    ///
    /// What makes it a *trap* rather than a warning is that the configuration is
    /// incoherent, not merely unlucky: an uploader's media deletes still relay through
    /// the internal media client, so there is no site root and auth header under which
    /// this host's uploader could have worked. Contrast the conditions the host's
    /// environment imposes at server start — a network policy that blocks the loopback
    /// endpoint, a port that won't bind — which log and degrade, because the very same
    /// configuration works once the environment allows it. Dropping the uploader is the
    /// symptom both share; only this one has a cause the host can fix in the
    /// configuration it just handed over.
    ///
    /// Called from `EditorViewController.init`, not from the server start. The uploader
    /// is `private(set)` and assigned only there, so a non-nil uploader at load time was
    /// necessarily passed at `init` — checking it then puts the host's own call site in
    /// the stack trace, instead of surfacing the mistake later from inside a page-load
    /// callback where the trace names only GutenbergKit. This mirrors what moving the
    /// handlers into `init` already did for the set-before-load contract: enforce the
    /// rule where the host states its intent.
    ///
    /// (Android enforces this in `GutenbergView.mediaUploader`'s setter — the earliest
    /// point available there, since it takes its handlers as mutable properties rather
    /// than at construction.)
    static func requireCredentialsForUploader(siteApiRoot: URL, authHeader: String, hasUploader: Bool) {
        guard hasUploader else { return }
        precondition(
            areUsable(siteApiRoot: siteApiRoot, authHeader: authHeader),
            "A mediaUploader needs site credentials so GutenbergKit can relay the "
                + "editor's media deletes to the configured site. Set an absolute "
                + "siteApiRoot and the auth header in the editor configuration."
        )
    }
}
