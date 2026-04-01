@preconcurrency import WebKit
import SwiftUI
import OSLog
import GutenbergKitResources

#if canImport(UIKit)
import UIKit

// MARK: - EditorViewController Loading Process
//
// The EditorViewController manages the Gutenberg block editor on iOS.
// It supports two distinct loading flows based on whether dependencies are pre-fetched or not.
//
// ## Loading Flow
//
// ```
// ┌───────────────────────────────────────────────────────────────────────────────┐
// │                              INITIALIZATION                                   │
// └───────────────────────────────────────────────────────────────────────────────┘
//                                      ▼
// ┌───────────────────────────────────────────────────────────────────────────────┐
// │                               viewDidLoad()                                   │
// │  • Branch based on initialization parameters                                  │
// └───────────────────────────────────────────────────────────────────────────────┘
//              ┌───────────────────────┼───────────────────────┐
//              ▼                       ▼                       ▼
// ┌────────────────────┐  ┌────────────────────┐  ┌───────────────────────────────┐
// │   WARMUP MODE      │  │ DEPENDENCIES       │  │ NO DEPENDENCIES               │
// │   (isWarmupMode)   │  │ PROVIDED           │  │ (Async Flow)                  │
// │                    │  │ (Fast Path)        │  │                               │
// │ Load HTML without  │  │                    │  │ Spawn Task to fetch           │
// │ any dependencies   │  │ loadEditor()       │  │ dependencies                  │
// │ for prewarming     │  │ immediately        │  │                               │
// └────────────────────┘  └────────────────────┘  └───────────────────────────────┘
//                                      │                       ▼
//                                      │          ┌───────────────────────────────┐
//                                      │          │ prepareEditor()               │
//                                      │          │  • Load editor dependencies   │
//                                      │          └───────────────────────────────┘
//                                      │                       ▼
//                                      │          ┌───────────────────────────────┐
//                                      └─────────►│ loadEditor()                  │
//                                                 │  • Load editor JS into webview│
//                                                 └───────────────────────────────┘
//                                                             ▼
//                                                 ┌───────────────────────────────┐
//                                                 │   WebView Navigation          │
//                                                 │  • JS Compiled                │
//                                                 │  • Gutenberg initialized      │
//                                                 │  • `onEditorLoaded` sent      │
//                                                 └───────────────────────────────┘
//                                                             ▼
//                                                 ┌───────────────────────────────┐
//                                                 │ didLoadEditor()               │
//                                                 │  • isReady = true             │
//                                                 │  • JS methods now safe to use │
//                                                 └───────────────────────────────┘
// ```
//
// ## Flow 1: Dependencies Provided (Fast Path)
//
// When `EditorDependencies` are passed to `init()`, the editor skips the async
// dependency fetching phase entirely. This is useful when:
// - Dependencies were pre-fetched by the host app
// - The app wants to control caching/fetching separately
//
// ## Flow 2: No Dependencies (Async Flow)
//
// When no dependencies are provided, the controller fetches them asynchronously.
// This is a fallback behaviour – the host app should provide the dependencies if it can,
// because it'll be a much better user experience.
//
@MainActor
public final class EditorViewController: UIViewController, GutenbergEditorControllerDelegate, UIAdaptivePresentationControllerDelegate, UIPopoverPresentationControllerDelegate, UISheetPresentationControllerDelegate {

    public let webView: WKWebView
    public var configuration: EditorConfiguration

    /// The current editor state (empty, has undo/redo history).
    public private(set) var state = EditorState()

    /// Delegate for receiving editor lifecycle and content change callbacks.
    public weak var delegate: EditorViewControllerDelegate?

    /// The fetched or provided editor dependencies (settings, assets, preload data).
    private var dependencies: EditorDependencies?
    private var dependencyTaskHandle: Task<Void, Never>?

    /// Error encountered while loading dependencies.
    private var error: Error? {
        didSet {
            if let error {
                self.displayError(error)
            }
        }
    }

    /// Indicates whether the editor JavaScript has initialized and is ready for use.
    /// Set to `true` when the `onEditorLoaded` message is received from JavaScript.
    /// - Important: JS `editor` APIs are only safe to call after this becomes `true`.
    private var isReady: Bool = false

    /// When `true`, loads editor HTML without dependencies for WebKit prewarming.
    /// Used by `EditorViewController.warmup()` to reduce first-render latency.
    private let isWarmupMode: Bool

    // MARK: - Private Properties (Services)
    private let editorService: EditorService
    private let mediaPicker: MediaPickerController?
    private let controller: GutenbergEditorController
    private let bundleProvider: EditorAssetBundleProvider

    // MARK: - Private Properties (UI)

    /// Progress bar shown during async dependency fetching ("No Dependencies" flow).
    private let progressView = UIEditorProgressView(loadingText: EditorLocalization.localize(.loadingEditor))

    /// Spinning indicator shown while WebKit loads and parses the editor JavaScript.
    private let waitingView = UIActivityIndicatorView(style: .medium)

    /// View controller that displays error information when loading fails.
    private var errorViewController: UIHostingController<AnyView>?

    /// Stores the contextId from the most recent `openMediaLibrary` JS call.
    /// Passed back to JavaScript when media selection completes.
    private var currentMediaContextId: String?

    // MARK: - Private Properties (Timing)

    /// Timestamp captured at initialization for measuring first-render performance.
    private let timestampInit = CFAbsoluteTimeGetCurrent()

    /// Semi-transparent overlay shown over the navigation bar when JS modal dialogs are open.
    /// Prevents user interaction with navigation items while a modal is displayed.
    private lazy var navigationOverlayView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        view.isUserInteractionEnabled = true
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Renders HTML previews for block patterns in the block inserter.
    private lazy var htmlPreviewManager: HTMLPreviewManager = {
        guard let dependencies else {
            preconditionFailure("Editor does not have dependencies, cannot create HTMLPreviewManager")
        }

        return HTMLPreviewManager(themeStyles: dependencies.editorSettings.themeStyles)
    }()

    public init(
        configuration: EditorConfiguration,
        dependencies: EditorDependencies? = nil,
        mediaPicker: MediaPickerController? = nil,
        httpClient: EditorHTTPClient? = nil,
        isWarmupMode: Bool = false
    ) {
        let httpClient = httpClient ?? EditorHTTPClient(
            urlSession: URLSession.shared,
            authHeader: configuration.authHeader
        )

        self.configuration = configuration
        self.dependencies = dependencies
        self.editorService = EditorService(
            configuration: configuration,
            httpClient: httpClient
        )
        self.bundleProvider = EditorAssetBundleProvider(httpClient: httpClient)
        self.mediaPicker = mediaPicker
        self.controller = GutenbergEditorController(configuration: configuration)

        // The `allowFileAccessFromFileURLs` allows the web view to access the
        // files from the local filesystem.
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        // Set-up communications with the editor.
        config.userContentController.add(controller, name: "editorDelegate")

        // Register async message handler for content recovery requests.
        // This allows JavaScript to request the latest persisted content from the native host.
        config.userContentController.addScriptMessageHandler(controller, contentWorld: .page, name: "requestLatestContent")

        self.bundleProvider.bind(to: config)

        // Register media file scheme handler for serving local media via gbk-media-file:// URLs
        config.setURLSchemeHandler(MediaFileSchemeHandler(), forURLScheme: MediaFileSchemeHandler.scheme)

        config.applicationNameForUserAgent = "GutenbergKit/\(GutenbergKitVersion.version)"

        self.webView = GBWebView(frame: .zero, configuration: config)
        self.webView.scrollView.keyboardDismissMode = .interactive

        self.isWarmupMode = isWarmupMode

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View Lifecycle (Loading Entry Point)
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

        // WebView starts hidden; fades in when editor is ready (see didLoadEditor())
        webView.alpha = 0

        // Warmup mode - load HTML without dependencies for WebKit prewarming
        if isWarmupMode {
            self.loadEditorWithoutDependencies()
        }

        if let dependencies {
            // FAST PATH: Dependencies were provided at init() - load immediately
            do {
                try self.loadEditor(dependencies: dependencies)
            } catch {
                self.error = error
            }
        } else {
            // ASYNC FLOW: No dependencies - fetch them asynchronously
            self.dependencyTaskHandle = Task(priority: .userInitiated) { [weak self] in
                await self?.prepareEditor()
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

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.dependencyTaskHandle?.cancel()
    }

    /// Fetches all required dependencies and then loads the editor.
    ///
    /// This method is the entry point for the **Async Flow** (when no dependencies were provided at init).
    @MainActor
    private func prepareEditor() async {
        self.displayProgressView()
        defer { self.hideProgressView() }

        do {
            // EditorService.prepare() fetches dependencies concurrently with progress reporting
            let dependencies = try await self.editorService.prepare { @MainActor [weak self] progress in
                self?.progressView.setProgress(progress, animated: true)
            }

            // Store dependencies for later use (e.g., HTMLPreviewManager)
            self.dependencies = dependencies

            // Continue to the shared loading path
            try self.loadEditor(dependencies: dependencies)
        } catch {
            // Display error view - this sets self.error which triggers displayError()
            self.error = error
        }
    }

    // MARK: - Shared Loading Path: Load Editor into WebView

    /// Loads the editor HTML into the WebView with the given dependencies.
    ///
    /// This is the **shared loading path** used by both flows after dependencies are available.
    ///
    /// After this method completes, WebKit will parse the HTML and execute JavaScript.
    /// The editor will eventually emit an `onEditorLoaded` message, triggering `didLoadEditor()`.
    ///
    @MainActor
    private func loadEditor(dependencies: EditorDependencies) throws {
        self.displayActivityView()

        // Set asset bundle for the URL scheme handler to serve cached plugin/theme assets
        self.bundleProvider.set(bundle: dependencies.assetBundle)

        // Build and inject editor configuration as window.GBKit
        let editorConfig = try buildEditorConfiguration(dependencies: dependencies)
        webView.configuration.userContentController.addUserScript(editorConfig)

        // Load editor HTML - supports dev server via environment variable
        if let editorURL = ProcessInfo.processInfo.environment["GUTENBERG_EDITOR_URL"].flatMap(URL.init) {
            webView.load(URLRequest(url: editorURL))
        } else {
            let indexURL = GutenbergKitResources.editorIndexURL
            webView.loadFileURL(indexURL, allowingReadAccessTo: GutenbergKitResources.resourcesDirectoryURL)
        }
    }

    /// Loads the editor HTML without any dependencies (warmup mode only).
    ///
    /// This method is used exclusively by the warmup mechanism to preload editor resources
    /// into WebKit's memory cache. The editor won't be functional without dependencies,
    /// but subsequent loads will be faster because WebKit has already parsed the HTML/JS.
    ///
    /// - Note: Only called when `isWarmupMode` is true.
    private func loadEditorWithoutDependencies() {
        let indexURL = GutenbergKitResources.editorIndexURL
        webView.loadFileURL(indexURL, allowingReadAccessTo: GutenbergKitResources.resourcesDirectoryURL)
    }

    /// Builds a `WKUserScript` that injects the editor configuration into the page.
    ///
    /// The configuration is injected as `window.GBKit` at document start, before any other
    /// scripts run. This ensures the editor JavaScript has access to all configuration data
    /// when it initializes.
    ///
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
        guard self.isReady else {
            return
        }

        let escapedString = content.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        evaluate("editor.setContent('\(escapedString)');", isCritical: true)
    }

    /// Returns the current editor content.
    public func getContent() async throws -> String {
        guard isReady else { throw EditorNotReadyError() }
        return try await webView.evaluateJavaScript("editor.getContent();") as! String
    }

    public struct EditorTitleAndContent: Decodable {
        public let title: String
        public let content: String
        public let changed: Bool
    }

    /// Returns the current editor title and content.
    public func getTitleAndContent() async throws -> EditorTitleAndContent {
        guard isReady else { throw EditorNotReadyError() }
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
        guard isReady else { return }
        evaluate("editor.undo();")
    }

    /// Steps forwards in the editor history state
    public func redo() {
        guard isReady else { return }
        evaluate("editor.redo();")
    }

    /// Dismisses the topmost modal dialog or menu in the editor
    public func dismissTopModal() {
        guard isReady else { return }
        evaluate("editor.dismissTopModal();")
    }

    /// Enables code editor.
    public var isCodeEditorEnabled: Bool = false {
        didSet {
            guard isCodeEditorEnabled != oldValue, isReady else { return }
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
        guard isReady else { return }
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

    fileprivate func controllerDidRequestLatestContent(_ controller: GutenbergEditorController) -> (title: String, content: String)? {
        return delegate?.editorDidRequestLatestContent(self)
    }

    fileprivate func controllerWebContentProcessDidTerminate(_ controller: GutenbergEditorController) {
        // Reset readiness so JS bridge calls are blocked until the editor
        // re-emits onEditorLoaded after the reload completes.
        self.isReady = false
        webView.reload()
    }

    // MARK: - Loading Complete: Editor Ready

    /// Called when the editor JavaScript emits the `onEditorLoaded` message.
    ///
    /// This method marks the **final step of the loading process** for both flows.
    /// At this point:
    /// - All dependencies have been fetched (or were provided)
    /// - The HTML has been loaded and parsed
    /// - The JavaScript has executed and the editor has mounted
    ///
    /// **Important**: Only after this method completes is it safe to call JS `editor` APIs
    ///
    private func didLoadEditor() {
        // Guard against multiple onEditorLoaded events (e.g., from location.reload())
        guard !self.isReady else {
            return
        }

        self.hideActivityView()
        self.isReady = true

        // Fade in the WebView - it was hidden (alpha = 0) since viewDidLoad()
        UIView.animate(withDuration: 0.2, delay: 0.1, options: [.allowUserInteraction]) {
            self.webView.alpha = 1
        }

        // Log performance timing for monitoring
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

/// Error thrown when a JS bridge method is called before the editor is ready.
public struct EditorNotReadyError: LocalizedError {
    public var errorDescription: String? {
        "The editor is not ready. Wait for editorDidLoad before calling JS bridge methods."
    }
}

@MainActor
private protocol GutenbergEditorControllerDelegate: AnyObject {
    func controller(_ controller: GutenbergEditorController, didReceiveMessage message: EditorJSMessage)
    func controllerDidRequestLatestContent(_ controller: GutenbergEditorController) -> (title: String, content: String)?
    func controllerWebContentProcessDidTerminate(_ controller: GutenbergEditorController)
}

/// Hiding the conformances, and breaking retain cycles.
private final class GutenbergEditorController: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
    weak var delegate: GutenbergEditorControllerDelegate?
    let configuration: EditorConfiguration
    private let navigationPolicy: EditorNavigationPolicy

    init(configuration: EditorConfiguration) {
        self.configuration = configuration
        let devServerURL = ProcessInfo.processInfo.environment["GUTENBERG_EDITOR_URL"].flatMap(URL.init)
        self.navigationPolicy = EditorNavigationPolicy(devServerURL: devServerURL)
        super.init()
    }

    // MARK: - WKScriptMessageHandlerWithReply

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard message.name == "requestLatestContent" else {
            return (nil, "Unknown message handler: \(message.name)")
        }

        let content = await MainActor.run {
            delegate?.controllerDidRequestLatestContent(self)
        }

        guard let content else {
            return (nil, nil)  // No content available - not an error
        }

        return ([
            "title": content.title,
            "content": content.content
        ] as [String: String], nil)
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
        if navigationPolicy.shouldAllowNavigation(for: navigationAction) {
            return .allow
        }

        // External main frame navigation should open in the system browser.
        if let url = navigationAction.request.url {
            Logger.navigation.debug("Opening external URL in system browser: \(url.absoluteString)")
            await UIApplication.shared.open(url)
        }
        return .cancel
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        NSLog("webViewWebContentProcessDidTerminate: reloading editor")
        MainActor.assumeIsolated {
            delegate?.controllerWebContentProcessDidTerminate(self)
        }
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
        let view = ContentUnavailableView(
            EditorLocalization.localize(.editorError),
            systemImage: "exclamationmark.circle",
            description: Text(error.localizedDescription)
        )

        self.errorViewController = UIHostingController(rootView: AnyView(view))
        self.displayAndCenterView(errorViewController!.view)
        self.errorViewController?.didMove(toParent: self)
    }

    @MainActor
    func hideError() {
        self.errorViewController?.view.removeFromSuperview()
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
