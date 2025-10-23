@preconcurrency import WebKit
import SwiftUI
import Combine
import CryptoKit

#if canImport(UIKit)
import UIKit

@MainActor
public final class EditorViewController: UIViewController, GutenbergEditorControllerDelegate {
    public let webView: WKWebView
    let assetsLibrary: EditorAssetsLibrary

    public var configuration: EditorConfiguration
    private var _isEditorRendered = false
    private var _isEditorSetup = false
    private let mediaPicker: MediaPickerController?
    private let controller: GutenbergEditorController
    private let timestampInit = CFAbsoluteTimeGetCurrent()

    public private(set) var state = EditorState()

    public weak var delegate: EditorViewControllerDelegate?

    private var cancellables: [AnyCancellable] = []

    /// Warmup mode preloads resources into memory to make the UI transition seamless when displaying the editor for the first time
    ///
    private let isWarmupMode: Bool

    /// Initalizes the editor with the initial content (Gutenberg).
    public init(
        configuration: EditorConfiguration = .default,
        mediaPicker: MediaPickerController? = nil,
        isWarmupMode: Bool = false
    ) {
        self.configuration = configuration
        self.mediaPicker = mediaPicker
        self.assetsLibrary = EditorAssetsLibrary(configuration: configuration)
        self.controller = GutenbergEditorController(configuration: configuration)

        // The `allowFileAccessFromFileURLs` allows the web view to access the
        // files from the local filesystem.
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        // Set-up communications with the editor.
        config.userContentController.add(controller, name: "editorDelegate")

        // This is important so they user can't select anything but text across blocks.
        config.selectionGranularity = .character

        let schemeHandler = CachedAssetSchemeHandler(library: assetsLibrary)
        for scheme in CachedAssetSchemeHandler.supportedURLSchemes {
            config.setURLSchemeHandler(schemeHandler, forURLScheme: scheme)
        }

        self.webView = GBWebView(frame: .zero, configuration: config)
        self.webView.scrollView.keyboardDismissMode = .interactive

        self.isWarmupMode = isWarmupMode

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

        if isWarmupMode {
            setUpEditor()
            loadEditor()
        }
    }

    private func setUpEditor() {
        let webViewConfiguration = webView.configuration
        let userContentController = webViewConfiguration.userContentController
        let editorInitialConfig = getEditorConfiguration()
        userContentController.addUserScript(editorInitialConfig)
    }

    private func loadEditor() {
        if configuration.shouldUsePlugins {
            webView.configuration.userContentController.addScriptMessageHandler(
                EditorAssetsProvider(library: assetsLibrary),
                contentWorld: .page,
                name: "loadFetchedEditorAssets"
            )

            if let remoteURL = ProcessInfo.processInfo.environment["GUTENBERG_EDITOR_REMOTE_URL"].flatMap(URL.init) {
                webView.load(URLRequest(url: remoteURL))
            } else {
                let remoteURL = Bundle.module.url(forResource: "remote", withExtension: "html", subdirectory: "Gutenberg")!
                webView.loadFileURL(remoteURL, allowingReadAccessTo: Bundle.module.resourceURL!)
            }
        } else if let editorURL = ProcessInfo.processInfo.environment["GUTENBERG_EDITOR_URL"].flatMap(URL.init) {
            webView.load(URLRequest(url: editorURL))
        } else {
            let indexURL = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Gutenberg")!
            webView.loadFileURL(indexURL, allowingReadAccessTo: Bundle.module.resourceURL!)
        }
    }

    private func getEditorConfiguration() -> WKUserScript {

        let jsCode = """

        window.GBKit = {
            siteURL: '\(configuration.siteURL)',
            siteApiRoot: '\(configuration.siteApiRoot)',
            siteApiNamespace: \(Array(configuration.siteApiNamespace)),
            namespaceExcludedPaths: \(Array(configuration.namespaceExcludedPaths)),
            authHeader: '\(configuration.authHeader)',
            themeStyles: \(configuration.shouldUseThemeStyles),
            enableNativeBlockInserter: \(configuration.isNativeInserterEnabled),
            hideTitle: \(configuration.shouldHideTitle),
            editorSettings: \(configuration.editorSettings),
            locale: '\(configuration.locale)',
            post: {
                id: \(configuration.postID ?? -1),
                title: '\(configuration.escapedTitle)',
                content: '\(configuration.escapedContent)'
            },
        };

        localStorage.setItem('GBKit', JSON.stringify(window.GBKit));

        "done";
        """

        let editorScript = WKUserScript(source: jsCode, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        return editorScript
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
        evaluate("editor.setContent('\(escapedString)');", isCritical: true)
    }

    /// Returns the current editor content.
    public func getContent() async throws -> String {
        try await webView.evaluateJavaScript("editor.getContent();") as! String
    }

    /// Returns the current editor title and content.
    public func getTitleAndContent() async throws -> EditorTitleAndContent {
        let result = try await webView.evaluateJavaScript("editor.getTitleAndContent();")
        guard let dictionary = result as? [String: Any],
              let title = dictionary["title"] as? String,
              let content = dictionary["content"] as? String,
              let changed = dictionary["changed"] as? Bool else {
            throw NSError(domain: "Invalid data format", code: 0, userInfo: nil)
        }
        return EditorTitleAndContent(title: title, content: content, changed: changed)
    }

    /// Steps backwards in the editor history state
    public func undo() {
        evaluate("editor.undo();")
    }

    /// Steps forwards in the editor history state
    public func redo() {
        evaluate("editor.redo();")
    }

    /// Dismisses the topmost modal dialog or menu in the editor
    public func dismissTopModal() {
        evaluate("editor.dismissTopModal();")
    }

    /// Enables code editor.
    public var isCodeEditorEnabled: Bool = false {
        didSet {
            guard isCodeEditorEnabled != oldValue else { return }
            evaluate("editor.switchEditorMode('\(isCodeEditorEnabled ? "text" : "visual")');")
        }
    }

    /// Updates the editor configuration
    public func updateConfiguration(_ newConfiguration: EditorConfiguration) {
        self.configuration = newConfiguration
    }

    /// Starts the editor setup process
    public func startEditorSetup() {
        guard !_isEditorSetup else { return }
        _isEditorSetup = true

        setUpEditor()
        loadEditor()
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

    private func showBlockInserter(blocks: [EditorBlock]) {
        let context = MediaPickerPresentationContext()

        let host = UIHostingController(rootView: NavigationStack {
            BlockInserterView(
                blocks: blocks,
                mediaPicker: mediaPicker,
                presentationContext: context,
                onBlockSelected: {
                    print("insert blocks:", $0)
                },
                onMediaSelected: {
                    print("insert media:", $0)
                }
            )
        })

        context.viewController = host

        present(host, animated: true)
    }

    private func openMediaLibrary(_ config: OpenMediaLibraryAction) {
        delegate?.editor(self, didRequestMediaFromSiteMediaLibrary: config)
    }

    public func setMediaUploadAttachment(_ media: String) {
        evaluate("editor.setMediaUploadAttachment(\(media));")
    }

    /// Appends text at the current cursor position in the editor.
    ///
    /// - parameter text: The text to append at the cursor position.
    public func appendTextAtCursor(_ text: String) {
        let escapedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        evaluate("editor.appendTextAtCursor(decodeURIComponent('\(escapedText)'));")
    }

    // MARK: - GutenbergEditorControllerDelegate

    fileprivate func controller(_ controller: GutenbergEditorController, didReceiveMessage message: EditorJSMessage) {
        do {
            switch message.type {
            case .onEditorLoaded:
                didLoadEditor()
            case .onEditorContentChanged:
                // TODO: Refactor and remove EditorState entirely?
                delegate?.editor(self, didUpdateContentWithState: state)
            case .onEditorHistoryChanged:
                let body = try message.decode(EditorJSMessage.DidUpdateEditorHistoryBody.self)
                self.state.hasUndo = body.hasUndo
                self.state.hasRedo = body.hasRedo
                delegate?.editor(self, didUpdateHistoryState: state)
            case .onEditorFeaturedImageChanged:
                let body = try message.decode(EditorJSMessage.DidUpdateFeaturedImageBody.self)
                delegate?.editor(self, didUpdateFeaturedImage: body.mediaID)
            case .onEditorExceptionLogged:
                guard let exception = message.body as? [String: Any],
                  let editorException = GutenbergJSException(from: exception) else {
                    return
                }
                delegate?.editor(self, didLogException: editorException)
            case .showBlockInserter:
                let body = try message.decode(EditorJSMessage.ShowBlockInserterBody.self)
                showBlockInserter(blocks: body.blocks)
            case .openMediaLibrary:
                let config = try message.decode(OpenMediaLibraryAction.self)
                openMediaLibrary(config)
            case .onAutocompleterTriggered:
                let body = try message.decode(EditorJSMessage.AutocompleterTriggeredBody.self)
                delegate?.editor(self, didTriggerAutocompleter: body.type)
            case .onModalDialogOpened:
                let body = try message.decode(EditorJSMessage.ModalDialogBody.self)
                delegate?.editor(self, didOpenModalDialog: body.dialogType)
            case .onModalDialogClosed:
                let body = try message.decode(EditorJSMessage.ModalDialogBody.self)
                delegate?.editor(self, didCloseModalDialog: body.dialogType)
            }
        } catch {
            fatalError("failed to decode message: \(error)")
        }
    }

    // Only after this point it's safe to use JS `editor` API.
    private func didLoadEditor() {
        guard !_isEditorRendered else { return }
        _isEditorRendered = true

        UIView.animate(withDuration: 0.2, delay: 0.1, options: [.allowUserInteraction]) {
            self.webView.alpha = 1
        }

        let duration = CFAbsoluteTimeGetCurrent() - timestampInit
        print("gutenbergkit-measure_editor-first-render:", duration)
        delegate?.editorDidLoad(self)

        if configuration.content.isEmpty {
            evaluate("editor.focus();")
        }
    }

    // MARK: - Warmup

    /// Calls this at any moment before showing the actual editor. The warmup
    /// shaves a couple of hundred milliseconds off the first load.
    public static func warmup(configuration: EditorConfiguration = .default) {
        let editorViewController = EditorViewController(configuration: configuration, isWarmupMode: true)
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
    private let configuration: EditorConfiguration
    private let editorURL: URL?

    init(configuration: EditorConfiguration) {
        self.configuration = configuration
        self.editorURL = ProcessInfo.processInfo.environment["GUTENBERG_EDITOR_URL"].flatMap(URL.init)
        super.init()
    }

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

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if navigationAction.navigationType == .linkActivated {
            // Open the request in OS browser
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
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


#endif
