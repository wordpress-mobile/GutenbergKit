@preconcurrency import WebKit
import SwiftUI
import OSLog

#if canImport(UIKit)
import UIKit

@MainActor
public final class EditorViewController: UIViewController, GutenbergEditorControllerDelegate, UIAdaptivePresentationControllerDelegate, UIPopoverPresentationControllerDelegate, UISheetPresentationControllerDelegate {

    /// Represents the lifecycle state of the editor view controller.
    ///
    /// The editor progresses through these states as it initializes:
    ///
    /// ```
    /// +-------+      No deps       +---------+    Fetch complete    +--------+
    /// | start | -----------------> | loading | -------------------> | loaded |
    /// +-------+                    +---------+                      +--------+
    ///     |                                                              |
    ///     | Has deps                                                     |
    ///     +--------------------------------------------------------------+
    ///                                                                    |
    ///                                                               JS initialized
    ///                                                                    |
    ///                                                                    v
    ///                                                               +-------+
    ///                                                               | ready |
    ///                                                               +-------+
    /// ```
    ///
    /// Any state can transition to ``error(_:)`` if a fatal error occurs.
    ///
    /// ## State Descriptions
    ///
    /// - ``start``: Initial state before `viewDidLoad`. The editor has not begun initialization.
    /// - ``loading(_:)``: Fetching dependencies from the network. A progress bar is displayed.
    /// - ``loaded(_:)``: Dependencies are available and the WebView is loading HTML/JS. An activity indicator is shown.
    /// - ``ready(_:)``: The editor is fully initialized. JavaScript APIs (e.g., `editor.getContent()`) are now safe to call.
    /// - ``error(_:)``: A fatal error occurred. The error view is displayed and the delegate is notified.
    ///
    /// ## UI Behavior
    ///
    /// Each state transition triggers corresponding UI updates:
    /// - `start` -> `loading`: Shows progress bar
    /// - `loading` -> `loaded`: Hides progress bar, shows activity indicator
    /// - `loaded` -> `ready`: Hides activity indicator, reveals editor
    /// - Any -> `error`: Shows error view
    ///
    enum ViewState: Sendable, Equatable {

        /// Initial state before the view has loaded.
        ///
        /// This is the default state when the view controller is created. The editor
        /// transitions out of this state in `viewDidLoad`.
        case start

        /// Fetching editor dependencies from the network.
        ///
        /// The associated task represents the async work being performed. A progress
        /// bar is displayed to the user during this state.
        ///
        /// - Parameter task: The task fetching dependencies via `EditorService.prepare()`.
        case loading(Task<Void, Never>)

        /// Dependencies are loaded and the WebView is initializing.
        ///
        /// The editor HTML and JavaScript are being loaded into the WebView. An
        /// indeterminate activity indicator is shown during this brief phase.
        ///
        /// - Parameter dependencies: The pre-fetched editor dependencies.
        case loaded(EditorDependencies)

        /// The editor is fully initialized and ready for use.
        ///
        /// JavaScript APIs like `editor.getContent()`, `editor.setContent()`, `editor.undo()`,
        /// etc. are now safe to call. The editor UI is visible and interactive.
        ///
        /// - Parameter dependencies: The editor dependencies used for initialization.
        case ready(EditorDependencies)

        /// A fatal error occurred during initialization.
        ///
        /// The error view is displayed and the delegate's `editor(_:didEncounterCriticalError:)`
        /// method is called. The editor cannot recover from this state.
        ///
        /// - Parameter error: The error that caused initialization to fail.
        case error(Error)

        static func == (lhs: EditorViewController.ViewState, rhs: EditorViewController.ViewState) -> Bool {
            switch (lhs, rhs) {
            case (.start, .start): return true
            case (.loading, .loading): return true
            case (.loaded, .loaded): return true
            case (.ready, .ready): return true
            case (.error, .error): return true
            default: return false
            }
        }
    }

    @MainActor
    private var viewState: ViewState = .start  {
        willSet {
            if newValue == self.viewState {
                preconditionFailure("Invalid transition from `\(self.viewState)` to `\(newValue)")
            }
        }
        didSet {
            switch viewState {
            case .start:
                preconditionFailure("viewState should never transition back to `start`")
            case .loading:
                self.displayProgressView()
            case .loaded:
                self.hideProgressView()
                self.displayActivityView()
            case .ready:
                self.hideActivityView()
            case .error(let error):
                self.displayError(error)
                self.delegate?.editor(self, didEncounterCriticalError: error)
            }
        }
    }

    public let webView: WKWebView

    public var configuration: EditorConfiguration
    private let editorService: EditorService

    private let mediaPicker: MediaPickerController?
    private let controller: GutenbergEditorController
    private let timestampInit = CFAbsoluteTimeGetCurrent()
    private let bundleProvider = EditorAssetBundleProvider()

    /// Displays a progress bar indicating loading status
    private let progressView = UIEditorProgressView(loadingText: Strings.loadingEditor)

    /// Displays an indeterminate indicator while WebKit loads the JS code
    private let waitingView = UIActivityIndicatorView(style: .medium)

    private let errorViewController = EditorErrorViewController()

    public private(set) var state = EditorState()

    public weak var delegate: EditorViewControllerDelegate?

    /// Stores the contextId from the most recent openMediaLibrary call
    /// to pass back to JavaScript when media is selected
    private var currentMediaContextId: String?

    /// Warmup mode preloads resources into memory to make the UI transition seamless when displaying the editor for the first time
    private let isWarmupMode: Bool

    /// Overlay view shown over the navigation bar when modal dialogs are open
    private lazy var navigationOverlayView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        view.isUserInteractionEnabled = true
        view.isHidden =  true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// HTML Preview Manager instance for rendering pattern previews
    ///
    /// It is a fatal error to attempt to access this before the editor state is `ready`.
    ///
    private lazy var htmlPreviewManager: HTMLPreviewManager = {
        guard case .ready(let dependencies) = viewState else {
            preconditionFailure("Editor is not in a `.ready` state, cannot create HTMLPreviewManager")
        }

        return HTMLPreviewManager(themeStyles: dependencies.editorSettings.themeStyles)
    }()

    /// Initalizes the editor with the initial content (Gutenberg).
    public init(
        configuration: EditorConfiguration,
        dependencies: EditorDependencies? = nil,
        mediaPicker: MediaPickerController? = nil,
        isWarmupMode: Bool = false
    ) {
        self.configuration = configuration
        self.editorService = EditorService(configuration: configuration)
        self.mediaPicker = mediaPicker
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

        self.bundleProvider.bind(to: config)

        self.webView = GBWebView(frame: .zero, configuration: config)
        self.webView.scrollView.keyboardDismissMode = .interactive

        self.isWarmupMode = isWarmupMode

        super.init(nibName: nil, bundle: nil)

        if let dependencies {
            self.viewState = .loaded(dependencies)
        }
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
            self.loadEditorWithoutDependencies()
        }

        // If we don't have dependencies yet, we need to load them
        if case .start = viewState {
            self.viewState = .loading(self.loadEditorTask)
        }

        // If we already have the dependencies, we can just load the editor right away
        if case .loaded(let editorDependencies) = viewState {
            do {
                try self.loadEditor(dependencies: editorDependencies)
            } catch {
                self.viewState = .error(error)
            }
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setupNavigationOverlay()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        removeNavigationOverlay()
    }

    @MainActor
    private var loadEditorTask: Task<Void, Never> {
        Task(priority: .userInitiated) {
            do {
                let dependencies = try await self.editorService.prepare { @MainActor progress in
                    self.progressView.setProgress(progress, animated: true)
                }
                try self.loadEditor(dependencies: dependencies)

                self.viewState = .loaded(dependencies)
                
            } catch {
                self.viewState = .error(error)
            }
        }
    }

    @MainActor
    private func loadEditor(dependencies: EditorDependencies) throws {
        self.bundleProvider.set(bundle: dependencies.assetBundle)

        // Register the handler that provides the editor configuration
        let editorConfig = try buildEditorConfiguration(dependencies: dependencies)
        webView.configuration.userContentController.addUserScript(editorConfig)

        if let editorURL = ProcessInfo.processInfo.environment["GUTENBERG_EDITOR_URL"].flatMap(URL.init) {
            webView.load(URLRequest(url: editorURL))
        } else {
            let indexURL = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Gutenberg")!
            webView.loadFileURL(indexURL, allowingReadAccessTo: Bundle.module.resourceURL!)
        }
    }

    /// Load the editor without any external dependencies – this is useful for prewarming the JS
    ///
    private func loadEditorWithoutDependencies() {
        let indexURL = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Gutenberg")!
        webView.loadFileURL(indexURL, allowingReadAccessTo: Bundle.module.resourceURL!)
    }

    private func buildEditorConfiguration(dependencies: EditorDependencies) throws -> WKUserScript {
        let gbkitGlobal = try GBKitGlobal(configuration: self.configuration, dependencies: dependencies)
        let stringValue = try gbkitGlobal.toString()

        let jsCode = """
        window.GBKit = \(stringValue);
        localStorage.setItem('GBKit', JSON.stringify(window.GBKit));
        "done";
        """

        return WKUserScript(source: jsCode, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    /// Deletes all cached editor data for all sites
    public static func deleteAllData() throws {
        if FileManager.default.directoryExists(at: Paths.defaultCacheRoot) {
            try FileManager.default.removeItem(at: Paths.defaultCacheRoot)
        }

        if FileManager.default.directoryExists(at: Paths.defaultStorageRoot) {
            try FileManager.default.removeItem(at: Paths.defaultStorageRoot)
        }
    }

    // MARK: - Public API

    // TODO: synchronize with the editor user-generated updates
    // TODO: convert to a property?
    public func setContent(_ content: String) {
        _setContent(content)
    }

    private func _setContent(_ content: String) {
        guard case .ready = viewState else {
            return
        }

        let escapedString = content.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        evaluate("editor.setContent('\(escapedString)');", isCritical: true)
    }

    /// Returns the current editor content.
    public func getContent() async throws -> String {
        try await webView.evaluateJavaScript("editor.getContent();") as! String
    }

    public struct EditorTitleAndContent: Decodable {
        public let title: String
        public let content: String
        public let changed: Bool
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

    // MARK: - Internal (JavaScript)

    private func evaluate(_ javascript: String, isCritical: Bool = false) {
        webView.evaluateJavaScript(javascript) { [weak self] _, error in
            guard let self, let error else { return }
            self.handleError(error, isCritical: isCritical)
        }
    }

    private func makeJavaScriptCompatibleDictionary<T: Encodable>(with object: T) throws -> Any {
        let data = try JSONEncoder().encode(object)
        return try JSONSerialization.jsonObject(with: data, options: .allowFragments)
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

    private func showBlockInserter(data: EditorJSMessage.ShowBlockInserterBody) {
        let context = MediaPickerPresentationContext()

        let host = UIHostingController(rootView: NavigationStack {
            BlockInserterView(
                sections: data.sections,
                patterns: data.patterns,
                patternCategories: data.patternCategories,
                mediaPicker: mediaPicker,
                presentationContext: context,
                onSelection: { [weak self] in self?.didSelectBlockInserterItem($0) },
                onClose: { [weak self] in self?.notifyInserterClosed() }
            )
            .environmentObject(htmlPreviewManager)
        })

        context.viewController = host

        // Set presentation delegate to track dismissal
        host.presentationController?.delegate = self

        if let sourceRect = data.sourceRect {
            host.modalPresentationStyle = .popover

            if let popover = host.popoverPresentationController {
                popover.delegate = self
                popover.sourceView = webView
                popover.sourceRect = CGRect(
                    x: sourceRect.x,
                    y: sourceRect.y,
                    width: sourceRect.width,
                    height: sourceRect.height
                )
                popover.permittedArrowDirections = [.up, .down]
                host.preferredContentSize = CGSize(width: 600, height: 580)
            }
        }

        if let sheet = host.popoverPresentationController?.adaptiveSheetPresentationController ?? host.sheetPresentationController {
            sheet.delegate = self
            sheet.detents = [.custom(identifier: .medium, resolver: { context in
                context.containerTraitCollection.horizontalSizeClass == .compact ? 536 : 900
            }), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 26
        }

        present(host, animated: true)
    }

    private func didSelectBlockInserterItem(_ selection: BlockInserterSelection) {
        notifyInserterClosed()

        switch selection {
        case .block(let block):
            insertBlockFromInserter(block.id)
        case .pattern(let pattern):
            insertPatternFromInserter(pattern.name)
        case .media(let items):
            Task {
                await insertMediaFromInserter(items)
            }
        }
    }

    // MARK: - UIAdaptivePresentationControllerDelegate

    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        notifyInserterClosed()
    }

    private func notifyInserterClosed() {
        evaluate("window.blockInserter?.onClose?.()")
    }

    private func insertBlockFromInserter(_ blockID: String) {
        evaluate("window.blockInserter.insertBlock('\(blockID)')")
    }

    private func insertMediaFromInserter(_ selection: [MediaInfo]) async {
        guard !selection.isEmpty else { return }
        do {
            let object = try makeJavaScriptCompatibleDictionary(with: selection)
            _ = try await webView.callAsyncJavaScript(
                "window.blockInserter.insertMedia(selection)",
                arguments: ["selection": object],
                in: nil,
                contentWorld: .page
            )
        } catch {
            assertionFailure("Failed to serialize or insert media: \(error)")
        }
    }

    private func insertPatternFromInserter(_ patternName: String) {
        let escapedName = patternName.replacingOccurrences(of: "'", with: "\\'")
        evaluate("window.blockInserter.insertPattern('\(escapedName)')")
    }

    private func openMediaLibrary(_ config: OpenMediaLibraryAction) {
        // Store the contextId to pass back when media is selected
        currentMediaContextId = config.contextId
        delegate?.editor(self, didRequestMediaFromSiteMediaLibrary: config)
    }

    public func setMediaUploadAttachment(_ media: String) {
        guard let contextId = currentMediaContextId else {
            NSLog("setMediaUploadAttachment called without contextId")
            return
        }

        let escapedContextId = contextId.replacingOccurrences(of: "'", with: "\\'")
        evaluate("editor.setMediaUploadAttachment(\(media), '\(escapedContextId)');")

        currentMediaContextId = nil
    }

    /// Appends text at the current cursor position in the editor.
    ///
    /// - parameter text: The text to append at the cursor position.
    public func appendTextAtCursor(_ text: String) {
        let escapedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        evaluate("editor.appendTextAtCursor(decodeURIComponent('\(escapedText)'));")
    }

    // MARK: - Navigation Overlay

    private func setupNavigationOverlay() {
        guard let navigationController = navigationController,
                navigationOverlayView.superview == nil else { return }
        navigationController.view.addSubview(navigationOverlayView)
        NSLayoutConstraint.activate([
            navigationOverlayView.leadingAnchor.constraint(equalTo: navigationController.view.leadingAnchor),
            navigationOverlayView.trailingAnchor.constraint(equalTo: navigationController.view.trailingAnchor),
            navigationOverlayView.topAnchor.constraint(equalTo: navigationController.view.topAnchor),
            navigationOverlayView.bottomAnchor.constraint(equalTo: navigationController.navigationBar.bottomAnchor)
        ])
    }

    private func removeNavigationOverlay() {
        navigationOverlayView.removeFromSuperview()
    }

    private func showNavigationOverlay() {
        navigationOverlayView.isHidden = false
    }

    private func hideNavigationOverlay() {
        navigationOverlayView.isHidden = true
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
                showBlockInserter(data: body)
            case .openMediaLibrary:
                let config = try message.decode(OpenMediaLibraryAction.self)
                openMediaLibrary(config)
            case .onAutocompleterTriggered:
                let body = try message.decode(EditorJSMessage.AutocompleterTriggeredBody.self)
                delegate?.editor(self, didTriggerAutocompleter: body.type)
            case .onModalDialogOpened:
                let body = try message.decode(EditorJSMessage.ModalDialogBody.self)
                showNavigationOverlay()
                delegate?.editor(self, didOpenModalDialog: body.dialogType)
            case .onModalDialogClosed:
                let body = try message.decode(EditorJSMessage.ModalDialogBody.self)
                hideNavigationOverlay()
                delegate?.editor(self, didCloseModalDialog: body.dialogType)
            case .log:
                let logMessage = try message.decode(EditorJSMessage.LogMessage.self)
                log(logMessage.level, logMessage.message)
            case .onNetworkRequest:
                guard let requestDict = message.body as? [String: Any],
                      let networkRequest = RecordedNetworkRequest(from: requestDict) else {
                    return
                }
                delegate?.editor(self, didLogNetworkRequest: networkRequest)
            }
        } catch {
            // Capture detailed diagnostic information for crash reporting
            let messageType = message.type
            let messageBodyDescription = String(describing: message.body)

            let errorMessage = """
                Failed to decode editor message:
                - Message type: \(messageType)
                - Decode error: \(error)
                - Message body: \(messageBodyDescription)
                """

            NSLog("❌ GutenbergKit Message Decode Error: %@", errorMessage)

            assertionFailure(errorMessage)

            fatalError(errorMessage)
        }
    }

    // Only after this point it's safe to use JS `editor` API.
    private func didLoadEditor() {

        // If the editor uses `location.reload`, we'll end up here more than once
        guard case .loaded(let editorDependencies) = viewState else {
            return
        }

        self.viewState = .ready(editorDependencies)

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
    public static func warmup(configuration: EditorConfiguration) {
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
    let configuration: EditorConfiguration
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

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else {
            return .allow
        }

        if navigationAction.navigationType == .linkActivated {
            // Open the request in OS browser
            await UIApplication.shared.open(url)
            return .cancel
        }

        return .allow
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

//MARK: - View Transformation
extension EditorViewController {

    @MainActor
    func displayError(_ error: Error) {
        self.displayAndCenterView(errorViewController.view!)
        self.errorViewController.didMove(toParent: self)
        errorViewController.error = error
    }

    @MainActor
    func hideError() {
        self.errorViewController.view.removeFromSuperview()
    }

    @MainActor
    func displayProgressView() {
        self.progressView.layer.opacity = 0
        self.displayAndCenterView(self.progressView)

        UIView.animate(withDuration: 0.2, delay: 0.2) {
            self.progressView.layer.opacity = 1
        }
    }

    @MainActor
    func hideProgressView() {
        UIView.animate(withDuration: 0.2) {
            self.progressView.layer.opacity = 0
        } completion: { _ in
            self.progressView.removeFromSuperview()
        }
    }

    @MainActor
    func displayActivityView() {
        self.waitingView.layer.opacity = 0
        self.displayAndCenterView(self.waitingView)
        self.waitingView.startAnimating()

        UIView.animate(withDuration: 0.2) {
            self.waitingView.layer.opacity = 1
        }
    }

    @MainActor
    func hideActivityView() {
        UIView.animate(withDuration: 0.2) {
            self.waitingView.layer.opacity = 0
        } completion: { _ in
            self.waitingView.stopAnimating()
            self.waitingView.removeFromSuperview()
        }
    }

    private func displayAndCenterView(_ newView: UIView) {
        newView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(newView)
        self.view.bringSubviewToFront(newView)
        NSLayoutConstraint.activate([
            newView.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            newView.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
            newView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            newView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
        ])
    }
}

#endif
