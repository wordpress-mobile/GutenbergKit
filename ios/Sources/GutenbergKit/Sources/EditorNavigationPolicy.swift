import Foundation

/// Determines how URLs should be handled during WebView navigation.
///
/// This policy controls whether navigation requests should be allowed within the WebView
/// or redirected to the system browser. It's used to ensure external URLs (like upgrade
/// flows and help links) open in Safari while editor resources load normally.
struct EditorNavigationPolicy {
    /// URL schemes that are always allowed to load within the WebView.
    /// - `file`: Local bundled editor resources
    /// - `gbk-cache-https`: Cached remote assets served via custom scheme handler
    /// - `gbk-media-file`: Local media files from the device's photo library
    static let allowedSchemes: Set<String> = ["file", "gbk-cache-https", "gbk-media-file"]

    /// Optional development server URL. Navigation to this host is always allowed.
    let devServerURL: URL?

    init(devServerURL: URL? = nil) {
        self.devServerURL = devServerURL
    }

    /// Evaluates whether a URL should be allowed to load within the WebView.
    ///
    /// - Parameter url: The URL being navigated to.
    /// - Returns: `true` if the URL should load in the WebView, `false` if it should
    ///   be opened in the system browser.
    func shouldAllowNavigation(to url: URL) -> Bool {
        // Allow local editor resources and custom URL schemes
        if let scheme = url.scheme, Self.allowedSchemes.contains(scheme) {
            return true
        }

        // Allow navigation to dev server URL if configured
        if let devServerURL, url.host == devServerURL.host {
            return true
        }

        // All other URLs (http/https) should open externally
        return false
    }
}
