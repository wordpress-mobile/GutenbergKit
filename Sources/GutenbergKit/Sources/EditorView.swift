import UIKit
import SwiftUI
import WebKit
import Photos
import PhotosUI
import OSLog

public struct EditorView: View {
    @State private var isBlockInserterShown = false

    public init() {}

    public var body: some View {
        NavigationView {
            _EditorView()

                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button(action: {}, label: {
                            Image(systemName: "xmark")
                        })
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button(action: {}, label: {
                            Image(systemName: "arrow.uturn.backward")
                        })
                        Button(action: {}, label: {
                            Image(systemName: "arrow.uturn.forward")
                        }).disabled(true)
                    }

//                    ToolbarItemGroup(placement: .topBarTrailing) {
//                        HStack {
//                                Divider()
//                                .frame(width: 2, height: 20)
//                            }
//                    }

                    ToolbarItemGroup(placement: .topBarTrailing) {
//                        Button(action: {}, label: {
//                            Image(systemName: "curlybraces")
//                        })
//                        Button(action: {}, label: {
//                            Image(systemName: "list.bullet.indent")
//                        })
                        Button(action: {}, label: {
                            Image(systemName: "safari")
                        })

                        Menu {
                            Section {
                                Button(action: {}, label: {
                                    Label("Code Editor", systemImage: "curlybraces")
                                })
                                Button(action: {}, label: {
                                    Label("Outline", systemImage: "list.bullet.indent")
                                })
                                Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                                    Label("Preview", systemImage: "safari")
                                })
                            }
                            Section {
                                Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                                    Label("Revisions (42)", systemImage: "clock.arrow.circlepath")
                                })
                                Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                                    Label("Post Settings", systemImage: "gearshape")
                                })

                                Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                                    Label("Help", systemImage: "questionmark.circle")
                                })
                            }
                            Section {
                                Text("Blocks: 4, Words: 8, Characters: 15")
                            } header: {

                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .tint(Color.primary)
                    }


//                    ToolbarItemGroup(placement: .topBarTrailing) {
//                        HStack {
//                                Divider()
//                                .frame(width: 2, height: 20)
//                            }
//                    }

                    ToolbarItemGroup(placement: .topBarTrailing) {



//                        Button(action: {}, label: {
//                            Text("Publish")
//                        })
////                        .font(.headline)

//                            Button(action: {}, label: {
//                                Image(systemName: "paperplane.fill")
//                            })
//                            .font(.headline)


                        Button(action: {}, label: {
                            Image(systemName: "arrow.up.circle.fill")
                        })
//                        .buttonStyle(.borderedProminent)
//                        .font(.body.weight(.medium))
//                        .fixedSize()
                        //.*fix*/
                        .font(.title2)

//                        Button("Publish") {
//
//                        }
//                        .buttonStyle(.bordered)
                    }

                }

                .tint(Color.primary)

                .sheet(isPresented: $isBlockInserterShown) {
                    NavigationView {
                        BlockInserter()
                    }
//                    .presentationDetents([.height(540), .large])
//                    .presentationCornerRadius(20)
                }
        }
        .navigationViewStyle(.stack)
    }
}

struct _EditorView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> EditorViewController {
        EditorViewController()
    }

    func updateUIViewController(_ uiViewController: EditorViewController, context: Context) {
        // Do nothing
    }
}

public struct EditorState {
    /// Set to `true` if the editor has non-empty content.
    public var isEmpty = true
}

public protocol EditorViewControllerDelegate: AnyObject {
    /// Gets called when the editor is loaded and the initial content is displayed.
    ///
    /// - parameter content: Content serialized according to the editor's settings.
    func editor(_ viewContoller: EditorViewController, didDisplayInitialContent content: String)

    /// Editor encounterd a critical error and has to be stopped.
    ///
    /// - warning: Make sure not to update user content if that happens (it shouldn't)
    func editor(_ viewContoller: EditorViewController, didEncounterCriticalError error: Error)

    /// Notifies the client about the new edits.
    ///
    /// - note: To get the latest content, call ``EditorViewController/getContent()``.
    /// Retrieving the content is a relatively expensive operation and should not
    /// be performed too frequently during editing.
    func editor(_ viewController: EditorViewController, didUpdateContentWithState state: EditorState)
}

@MainActor
public final class EditorViewController: UIViewController, GutenbergEditorControllerDelegate {
    private var reactAppURL: URL!
    private var webView: WKWebView!
    private var content: String
    private var _isEditorRendered = false
    private let controller = GutenbergEditorController()
    private let timestampInit = CFAbsoluteTimeGetCurrent()

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

    /// Initalizes the editor with the initial content (Gutenberg).
    public init(content: String = "") {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        controller.delegate = self

        reactAppURL = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Gutenberg")

        // The `allowFileAccessFromFileURLs` allows the web view to access the
        // files from the local filesystem.
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        // Set-up communications with the editor.
        config.userContentController.add(controller, name: "editorDelegate")

        // set the configuration on the `WKWebView`
        // don't worry about the frame: .zero, SwiftUI will resize the `WKWebView` to
        // fit the parent
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = controller
        if #available(iOS 16.4, *) {
            webView.isInspectable = true // TODO: should be diasble in production
        }
        self.webView = webView

        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        webView.alpha = 0

        loadEditor()
    }

    private func loadEditor() {
        webView.loadFileURL(reactAppURL, allowingReadAccessTo: Bundle.module.resourceURL!)
    }

    // MARK: - Actions

    // TODO: synchronize with the editor user-generated updates
    // TODO: convert to a property?
    public func setContent(_ content: String) {
        self.content = content
        _setContent(content)
    }

    private func setInitialContent(_ content: String, _ completion: (() -> Void)? = nil) async {
        guard _isEditorRendered else { fatalError("called too early") }

        let start = CFAbsoluteTimeGetCurrent()

        // TODO: Find a faster and more reliable way to pass large strings to a web view
        let escapedString = content.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!

        // TODO: Check errors and notify the delegate when the editor is loaded and the content got displaed
        do {
            let serializedContent = try await webView.evaluateJavaScript("""
        editor.setInitialContent(decodeURIComponent('\(escapedString)'));
        """) as! String
            self.initialContent = serializedContent
            delegate?.editor(self, didDisplayInitialContent: serializedContent)
            print("gutenbergkit-set-initial-content:", CFAbsoluteTimeGetCurrent() - start)

            UIView.animate(withDuration: 0.25, delay: 0.0, options: [.allowUserInteraction]) {
                self.webView.alpha = 1
            }
        } catch {
            delegate?.editor(self, didEncounterCriticalError: error)
        }
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

    // MARK: - GutenbergEditorControllerDelegate

    fileprivate func controller(_ controller: GutenbergEditorController, didReceiveMessage message: JSEditorMessage) {
        do {
            switch message.type {
            case .onEditorLoaded:
                didLoadEditor()
            case .onBlocksChanged:
                let body = try message.decode(JSEditorDidUpdateBlocksBody.self)
                let state = EditorState(isEmpty: body.isEmpty)
                delegate?.editor(self, didUpdateContentWithState: state)
            }
        } catch {
            fatalError("failed to decode message: \(error)")
        }
    }

    private func didLoadEditor() {
        guard !_isEditorRendered else { return }
        _isEditorRendered = true

        let duration = CFAbsoluteTimeGetCurrent() - timestampInit
        print("gutenbergkit-measure_editor-first-render:", duration)

        Task {
            await setInitialContent(content)
        }
    }
}

@MainActor
private protocol GutenbergEditorControllerDelegate: AnyObject {
    func controller(_ controller: GutenbergEditorController, didReceiveMessage message: JSEditorMessage)
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
        guard let message = JSEditorMessage(message: message) else {
            return NSLog("Unsupported message: \(message.body)")
        }
        MainActor.assumeIsolated {
            delegate?.controller(self, didReceiveMessage: message)
        }
    }
}

private extension WKWebView {

}
