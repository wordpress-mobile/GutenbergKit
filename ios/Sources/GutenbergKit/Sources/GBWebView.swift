import WebKit

class GBWebView: WKWebView {
    
    /// The GutenbergKit version string
    static let version = "0.11.1"
    
    /// Creates a custom user agent string by appending GutenbergKit identifier to the default user agent
    static func createCustomUserAgent() -> String {
        let webView = WKWebView()
        let defaultUserAgent = webView.value(forKey: "userAgent") as? String ?? ""
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
