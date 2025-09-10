import WebKit

class GBWebView: WKWebView {

    #if canImport(UIKit)
    /// Disables the default bottom bar that competes with the Gutenberg inserter
    ///
    override var inputAccessoryView: UIView? {
        nil
    }
    #endif
}
