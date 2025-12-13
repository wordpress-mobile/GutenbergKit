import WebKit

class GBWebView: WKWebView {
    
    /// Cached custom user agent to avoid repeated WebView instantiation
    private static var cachedCustomUserAgent: String?
    
    /// Creates a custom user agent string by appending GutenbergKit identifier to the default user agent
    /// The result is cached after the first call to avoid performance overhead
    static func createCustomUserAgent() -> String {
        // Return cached value if available
        if let cached = cachedCustomUserAgent {
            return cached
        }
        
        // Get the default user agent by creating a temporary WKWebView
        let webView = WKWebView()
        var defaultUserAgent = ""
        
        // Use DispatchGroup for synchronous wait
        // This is safe during view initialization as it's not on a critical path
        let group = DispatchGroup()
        group.enter()
        
        webView.evaluateJavaScript("navigator.userAgent") { result, error in
            if let result = result as? String {
                defaultUserAgent = result
            }
            group.leave()
        }
        
        group.wait()
        
        // Cache and return the result
        let customUserAgent = "\(defaultUserAgent) GutenbergKit/\(GutenbergKit.version)"
        cachedCustomUserAgent = customUserAgent
        return customUserAgent
    }

    #if canImport(UIKit)
    /// Disables the default bottom bar that competes with the Gutenberg inserter
    ///
    override var inputAccessoryView: UIView? {
        nil
    }
    #endif
}
