import WebKit

protocol GBWebViewDelegate {
    @MainActor
    func webView(_ webView: GBWebView, didReceiveMessage: EditorJSMessage)
}

public class GBWebView: WKWebView {

    init() {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        #if(os(iOS))
        // This is important so they user can't select anything but text across blocks.
        // config.selectionGranularity = WKSelectionGranularity.character
        #endif

        super.init(frame: .zero, configuration: config)
        self.navigationDelegate = self

        // Set-up communications with the editor.
        config.userContentController.add(self, name: "editorDelegate")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor
    var delegate: GBWebViewDelegate?

    #if canImport(UIKit)
    /// Disables the default bottom bar that competes with the Gutenberg inserter
    ///
    public override var inputAccessoryView: UIView? {
        nil
    }
    #endif

    func addUserScript(_ script: WKUserScript) {
        self.configuration.userContentController.addUserScript(script)
    }
}

extension GBWebView: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let message = EditorJSMessage(message: message) else {
            return NSLog("Unsupported message: \(message.body)")
        }

        MainActor.assumeIsolated {
            delegate?.webView(self, didReceiveMessage: message)
        }
    }
}

extension GBWebView: WKNavigationDelegate {

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        NSLog("didFinish navigation: \(String(describing: navigation))")
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("didFailNavigation: \(error)")
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("didFailProvisionalNavigation: \(error)")
    }
}
