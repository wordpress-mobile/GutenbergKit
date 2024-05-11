import UIKit
import SwiftUI
import WebKit

public struct EditorView: View {
    public init() {}

    public var body: some View {
        _EditorView()
    }
}

struct _EditorView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> GutenbergViewController {
        GutenbergViewController()
    }

    func updateUIViewController(_ uiViewController: GutenbergViewController, context: Context) {
        // Do nothing
    }
}

final class GutenbergViewController: UIViewController, WKNavigationDelegate{
    private var reactAppURL: URL!
    private var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Editor"

        reactAppURL = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Gutenberg")

        // configuring the `WKWebView` is very important
        // without doing this the local index.html will not be able to read
        // the css or js files properly
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        // set the configuration on the `WKWebView`
        // don't worry about the frame: .zero, SwiftUI will resize the `WKWebView` to
        // fit the parent
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        self.webView = webView

        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        loadEditor()
    }

    private func loadEditor() {
        webView.loadFileURL(reactAppURL, allowingReadAccessTo: Bundle.main.resourceURL!)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("didFailNavigation: \(error)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("didFailProvisionalNavigation: \(error)")
    }
}

struct EditorView_Preview: PreviewProvider {
    static var previews: some View {
        EditorView()
    }
}
