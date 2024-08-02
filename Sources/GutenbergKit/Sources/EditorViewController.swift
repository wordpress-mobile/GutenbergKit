import UIKit
import WebKit
import SwiftUI
import Combine

@MainActor
public final class EditorViewController: UIViewController, GutenbergEditorControllerDelegate {
    public let webView: WKWebView
    private var _initialRawContent: String
    private var _isEditorRendered = false
    private let controller = GutenbergEditorController()
    private let timestampInit = CFAbsoluteTimeGetCurrent()
    private let service: EditorService

    public private(set) var state = EditorState()

    public weak var delegate: EditorViewControllerDelegate?

    /// Returns `true` if the editor is loaded and the initial content is displayed.
    public var isEditorLoaded: Bool { initialContent != nil }

    /// The content that the editor was initialized with, serialized according
    /// to the editor's settings.
    ///
    /// - warning: Checking raw `content` for equality is not a reliable operation
    /// due to the various formatting choices Gutenberg and WordPress make when
    /// saving the posts.
    public private(set) var initialContent: String?

    /// A custom URL for the editor.
    public var editorURL: URL?

    private var cancellables: [AnyCancellable] = []

    /// Initalizes the editor with the initial content (Gutenberg).
    public init(content: String = "", service: EditorService) {
        self._initialRawContent = content
        self.service = service

        Task {
            await service.warmup()
        }

        // The `allowFileAccessFromFileURLs` allows the web view to access the
        // files from the local filesystem.
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        // Set-up communications with the editor.
        config.userContentController.add(controller, name: "editorDelegate")

        // This is important so they user can't select anything but text across blocks.
        config.selectionGranularity = .character

        self.webView = WKWebView(frame: .zero, configuration: config)

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        controller.delegate = self
        webView.navigationDelegate = controller

        // FIXME: implement with CSS (bottom toolbar)
        webView.scrollView.verticalScrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: 47, right: 0)

        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        ])

        webView.alpha = 0

        // TODO: register it when editor is loaded
//        service.$rawBlockTypesResponseData.compactMap({ $0 }).sink { [weak self] data in
//            guard let self else { return }
//            assert(Thread.isMainThread)
//
//        }.store(in: &cancellables)

        loadEditor()
    }

    // TODO: move
    private func registerBlockTypes(data: Data) async {
        guard let string = String(data: data, encoding: .utf8),
            let escapedString = string.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else {
            assertionFailure("invalid block types")
            return
        }
        do {
            // TODO: simplify this
            try await webView.evaluateJavaScript("""
                const blockTypes = JSON.parse(decodeURIComponent('\(escapedString)'));
                editor.registerBlocks(blockTypes);
                "done";
                """)
        } catch {
            NSLog("failed to register blocks \(error)")
            // TOOD: relay to the client
        }
    }

    private func loadEditor() {
        if let editorURL = editorURL ?? ProcessInfo.processInfo.environment["GUTENBERG_EDITOR_URL"].flatMap(URL.init) {
            webView.load(URLRequest(url: editorURL))
        } else {
            let reactAppURL = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Gutenberg")!
            let htmlContent = try! String(contentsOf: reactAppURL, encoding: .utf8)
            
            // Fetch environment variables
            if let siteURL = ProcessInfo.processInfo.environment["GUTENBERG_SITE_URL"],
               let username = ProcessInfo.processInfo.environment["GUTENBERG_APPLICATION_USER"],
               let appPassword = ProcessInfo.processInfo.environment["GUTENBERG_APPLICATION_PASSWORD"] {

                // Create a script tag string with the environment variables
                let scriptContent = """
                <script>
                (function() {
                    window.gb = window.gb || {};
                    window.gb.GUTENBERG_SITE_URL = '\(siteURL)';
                    window.gb.GUTENBERG_APPLICATION_USER = '\(username)';
                    window.gb.GUTENBERG_APPLICATION_PASSWORD = '\(appPassword)';
                })();
                </script>
                """

                // Insert the script tag just before the closing </head> tag
                let modifiedHTML = htmlContent.replacingOccurrences(of: "</head>", with: "\(scriptContent)</head>")

                // Load the modified HTML content
                webView.loadHTMLString(modifiedHTML, baseURL: reactAppURL.deletingLastPathComponent())
            } else {
                // If any environment variable is missing, load the file as is
                webView.loadFileURL(reactAppURL, allowingReadAccessTo: Bundle.module.resourceURL!)
            }
        }
    }

    // MARK: - Public API

    // TODO: synchronize with the editor user-generated updates
    // TODO: convert to a property?
    public func setContent(_ content: String) {
        _setContent(content)
    }

    private func _setContent(_ content: String) {
        guard _isEditorRendered else { return }

        let escapedString = content.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        evaluate("editor.setContent(decodeURIComponent('\(escapedString)'));", isCritical: true)
    }

    /// Returns the current editor content.
    public func getContent() async throws -> String {
        try await webView.evaluateJavaScript("editor.getContent();") as! String
    }

    /// Enables code editor.
    public var isCodeEditorEnabled: Bool = false {
        didSet {
            guard isCodeEditorEnabled != oldValue else { return }
            evaluate("editor.setCodeEditorEnabled(\(isCodeEditorEnabled ? "true" : "false"));")
        }
    }

    // MARK: - Internal (JavaScript)

    private func evaluate(_ javascript: String, isCritical: Bool = false) {
        webView.evaluateJavaScript(javascript) { [weak self] _, error in
            guard let self, let error else { return }
            self.handleError(error, isCritical: isCritical)
        }
    }

    private func handleError(_ error: Error, isCritical: Bool) {
        // These are non-critical errors but they might prevent certain features from working
        let alert = UIAlertController(title: error.localizedDescription, message: "\(error)", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            if isCritical {
                self.delegate?.editor(self, didEncounterCriticalError: error)
            }
        })
        present(alert, animated: true)
    }

    // MARK: - Internal (Block Inserter)

    // TODO: wire with JS and pass blocks
    private func showBlockInserter() {
        let viewModel = EditorBlockPickerViewModel(blockTypes: service.blockTypes)
        let view = NavigationView {
            EditorBlockPicker(viewModel: viewModel)
        }
        let host = UIHostingController(rootView: view)
        present(host, animated: true)
    }

    // MARK: - Internal (Initial Content)

    private func setInitialContent(_ content: String, _ completion: (() -> Void)? = nil) async {
        guard _isEditorRendered else { fatalError("called too early") }

        let start = CFAbsoluteTimeGetCurrent()

        // TODO: Find a faster and more reliable way to pass large strings to a web view
        let escapedString = content.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!

        // TODO: Check errors and notify the delegate when the editor is loaded and the content got displayed
        do {
            let serializedContent = try await webView.evaluateJavaScript("""
        editor.setInitialContent(decodeURIComponent('\(escapedString)'));
        """) as! String
            self.initialContent = serializedContent
            delegate?.editor(self, didDisplayInitialContent: serializedContent)
            print("gutenbergkit-set-initial-content:", CFAbsoluteTimeGetCurrent() - start)

            UIView.animate(withDuration: 0.2, delay: 0.1, options: [.allowUserInteraction]) {
                self.webView.alpha = 1
            }
        } catch {
            delegate?.editor(self, didEncounterCriticalError: error)
        }
    }

    // MARK: - GutenbergEditorControllerDelegate

    fileprivate func controller(_ controller: GutenbergEditorController, didReceiveMessage message: EditorJSMessage) {
        do {
            switch message.type {
            case .onEditorLoaded:
                didLoadEditor()
            case .onBlocksChanged:
                let body = try message.decode(EditorJSMessage.DidUpdateBlocksBody.self)
                self.state.isEmpty = body.isEmpty
                delegate?.editor(self, didUpdateContentWithState: state)
            case .showBlockPicker:
                showBlockInserter()
            }
        } catch {
            fatalError("failed to decode message: \(error)")
        }
    }

    // Only after this point it's safe to use JS `editor` API.
    private func didLoadEditor() {
        guard !_isEditorRendered else { return }
        _isEditorRendered = true

        let duration = CFAbsoluteTimeGetCurrent() - timestampInit
        print("gutenbergkit-measure_editor-first-render:", duration)

        // TODO: refactor (perform initial setup with a single JS call)
        Task { @MainActor in
            if let data = service.rawBlockTypesResponseData {
                await registerBlockTypes(data: data)
            }
            await setInitialContent(_initialRawContent)
        }
    }

    // MARK: - Warmup

    /// Calls this at any moment before showing the actual editor. The warmup
    /// shaves a couple of hundred milliseconds off the first load.
    public static func warmup() {
        struct MockClient: EditorNetworkingClient {
            func send(_ request: EditorNetworkRequest) async throws -> EditorNetworkResponse {
                throw URLError(.unknown) // Unsupported
            }
        }
        let editorViewController = EditorViewController(
            content: "",
            service: EditorService(client: MockClient())
        )
        _ = editorViewController.view // Trigger viewDidLoad

        // Retain for 5 seconds and let it prefetch stuff
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(5)) {
            _ = editorViewController
        }
    }
}

@MainActor
private protocol GutenbergEditorControllerDelegate: AnyObject {
    func controller(_ controller: GutenbergEditorController, didReceiveMessage message: EditorJSMessage)
}

/// Hiding the conformances, and breaking retain cycles.
private final class GutenbergEditorController: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    weak var delegate: GutenbergEditorControllerDelegate?

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        NSLog("navigation: \(String(describing: navigation))")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("didFailNavigation: \(error)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("didFailProvisionalNavigation: \(error)")
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let message = EditorJSMessage(message: message) else {
            return NSLog("Unsupported message: \(message.body)")
        }
        MainActor.assumeIsolated {
            delegate?.controller(self, didReceiveMessage: message)
        }
    }
}

private extension WKWebView {

}
