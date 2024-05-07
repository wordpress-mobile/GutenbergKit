import UIKit
import SwiftUI
import WebKit

final class GutenbergViewController: UIViewController {
    private var reactAppURL: URL!

    override func viewDidLoad() {
        super.viewDidLoad()

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
        // now load the local url
        webView.loadFileURL(reactAppURL, allowingReadAccessTo: reactAppURL)


        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
