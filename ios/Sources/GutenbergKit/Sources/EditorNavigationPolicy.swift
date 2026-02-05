import Foundation
import WebKit

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
    private static let allowedSchemes: Set<String> = ["file", "gbk-cache-https", "gbk-media-file"]

    /// Optional development server URL. Navigation to this host is always allowed.
    let devServerURL: URL?

    init(devServerURL: URL? = nil) {
        self.devServerURL = devServerURL
    }

    /// Evaluates whether a navigation action should be allowed within the WebView.
    ///
    /// - Parameter navigationAction: The navigation action to evaluate.
    /// - Returns: `true` if the navigation should proceed in the WebView, `false` if it
    ///   should be opened in the system browser.
    @MainActor
    func shouldAllowNavigation(for navigationAction: WKNavigationAction) -> Bool {
        shouldAllowNavigation(
            url: navigationAction.request.url,
            navigationType: navigationAction.navigationType,
            isMainFrame: navigationAction.targetFrame?.isMainFrame
        )
    }

    /// Evaluates whether a navigation should be allowed based on its properties.
    ///
    /// This method extracts the decision logic from WKNavigationAction to enable unit testing.
    ///
    /// - Parameters:
    ///   - url: The URL being navigated to.
    ///   - navigationType: The type of navigation (link click, JavaScript, etc.).
    ///   - isMainFrame: Whether the navigation targets the main frame (`true`), a subframe (`false`), or unknown (`nil`).
    /// - Returns: `true` if the navigation should proceed in the WebView, `false` if it should open externally.
    func shouldAllowNavigation(url: URL?, navigationType: WKNavigationType, isMainFrame: Bool?) -> Bool {
        guard let url else {
            return false
        }

        // Allow local editor resources and custom URL schemes
        if isAllowedScheme(url) {
            return true
        }

        // Allow navigation to dev server URL if configured
        if isDevServerURL(url) {
            return true
        }

        // Allow subframe navigation (iframes, video embeds, etc.)
        // When targetFrame is nil (e.g., target="_blank" or window.open()), treat
        // as external navigation since it's attempting to open a new window.
        if isMainFrame == false {
            return true
        }

        // Allow reload navigation (e.g., pull-to-refresh, manual reload)
        if navigationType == .reload {
            return true
        }

        // Block all other main frame navigation to external URLs:
        // - .linkActivated: User tapped a link
        // - .other: JavaScript navigation (e.g., window.top.location.href for upsell buttons)
        // - .backForward, .formSubmitted, .formResubmitted: Not expected in the editor
        return false
    }

    // MARK: - Internal helpers (exposed for testing)

    /// Returns `true` if the URL uses an allowed scheme.
    func isAllowedScheme(_ url: URL) -> Bool {
        guard let scheme = url.scheme else { return false }
        return Self.allowedSchemes.contains(scheme)
    }

    /// Returns `true` if the URL matches the configured dev server host.
    func isDevServerURL(_ url: URL) -> Bool {
        guard let devServerURL else { return false }
        return url.host == devServerURL.host
    }
}
