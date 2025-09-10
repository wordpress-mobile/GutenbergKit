import Foundation
import SwiftUI
import WebKit
import Combine

@available(iOS 26.0, *)
public struct GutenbergEditor: View {
    @StateObject private var viewModel: GutenbergEditorViewModel

    public init(configuration: EditorConfiguration = .default) {
        self._viewModel = StateObject(wrappedValue: GutenbergEditorViewModel(configuration: configuration))
    }

    public var body: some View {
        WebView(viewModel.webPage)
            .textSelection(.enabled)
            .scrollDismissesKeyboard(.interactively)
            .task {
                await viewModel.loadEditor()
            }
    }

}

@available(iOS 26.0, *)
@MainActor
private final class GutenbergEditorViewModel: ObservableObject {
    @Published private(set) var webPage: WebPage

    var configuration: EditorConfiguration
    private let webBridge: WebBridge
    private let controller: GutenbergEditorController

    init(configuration: EditorConfiguration = .default) {
        self.configuration = configuration
        self.webBridge = WebBridge(configuration: configuration)
        self.controller = GutenbergEditorController(configuration: configuration)

        var config = WebPage.Configuration()
        webBridge.configure(with: &config)

        self.webPage = WebPage(configuration: config, navigationDecider: controller)

#if DEBUG
        self.webPage.isInspectable = true
#endif
    }

    func loadEditor() async {
        if configuration.plugins {
            // Handle remote editor loading
            if let remoteURL = ProcessInfo.processInfo.environment["GUTENBERG_EDITOR_REMOTE_URL"].flatMap(URL.init) {
                webPage.load(URLRequest(url: remoteURL))
            } else {
                let remoteURL = Bundle.module.url(forResource: "remote", withExtension: "html", subdirectory: "Gutenberg")!
                webPage.load(URLRequest(url: remoteURL))
            }
        } else if let editorURL = ProcessInfo.processInfo.environment["GUTENBERG_EDITOR_URL"].flatMap(URL.init) {
            webPage.load(URLRequest(url: editorURL))
        } else {
            let indexURL = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Gutenberg")!
            webPage.load(URLRequest(url: indexURL))
        }
    }
}
