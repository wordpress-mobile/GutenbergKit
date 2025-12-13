import WebKit

class GBWebView: WKWebView {
    
    /// The GutenbergKit version string
    static let version = "0.11.1"
    
    /// Cached default user agent to avoid repeated WKWebView instantiation
    private static let defaultUserAgent: String = {
        let webView = WKWebView()
        return webView.value(forKey: "userAgent") as? String ?? ""
    }()
    
    /// Creates a custom user agent string by appending GutenbergKit identifier to the default user agent
    static func createCustomUserAgent() -> String {
        return "\(defaultUserAgent) GutenbergKit/\(version)"
    }

    #if canImport(UIKit)
    /// Disables the default bottom bar that competes with the Gutenberg inserter
    ///
    override var inputAccessoryView: UIView? {
        nil
    }
    #endif
}
