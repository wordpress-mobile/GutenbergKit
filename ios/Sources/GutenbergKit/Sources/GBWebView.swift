import WebKit

class GBWebView: WKWebView {
    
    /// The GutenbergKit version string
    static let version = "0.11.1"
    
    /// Cached default user agent, lazily initialized
    private static let defaultUserAgent: String = {
        // Use a temporary WKWebView to get the default user agent
        // We need to use evaluateJavaScript since customUserAgent is write-only
        let webView = WKWebView()
        let semaphore = DispatchSemaphore(value: 0)
        var userAgent = ""
        
        webView.evaluateJavaScript("navigator.userAgent") { result, error in
            if let result = result as? String {
                userAgent = result
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        return userAgent
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
