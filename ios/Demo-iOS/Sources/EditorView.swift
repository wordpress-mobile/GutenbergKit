import SwiftUI
import GutenbergKit
import WebKit

struct EditorView: View {
    private let configuration: EditorConfiguration
    @State private var showingMoreMenu = false
    @State private var moreMenuAnchor: CGRect = .zero
    @Environment(\.dismiss) private var dismiss

    init(configuration: EditorConfiguration) {
        self.configuration = configuration
    }

    var body: some View {
        _EditorView(
            configuration: configuration,
            onNavigationAction: handleNavigationAction,
            moreMenuAnchor: $moreMenuAnchor
        )
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .popover(isPresented: $showingMoreMenu, attachmentAnchor: .rect(.rect(moreMenuAnchor)), arrowEdge: .top) {
            moreMenuContent
                .presentationCompactAdaptation(.popover)
        }
    }
    
    private func handleNavigationAction(_ action: NavigationAction) {
        switch action {
        case .close:
            dismiss()
        case .back:
            // Handle back action
            print("Back tapped")
        case .forward:
            // Handle forward action
            print("Forward tapped")
        case .openInSafari:
            // Handle open in Safari
            print("Open in Safari tapped")
        case .showMore(let rect):
            moreMenuAnchor = rect
            showingMoreMenu = true
        }
    }

    private var moreMenuContent: some View {
        List {
            Section {
                Button(action: {
                    showingMoreMenu = false
                    // Handle code editor
                }) {
                    Label("Code Editor", systemImage: "curlybraces")
                }
                Button(action: {
                    showingMoreMenu = false
                    // Handle outline
                }) {
                    Label("Outline", systemImage: "list.bullet.indent")
                }
                Button(action: {
                    showingMoreMenu = false
                    // Handle preview
                }) {
                    Label("Preview", systemImage: "safari")
                }
            }
            Section {
                Button(action: {
                    showingMoreMenu = false
                    // Handle revisions
                }) {
                    Label("Revisions (42)", systemImage: "clock.arrow.circlepath")
                }
                Button(action: {
                    showingMoreMenu = false
                    // Handle post settings
                }) {
                    Label("Post Settings", systemImage: "gearshape")
                }
                Button(action: {
                    showingMoreMenu = false
                    // Handle help
                }) {
                    Label("Help", systemImage: "questionmark.circle")
                }
            }
            Section {
                Text("Blocks: 4, Words: 8, Characters: 15")
            }
        }
        .listStyle(.plain)
        .frame(width: 260, height: 324)
    }
}

enum NavigationAction {
    case close
    case back
    case forward
    case openInSafari
    case showMore(CGRect)
}

private struct _EditorView: UIViewControllerRepresentable {
    private let configuration: EditorConfiguration
    let onNavigationAction: (NavigationAction) -> Void
    @Binding var moreMenuAnchor: CGRect

    init(configuration: EditorConfiguration, 
         onNavigationAction: @escaping (NavigationAction) -> Void,
         moreMenuAnchor: Binding<CGRect>) {
        self.configuration = configuration
        self.onNavigationAction = onNavigationAction
        self._moreMenuAnchor = moreMenuAnchor
    }

    func makeUIViewController(context: Context) -> EditorViewControllerWrapper {
        let wrapper = EditorViewControllerWrapper(configuration: configuration)
        wrapper.navigationHandler = context.coordinator
        
        if #available(iOS 16.4, *) {
            wrapper.editorViewController.webView.isInspectable = true
        }
        wrapper.editorViewController.startEditorSetup()
        return wrapper
    }

    func updateUIViewController(_ uiViewController: EditorViewControllerWrapper, context: Context) {
        // Do nothing
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigationAction: onNavigationAction,
                   moreMenuAnchor: $moreMenuAnchor)
    }
    
    class Coordinator: NSObject {
        let onNavigationAction: (NavigationAction) -> Void
        @Binding var moreMenuAnchor: CGRect
        
        init(onNavigationAction: @escaping (NavigationAction) -> Void,
             moreMenuAnchor: Binding<CGRect>) {
            self.onNavigationAction = onNavigationAction
            self._moreMenuAnchor = moreMenuAnchor
        }
    }
}

// Wrapper to add navigation functionality
class EditorViewControllerWrapper: UIViewController {
    let editorViewController: EditorViewController
    fileprivate weak var navigationHandler: _EditorView.Coordinator?
    
    init(configuration: EditorConfiguration) {
        self.editorViewController = EditorViewController(configuration: configuration)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Add editor as child view controller
        addChild(editorViewController)
        view.addSubview(editorViewController.view)
        editorViewController.view.frame = view.bounds
        editorViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        editorViewController.didMove(toParent: self)
        
        // Inject navigation bar HTML/CSS/JS
        injectNavigationBar()
        
        // Add message handler for navigation actions
        editorViewController.webView.configuration.userContentController.add(self, name: "navigationHandler")
    }
    
    private func injectNavigationBar() {
        let navigationBarScript = """
        (function() {
            // Wait for editor to be ready
            const injectNavBar = () => {
                // Check if navigation already exists
                if (document.getElementById('gbkit-navigation-bar')) return;
                
                // Create navigation bar HTML
                const navHTML = `
                    <div id="gbkit-navigation-bar">
                        <div class="gbkit-nav-group gbkit-nav-leading">
                            <button class="gbkit-nav-button" data-action="close">
                                <svg viewBox="0 0 24 24" fill="none">
                                    <path d="M18 6L6 18M6 6L18 18" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
                                </svg>
                            </button>
                        </div>
                        <div class="gbkit-nav-group gbkit-nav-trailing">
                            <button class="gbkit-nav-button" data-action="back">
                                <svg viewBox="0 0 24 24" fill="none">
                                    <path d="M7 12L3 8M3 8L7 4M3 8H13C17.4183 8 21 11.5817 21 16C21 20.4183 17.4183 24 13 24H11" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
                                </svg>
                            </button>
                            <button class="gbkit-nav-button" data-action="forward" disabled>
                                <svg viewBox="0 0 24 24" fill="none">
                                    <path d="M17 12L21 8M21 8L17 4M21 8H11C6.58172 8 3 11.5817 3 16C3 20.4183 6.58172 24 11 24H13" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
                                </svg>
                            </button>
                            <button class="gbkit-nav-button" data-action="preview">
                                <svg viewBox="0 0 24 24" fill="none">
                                    <rect x="4" y="4" width="16" height="16" rx="2" stroke="currentColor" stroke-width="2"/>
                                    <path d="M9 9H15M9 12H15M9 15H13" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
                                </svg>
                            </button>
                            <button class="gbkit-nav-button" data-action="more">
                                <svg viewBox="0 0 24 24" fill="none">
                                    <circle cx="12" cy="5" r="2" fill="currentColor"/>
                                    <circle cx="12" cy="12" r="2" fill="currentColor"/>
                                    <circle cx="12" cy="19" r="2" fill="currentColor"/>
                                </svg>
                            </button>
                        </div>
                    </div>
                `;
                
                // Create navigation container
                const navContainer = document.createElement('div');
                navContainer.innerHTML = navHTML;
                document.body.insertBefore(navContainer.firstElementChild, document.body.firstChild);
                
                // Add CSS
                const style = document.createElement('style');
                style.textContent = `
                    #gbkit-navigation-bar {
                        position: fixed;
                        top: 0;
                        left: 0;
                        right: 0;
                        height: 60px;
                        background: rgba(255, 255, 255, 0.9);
                        backdrop-filter: blur(10px);
                        -webkit-backdrop-filter: blur(10px);
                        display: flex;
                        justify-content: space-between;
                        align-items: center;
                        padding: 0 8px;
                        z-index: 9999;
                        border-bottom: 1px solid rgba(0, 0, 0, 0.1);
                        overflow: visible;
                    }
                    
                    /* Extend background above the navigation bar */
                    #gbkit-navigation-bar::before {
                        content: '';
                        position: absolute;
                        top: -200px;
                        left: -20px;
                        right: -20px;
                        height: 200px;
                        background: rgba(255, 255, 255, 0.9);
                        backdrop-filter: blur(10px);
                        -webkit-backdrop-filter: blur(10px);
                        z-index: -1;
                    }
                    
                    /* Dark mode support for extended background */
                    @media (prefers-color-scheme: dark) {
                        #gbkit-navigation-bar::before {
                            background: rgba(29, 29, 31, 0.94);
                        }
                    }
                    
                    .gbkit-nav-group {
                        display: flex;
                        gap: 12px;
                        align-items: center;
                    }
                    
                    .gbkit-nav-button {
                        background: none;
                        border: none;
                        padding: 8px;
                        min-width: 36px;
                        min-height: 36px;
                        cursor: pointer;
                        color: #000000;
                        display: flex;
                        align-items: center;
                        justify-content: center;
                        border-radius: 6px;
                        -webkit-tap-highlight-color: transparent;
                        -webkit-touch-callout: none;
                        -webkit-user-select: none;
                        user-select: none;
                        outline: none;
                    }
                    
                    .gbkit-nav-button svg {
                        width: 20px;
                        height: 20px;
                    }
                    
                    .gbkit-nav-button:active {
                        transform: scale(0.95);
                    }
                    
                    .gbkit-nav-button:disabled {
                        color: #C7C7CC;
                        cursor: not-allowed;
                    }
                    
                    .gbkit-nav-button:disabled:active {
                        transform: none;
                    }
                    
                    /* Adjust editor content to account for navigation bar */
                    .interface-interface-skeleton,
                    .edit-post-layout,
                    body {
                        padding-top: 60px !important;
                    }
                    
                    /* Ensure modals cover the navigation bar */
                    .components-modal__screen-overlay,
                    [role="dialog"][aria-modal="true"] {
                        top: 0 !important;
                        z-index: 10000 !important;
                    }
                    
                    /* Modal animations */
                    @keyframes modalFadeIn {
                        from {
                            opacity: 0;
                        }
                        to {
                            opacity: 1;
                        }
                    }
                    
                    @keyframes modalSlideIn {
                        from {
                            transform: translateY(20px) scale(0.95);
                            opacity: 0;
                        }
                        to {
                            transform: translateY(0) scale(1);
                            opacity: 1;
                        }
                    }
                    
                    @keyframes modalBackdropFadeIn {
                        from {
                            backdrop-filter: blur(0px);
                            -webkit-backdrop-filter: blur(0px);
                            background-color: rgba(0, 0, 0, 0);
                        }
                        to {
                            backdrop-filter: blur(8px);
                            -webkit-backdrop-filter: blur(8px);
                            background-color: rgba(0, 0, 0, 0.4);
                        }
                    }
                    
                    /* Apply animations to modal overlay */
                    .components-modal__screen-overlay {
                        animation: modalBackdropFadeIn 0.3s cubic-bezier(0.25, 0.1, 0.25, 1) forwards;
                        backdrop-filter: blur(8px);
                        -webkit-backdrop-filter: blur(8px);
                        background-color: rgba(0, 0, 0, 0.4) !important;
                    }
                    
                    /* Apply animations to modal content */
                    .components-modal__frame {
                        animation: modalSlideIn 0.3s cubic-bezier(0.25, 0.1, 0.25, 1) forwards;
                        box-shadow: 0 20px 60px rgba(0, 0, 0, 0.15), 0 0 1px rgba(0, 0, 0, 0.1) !important;
                        border-radius: 12px !important;
                        overflow: hidden;
                    }
                    
                    /* Block inserter specific styling */
                    .block-editor-inserter__menu,
                    .block-editor-inserter__popover {
                        animation: modalSlideIn 0.25s cubic-bezier(0.25, 0.1, 0.25, 1) forwards;
                    }
                    
                    /* Popover animations */
                    .components-popover {
                        animation: modalFadeIn 0.2s ease-out forwards;
                    }
                    
                    .components-popover__content {
                        animation: modalSlideIn 0.2s cubic-bezier(0.25, 0.1, 0.25, 1) forwards;
                        box-shadow: 0 8px 24px rgba(0, 0, 0, 0.12), 0 0 1px rgba(0, 0, 0, 0.1) !important;
                        border-radius: 8px !important;
                    }
                    
                    /* Block settings sidebar animation */
                    .interface-complementary-area {
                        transition: transform 0.3s cubic-bezier(0.25, 0.1, 0.25, 1), opacity 0.3s ease;
                    }
                    
                    .interface-complementary-area.is-hidden {
                        transform: translateX(100%);
                        opacity: 0;
                    }
                    
                    /* Settings panel animations */
                    .block-editor-block-inspector {
                        animation: modalSlideIn 0.25s cubic-bezier(0.25, 0.1, 0.25, 1) forwards;
                    }
                    
                    /* Dropdown animations */
                    .components-dropdown__content {
                        animation: modalFadeIn 0.15s ease-out forwards;
                    }
                    
                    .components-dropdown-menu__menu {
                        animation: modalSlideIn 0.2s cubic-bezier(0.25, 0.1, 0.25, 1) forwards;
                        border-radius: 8px !important;
                        box-shadow: 0 4px 16px rgba(0, 0, 0, 0.1) !important;
                    }
                    
                    /* Color picker animations */
                    .components-color-picker__popover .components-popover__content {
                        animation: modalSlideIn 0.2s cubic-bezier(0.25, 0.1, 0.25, 1) forwards;
                    }
                    
                    /* Smooth transitions for interactive elements */
                    .components-button {
                        transition: transform 0.1s ease, box-shadow 0.1s ease;
                    }
                    
                    .components-button:active {
                        transform: scale(0.98);
                    }
                    
                    /* Add spring animation for block selection */
                    .block-editor-block-list__block.is-selected {
                        animation: blockSelect 0.3s cubic-bezier(0.68, -0.55, 0.265, 1.55);
                    }
                    
                    @keyframes blockSelect {
                        0% {
                            transform: scale(1);
                        }
                        50% {
                            transform: scale(1.02);
                        }
                        100% {
                            transform: scale(1);
                        }
                    }
                    
                `;
                document.head.appendChild(style);
                
                // Add event listeners
                document.querySelectorAll('.gbkit-nav-button').forEach(button => {
                    button.addEventListener('click', (e) => {
                        const action = button.getAttribute('data-action');
                        
                        if (action === 'more') {
                            // Get button position relative to viewport
                            const rect = button.getBoundingClientRect();
                            window.webkit.messageHandlers.navigationHandler.postMessage({
                                action: action,
                                rect: {
                                    x: rect.x,
                                    y: rect.y,
                                    width: rect.width,
                                    height: rect.height
                                }
                            });
                        } else {
                            window.webkit.messageHandlers.navigationHandler.postMessage({
                                action: action
                            });
                        }
                    });
                });
                
                // Monitor for undo/redo state changes
                if (window.wp && window.wp.data) {
                    const checkUndoRedo = () => {
                        const editor = window.wp.data.select('core/editor');
                        if (editor) {
                            const canUndo = editor.hasEditorUndo();
                            const canRedo = editor.hasEditorRedo();
                            
                            const backButton = document.querySelector('[data-action="back"]');
                            const forwardButton = document.querySelector('[data-action="forward"]');
                            
                            if (backButton) backButton.disabled = !canUndo;
                            if (forwardButton) forwardButton.disabled = !canRedo;
                        }
                    };
                    
                    // Subscribe to state changes
                    const unsubscribe = window.wp.data.subscribe(checkUndoRedo);
                    
                    // Initial check
                    setTimeout(checkUndoRedo, 1000);
                }
            };
            
            // Try to inject immediately and after delays
            injectNavBar();
            setTimeout(injectNavBar, 1000);
            setTimeout(injectNavBar, 2000);
            
            // Also inject when DOM is ready
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', injectNavBar);
            }
        })();
        """
        
        let userScript = WKUserScript(source: navigationBarScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        editorViewController.webView.configuration.userContentController.addUserScript(userScript)
    }
}

// Handle navigation messages
extension EditorViewControllerWrapper: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            switch action {
            case "close":
                self?.navigationHandler?.onNavigationAction(.close)
            case "back":
                // Execute undo in the editor
                self?.editorViewController.webView.evaluateJavaScript("window.wp.data.dispatch('core/editor').undo();")
                self?.navigationHandler?.onNavigationAction(.back)
            case "forward":
                // Execute redo in the editor
                self?.editorViewController.webView.evaluateJavaScript("window.wp.data.dispatch('core/editor').redo();")
                self?.navigationHandler?.onNavigationAction(.forward)
            case "preview":
                // Toggle preview mode in the editor
                self?.editorViewController.webView.evaluateJavaScript("""
                    if (window.wp && window.wp.data) {
                        const editPost = window.wp.data.dispatch('core/edit-post');
                        const isPreviewOpen = window.wp.data.select('core/edit-post').isPublishSidebarOpened();
                        if (editPost.togglePublishSidebar) {
                            editPost.togglePublishSidebar();
                        }
                    }
                """)
            case "more":
                if let rect = body["rect"] as? [String: CGFloat],
                   let x = rect["x"],
                   let y = rect["y"],
                   let width = rect["width"],
                   let height = rect["height"] {
                    let menuRect = CGRect(x: x, y: y, width: width, height: height)
                    self?.navigationHandler?.onNavigationAction(.showMore(menuRect))
                }
            default:
                break
            }
        }
    }
}

#Preview {
    NavigationStack {
        EditorView(configuration: .default)
    }
}
