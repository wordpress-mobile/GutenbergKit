import UIKit
import SwiftUI
import WebKit

final class GutenbergViewController: UIViewController, WKNavigationDelegate{
    private var reactAppURL: URL!
    private var webView: WKWebView!


    let buttonOpenEditor = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Editor"

        buttonOpenEditor.setTitle("Launch Editor", for: [])


        reactAppURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "build")

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

        view.addSubview(buttonOpenEditor)
        buttonOpenEditor.addTarget(self, action: #selector(buttonEditorTapped), for: .touchUpInside)
        buttonOpenEditor.tintColor = .systemBlue

    }

    @objc private func buttonEditorTapped() {
        webView.loadFileURL(reactAppURL, allowingReadAccessTo: Bundle.main.resourceURL!)
        buttonOpenEditor.isHidden = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        buttonOpenEditor.sizeToFit()
        buttonOpenEditor.center = CGPoint(x: view.bounds.width / 2, y: view.bounds.height / 2)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("didFailNavigation: \(error)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("didFailProvisionalNavigation: \(error)")
    }
}
