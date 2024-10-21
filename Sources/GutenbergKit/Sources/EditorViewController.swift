import WebKit
import SwiftUI
import Combine

#if canImport(UIKit)
import UIKit
public typealias VCRepresentable = UIViewController
#elseif canImport(AppKit)
import AppKit
public typealias VCRepresentable = NSViewController
#endif

@MainActor
public final class EditorViewController: VCRepresentable {
    public var developmentEnvironmentUrl: URL?

    fileprivate let webView: GBWebView = GBWebView()

    fileprivate let timestampInit = CFAbsoluteTimeGetCurrent()
    fileprivate let service: EditorService

    public private(set) var state = EditorState()

    public weak var delegate: EditorViewControllerDelegate?
    private let viewModel: EditorViewModel

    public init(viewModel: EditorViewModel, service: EditorService) {
        self.viewModel = viewModel
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func handleError(_ error: Error, isCritical: Bool) {
#if canImport(UIKit)
        // These are non-critical errors but they might prevent certain features from working
        let alert = UIAlertController(title: error.localizedDescription, message: "\(error)", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            if isCritical {
                self.delegate?.editor(self, didEncounterCriticalError: error)
            }
        })
        present(alert, animated: true)
#endif
    }

    public var isDebuggingEnabled: Bool {
        get {
            if #available(iOS 16.4, *) {
                return webView.isInspectable
            } else {
                return false
            }
        }
        set {
            if #available(iOS 16.4, *) {
                webView.isInspectable = newValue
            }
        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(webView)

#if canImport(UIKit)
        view.backgroundColor = .red
        webView.backgroundColor = .blue
#else
        view.layer?.backgroundColor = CGColor(red: 1.0, green: 0, blue: 0, alpha: 1.0)
        webView.layer?.backgroundColor = CGColor(red: 0, green: 1.00, blue: 0, alpha: 1.0)
#endif

#if canImport(UIKit)
        // FIXME: implement with CSS (bottom toolbar)
        webView.scrollView.verticalScrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: 47, right: 0)
#endif

        webView.translatesAutoresizingMaskIntoConstraints = false

#if canImport(UIKit)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        ])
#else
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
#endif

        self.setUpEditor()
        self.loadEditor()
    }

#if canImport(UIKit)
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.webView.becomeFirstResponder()
    }
#endif

#if canImport(AppKit)
    public override func viewDidAppear() {
        super.viewDidAppear()
        self.webView.becomeFirstResponder()
    }
#endif

    private func setUpEditor() {
        self.webView.addUserScript(getEditorConfiguration())
        self.webView.delegate = self
    }

    func loadEditor() {
        var editorUrl = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Gutenberg")!

        if let developmentEnvironmentUrl {
            editorUrl = developmentEnvironmentUrl
        }

        if ProcessInfo.processInfo.environment.keys.contains("GUTENBERG_EDITOR_URL") {
            if let url = URL(string: ProcessInfo.processInfo.environment["GUTENBERG_EDITOR_URL"]!) {
                editorUrl = url
            }
        }

        if self.viewModel.features.contains(.Plugins) {
            if let url = Bundle.module.url(forResource: "remote", withExtension: "html", subdirectory: "Gutenberg") {
                editorUrl = url
            }
        }

        if editorUrl.isFileURL {
            webView.loadFileURL(editorUrl, allowingReadAccessTo: Bundle.module.resourceURL!)
        } else {
            webView.load(URLRequest(url: editorUrl))
        }
    }

    fileprivate func didLoadEditor() {
        //        guard !_isEditorRendered else { return }
        //        _isEditorRendered = true

        let duration = CFAbsoluteTimeGetCurrent() - timestampInit
        print("gutenbergkit-measure_editor-first-render:", duration)

    }

    private func getEditorConfiguration() -> WKUserScript {

        let escapedTitle = viewModel.initialTitle.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let escapedContent = viewModel.initialContent.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let hasThemeStylesEnabled = viewModel.features.contains(.ThemeStyles)

        let jsCode = """
        window.GBKit = {
            siteURL: '\(viewModel.siteURL)',
            siteApiRoot: '\(viewModel.siteApiRoot)',
            siteApiNamespace: '\(viewModel.siteApiNamespace)',
            authHeader: '\(viewModel.authHeader)',
            themeStyles: \(hasThemeStylesEnabled),
            post: {
                id: \(viewModel.id ?? -1),
                title: '\(escapedTitle)',
                content: '\(escapedContent)'
            },
        };
        localStorage.setItem('GBKit', JSON.stringify(window.GBKit));
        "done";
        """

        let editorScript = WKUserScript(source: jsCode, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        return editorScript
    }

    private func evaluate(_ javascript: String, isCritical: Bool = false) {
        webView.evaluateJavaScript(javascript) { [weak self] _, error in
            guard let self, let error else { return }
            self.handleError(error, isCritical: isCritical)
        }
    }

    public func setContent(_ newValue: String) {
        let escapedString = newValue.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        evaluate("editor.setContent(decodeURIComponent('\(escapedString)'));", isCritical: true)
    }

    /// Returns the current editor title and content.
    public func getTitleAndContent() async throws -> EditorTitleAndContent {
        let result = try await webView.evaluateJavaScript("editor.getTitleAndContent();")
        guard let dictionary = result as? [String: Any],
              let title = dictionary["title"] as? String,
              let content = dictionary["content"] as? String else {
            throw NSError(domain: "Invalid data format", code: 0, userInfo: nil)
        }
        return EditorTitleAndContent(title: title, content: content)
    }
}

extension EditorViewController: GBWebViewDelegate {
    func webView(_ webView: GBWebView, didReceiveMessage message: EditorJSMessage) {
        switch message.type {
            case .onEditorLoaded: didLoadEditor()
            case .onEditorContentChanged:
                // TODO: Refactor and remove EditorState entirely?
                delegate?.editor(self, didUpdateContentWithState: state)
        }
    }
}
