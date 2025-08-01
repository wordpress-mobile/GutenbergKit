import UIKit
@preconcurrency import WebKit
import SwiftUI
import Combine
import CryptoKit

@MainActor
public final class EditorViewController: UIViewController, GutenbergEditorControllerDelegate {
    public let webView: WKWebView
    let assetsLibrary: EditorAssetsLibrary

    public var configuration: EditorConfiguration
    private var _isEditorRendered = false
    private var _isEditorSetup = false
    private let controller: GutenbergEditorController
    private let timestampInit = CFAbsoluteTimeGetCurrent()

    public private(set) var state = EditorState()

    public weak var delegate: EditorViewControllerDelegate?

    private var cancellables: [AnyCancellable] = []

    /// Warmup mode preloads resources into memory to make the UI transition seamless when displaying the editor for the first time
    ///
    private let isWarmupMode: Bool

    /// Initalizes the editor with the initial content (Gutenberg).
    public init(configuration: EditorConfiguration = .default, isWarmupMode: Bool = false) {
        self.configuration = configuration
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

        // TODO: register it when editor is loaded
//        service.$rawBlockTypesResponseData.compactMap({ $0 }).sink { [weak self] data in
//            guard let self else { return }
//            assert(Thread.isMainThread)
//
//        }.store(in: &cancellables)
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

    private func setUpEditor() {
        let webViewConfiguration = webView.configuration
        let userContentController = webViewConfiguration.userContentController
        let editorInitialConfig = getEditorConfiguration()
        userContentController.addUserScript(editorInitialConfig)
    }

    private func loadEditor() {
        if configuration.plugins {
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
        let escapedTitle = configuration.title.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let escapedContent = configuration.content.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!

        // Generate JavaScript globals
        let globalsJS = configuration.webViewGlobals.map { global in
            "window[\"\(global.name)\"] = \(global.value.toJavaScript());"
        }.joined(separator: "\n")

        // Convert editor settings to JSON string if available
        var editorSettingsJS = "undefined"
        if let settings = configuration.editorSettings {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: settings, options: [])
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    editorSettingsJS = jsonString
                }
            } catch {
                NSLog("Failed to serialize editor settings: \(error)")
            }
        }

        let jsCode = """
        \(globalsJS)

        window.GBKit = {
            siteURL: '\(configuration.siteURL)',
            siteApiRoot: '\(configuration.siteApiRoot)',
            siteApiNamespace: \(Array(configuration.siteApiNamespace)),
            namespaceExcludedPaths: \(Array(configuration.namespaceExcludedPaths)),
            authHeader: '\(configuration.authHeader)',
            themeStyles: \(configuration.themeStyles),
            hideTitle: \(configuration.hideTitle),
            editorSettings: \(editorSettingsJS),
            locale: '\(configuration.locale)',
            enableNativeBlockInserter: \(configuration.enableNativeBlockInserter),
            post: {
                id: \(configuration.postID ?? -1),
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

    private func showBlockInserter(blockTypes: [EditorBlockType]) {
        let view = BlockInserterView(blockTypes: blockTypes) { [weak self] selectedBlockType in
            self?.insertBlock(selectedBlockType)
        }
        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear

        // Configure sheet presentation with medium detent
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.custom(identifier: .medium, resolver: { context in
                context.containerTraitCollection.horizontalSizeClass == .compact ? 508 : 900
            }), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        }

        present(host, animated: true)
    }
    
    private func insertBlock(_ blockType: EditorBlockType) {
        evaluate("window.editor.insertBlock('\(blockType.name)');")
    }

    private func openMediaLibrary(_ config: OpenMediaLibraryAction) {
        delegate?.editor(self, didRequestMediaFromSiteMediaLibrary: config)
    }

    public func setMediaUploadAttachment(_ media: String) {
        evaluate("editor.setMediaUploadAttachment(\(media));")
    }

    // MARK: - GutenbergEditorControllerDelegate

    fileprivate func controller(_ controller: GutenbergEditorController, didReceiveMessage message: EditorJSMessage) {
        print("Received message type: \(message.type)")
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
            case .showBlockPicker:
                do {
                    let body = try message.decode(EditorJSMessage.ShowBlockPickerBody.self)
                    showBlockInserter(blockTypes: body.blockTypes)
                } catch {
                    showBlockInserter(blockTypes: [])
                }
            case .openMediaLibrary:
                let config = try message.decode(OpenMediaLibraryAction.self)
                openMediaLibrary(config)
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
        
        // Auto-focus the editor after it loads if configured
        if configuration.autoFocusOnLoad {
            autoFocusEditor()
        }
    }
    
    private func autoFocusEditor() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.simulateTapOnWebView()
        }
    }
    
    private func simulateTapOnWebView() {
        // Use a hidden text field to trigger keyboard, then transfer focus
        let hiddenTextField = UITextField(frame: CGRect(x: -100, y: -100, width: 1, height: 1))
        hiddenTextField.autocorrectionType = .no
        hiddenTextField.autocapitalizationType = .none
        view.addSubview(hiddenTextField)
        
        // Focus the hidden field to bring up keyboard
        hiddenTextField.becomeFirstResponder()
        
        // After a short delay, transfer focus to web view
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            hiddenTextField.removeFromSuperview()
            self?.webView.becomeFirstResponder()
            
            // Try one more JavaScript focus attempt with keyboard already up
            let focusScript = """
            (function() {
                const editable = document.querySelector('[contenteditable="true"]');
                if (editable) {
                    editable.focus();
                    editable.click();
                }
            })();
            """
            self?.evaluate(focusScript)
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

private class EditorAssetsProvider: NSObject, WKScriptMessageHandlerWithReply {
    let library: EditorAssetsLibrary

    init(library: EditorAssetsLibrary) {
        self.library = library
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard let payload = message.body as? NSDictionary,
              let asset = payload.object(forKey: "asset") as? String,
              asset == "manifest"
        else {
            replyHandler(nil, "Unexpected message")
            return
        }

        Task.detached { [library] in
            do {
                let data = try await library.manifestContentForEditor()
                let dict = try JSONSerialization.jsonObject(with: data)
                await replyHandler(dict, nil)
            } catch {
                await replyHandler(nil, error.localizedDescription)
            }
        }
    }
}

class CachedAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    nonisolated static let cachedURLSchemePrefix = "gbk-cache-"
    nonisolated static let supportedURLSchemes = ["gbk-cache-http", "gbk-cache-https"]

    nonisolated static func originalHTTPURL(from url: URL) -> URL? {
        guard let scheme = url.scheme, supportedURLSchemes.contains(scheme) else { return nil }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return nil
        }

        components.scheme = String(scheme.suffix(from: scheme.index(scheme.startIndex, offsetBy: cachedURLSchemePrefix.count)))
        return components.url
    }

    nonisolated static func cachedURL(forWebLink link: String) -> String? {
        if link.starts(with: "http://") || link.starts(with: "https://") {
            return cachedURLSchemePrefix + link
        }
        return nil
    }

    let worker: Worker

    init(library: EditorAssetsLibrary) {
        self.worker = .init(library: library)
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        Task {
            await worker.start(urlSchemeTask)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        Task {
            await worker.stop(urlSchemeTask)
        }
    }

    actor Worker {
         struct TaskInfo {
             var webViewTask: WKURLSchemeTask
             var fetchAssetTask: Task<Void, Never>

             func cancel() {
                 fetchAssetTask.cancel()
             }
        }

        let library: EditorAssetsLibrary
        var tasks: [ObjectIdentifier: TaskInfo] = [:]

        init(library: EditorAssetsLibrary) {
            self.library = library
        }

        deinit {
            for (_, task) in tasks {
                task.cancel()
            }
        }

        func start(_ task: WKURLSchemeTask) {
            guard let url = task.request.url, let httpURL = CachedAssetSchemeHandler.originalHTTPURL(from: url) else {
                task.didFailWithError(URLError(.badURL))
                return
            }

            let taskKey = ObjectIdentifier(task)

            let fetchAssetTask = Task { [library, weak self] in
                do {
                    let localURL = try await library.cacheAsset(from: httpURL)
                    assert(localURL.isFileURL)

                    let content = try Data(contentsOf: localURL)
                    let mimeType: String = switch httpURL.pathExtension {
                    case "js": "application/javascript"
                    case "css": "text/css"
                    default: "application/octet-stream"
                    }
                    let response = URLResponse(url: url, mimeType: mimeType, expectedContentLength: content.count, textEncodingName: nil)

                    await self?.tasks[taskKey]?.webViewTask.didReceive(response)
                    await self?.tasks[taskKey]?.webViewTask.didReceive(content)

                    await self?.finish(with: nil, taskKey: taskKey)
                } catch {
                    await self?.finish(with: error, taskKey: taskKey)
                }
            }
            tasks[taskKey] = .init(webViewTask: task, fetchAssetTask: fetchAssetTask)
        }

        func stop(_ task: WKURLSchemeTask) {
            let taskKey = ObjectIdentifier(task)
            tasks[taskKey]?.cancel()
            tasks[taskKey] = nil
        }

        private func finish(with error: Error?, taskKey: ObjectIdentifier) {
            guard let task = tasks[taskKey] else { return }

            if let error {
                task.webViewTask.didFailWithError(error)
            } else {
                task.webViewTask.didFinish()
            }
            tasks[taskKey] = nil
        }
    }
}
