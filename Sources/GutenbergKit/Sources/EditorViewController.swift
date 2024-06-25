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

        registerService()
        loadEditor()
    }

    private func registerService() {
        // TODO: pass block types
        service.$blockTypes.filter({ !$0.isEmpty }).sink { [weak self] blockTypes in
            guard let self else { return }
            assert(Thread.isMainThread)
            webView.evaluateJavaScript("""
            editor.registerBlocks([{name:"paragraph"}]);
            """)
        }.store(in: &cancellables)
    }

    private func loadEditor() {
        let reactAppURL = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Gutenberg")!
        webView.loadFileURL(reactAppURL, allowingReadAccessTo: Bundle.module.resourceURL!)
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
        webView.evaluateJavaScript("""
        editor.setContent(decodeURIComponent('\(escapedString)'));
        """)
    }

    /// Returns the current editor content.
    public func getContent() async throws -> String {
        try await webView.evaluateJavaScript("editor.getContent();") as! String
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
            case .onSheetVisibilityUpdated:
                let body = try message.decode(EditorJSMessage.SheetVisibilityUpdatedBody.self)
                delegate?.editor(self, didUpdateSheetVisibility: body.isShown)
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

        Task {
            await setInitialContent(_initialRawContent)
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
