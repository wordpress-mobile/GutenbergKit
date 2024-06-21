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
    func makeUIViewController(context: Context) -> GutenbergEditorViewController {
        GutenbergEditorViewController()
    }

    func updateUIViewController(_ uiViewController: GutenbergEditorViewController, context: Context) {
        // Do nothing
    }
}

public final class GutenbergEditorViewController: UIViewController, GutenbergEditorControllerDelegate {
    private var reactAppURL: URL!
    private var webView: WKWebView!
    private var content: String
    private var isEditorLoaded = false
    private let controller = GutenbergEditorController()
    private var getContentContinuations: [String: UnsafeContinuation<String, Never>] = [:]

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
            webView.isInspectable = true
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

    private func _setContent(_ content: String) {
        guard isEditorLoaded else { return }

        guard let data = content.data(using: .utf8)?.base64EncodedString() else {
            return // Should never happen
        }
        webView.evaluateJavaScript("""
        window.postMessage({ event: "setContent", content: atob('\(data)') });
        """)
    }

    /// Returns the current editor content.
    public func getContent() async -> String {
        await withUnsafeContinuation { continuation in
            let requestID = UUID().uuidString
            getContentContinuations[requestID] = continuation
            webView.evaluateJavaScript("""
            window.postMessage({ event: "getContent", requestID: "\(requestID)" });
            """)
        }
    }

    // MARK: - GutenbergEditorControllerDelegate

    fileprivate func controller(_ controller: GutenbergEditorController, didReceiveMessage message: JSEditorMessage) {
        do {
            switch message.type {
            case .onEditorLoaded:
                didLoadEditor()
            case .onContentProvided:
                let body = try message.decode(JSEditorMessageContentProvidedBody.self)
                if let continuation = getContentContinuations.removeValue(forKey: body.requestID) {
                     if let data = Data(base64Encoded: body.content),
                        let string = String(data: data, encoding: .utf8) {
                         continuation.resume(returning: string)
                     } else {
                         fatalError("invalid encoding")
                     }
                }
            }
        } catch {
            fatalError("failed to decode message: \(error)")
        }
    }

    private func didLoadEditor() {
        guard !isEditorLoaded else { return }
        isEditorLoaded = true

        _setContent(content)
    }
}

private protocol GutenbergEditorControllerDelegate: AnyObject {
    func controller(_ controller: GutenbergEditorController, didReceiveMessage message: JSEditorMessage)
}

/// Hiding the conformances, and breaking retain cycles.
private final class GutenbergEditorController: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    weak var delegate: GutenbergEditorControllerDelegate?

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        NSLog("navigation: \(navigation)")
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
        delegate?.controller(self, didReceiveMessage: message)
    }
}
