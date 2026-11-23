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
    private static let allowedSchemes: Set<String> = ["file"]

    /// The editor's own custom schemes, which mean nothing outside the editor, so a
    /// navigation that would replace the editor's page with one of them is blocked.
    /// - `gbk-cache-https`: Cached remote assets, for subresources and subframes
    /// - `gbk-media-file`: Local media files, for subresources and subframes
    /// - `gbk-rest`, `gbk-upload`: Relays that answer the editor's `fetch` and XHR requests
    private static let resourceSchemes: Set<String> = [
        Constants.EditorAssetLibrary.urlScheme,
        MediaFileSchemeHandler.scheme,
        RestRelaySchemeHandler.scheme,
        MediaUploadSchemeHandler.scheme,
    ]

    /// Optional development server URL. Navigation to this host is always allowed.
    let devServerURL: URL?

    init(devServerURL: URL? = nil) {
        self.devServerURL = devServerURL
    }

    /// Evaluates whether a navigation action should be allowed within the WebView.
    ///
    /// - Parameter navigationAction: The navigation action to evaluate.
    /// - Returns: `true` if the navigation should proceed in the WebView, `false` if it
    ///   must not. The caller opens a refused external URL in the system browser.
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
    /// - Returns: `true` if the navigation should proceed in the WebView, `false` if it must not.
    func shouldAllowNavigation(url: URL?, navigationType: WKNavigationType, isMainFrame: Bool?) -> Bool {
        guard let url else {
            return false
        }

        // Allow local editor resources and custom URL schemes
        if isAllowedScheme(url) {
            return true
        }

        // The editor's resource schemes never replace its page, even on the dev server's host
        if isResourceScheme(url) {
            return isMainFrame == false
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

    /// Returns `true` if the URL uses one of the editor's own resource schemes.
    func isResourceScheme(_ url: URL) -> Bool {
        guard let scheme = url.scheme else { return false }
        return Self.resourceSchemes.contains(scheme)
    }

    /// Returns `true` if a page with this security origin is the editor's own: the bundled
    /// `file:` page, or the dev server when one is configured.
    func isEditorOrigin(scheme: String, host: String, port: Int) -> Bool {
        if scheme == "file" {
            return true
        }
        guard let devServerURL, let devScheme = devServerURL.scheme, let devHost = devServerURL.host else {
            return false
        }
        // `WKSecurityOrigin` reports a default port as 0.
        return scheme.caseInsensitiveCompare(devScheme) == .orderedSame
            && host.caseInsensitiveCompare(devHost) == .orderedSame
            && port == (devServerURL.port ?? 0)
    }

    /// Returns `true` if the URL matches the configured dev server host.
    func isDevServerURL(_ url: URL) -> Bool {
        guard let devServerURL else { return false }
        return url.host == devServerURL.host
    }
}
