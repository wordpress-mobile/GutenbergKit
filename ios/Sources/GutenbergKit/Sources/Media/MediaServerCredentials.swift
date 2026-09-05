import Foundation

/// Whether the editor configuration can reach the configured site for media.
///
/// Deliberately outside `EditorViewController`. That type is `#if canImport(UIKit)`,
/// so on the macOS host it does not exist and nothing in it can be tested — including
/// this check, which already diverged silently between iOS and Android once. Living
/// here, it is reachable from the host test suite.
enum MediaServerCredentials {
    /// Whether a ``DefaultMediaUploader`` built from this configuration could actually
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
}
