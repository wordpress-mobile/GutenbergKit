import Foundation
import WebKit
import Combine

@MainActor
final class WebBridge {
    private let configuration: EditorConfiguration
    private let assetsLibrary: EditorAssetsLibrary
    private var editorDelegate: EditorDelegate

    private let messagesSubject: PassthroughSubject<EditorJSMessage, Never> = .init()
    var messages: AnyPublisher<EditorJSMessage, Never> { messagesSubject.eraseToAnyPublisher() }

    init(configuration: EditorConfiguration) {
        self.configuration = configuration
        self.assetsLibrary = EditorAssetsLibrary(configuration: configuration)
        self.editorDelegate = EditorDelegate()
        self.editorDelegate.bridge = self
    }

    fileprivate func didReceiveMessageFromWebView(_ message: EditorJSMessage) {
        messagesSubject.send(message)
    }
}

// MARK: - WKWebView support (UIKit)

extension WebBridge {
    func configure(with configuration: WKWebViewConfiguration) {
        configuration.userContentController.addUserScript(getEditorConfiguration())

        configuration.userContentController.add(editorDelegate, name: "editorDelegate")

        configuration.userContentController.addScriptMessageHandler(
            EditorAssetsProvider(library: assetsLibrary),
            contentWorld: .page,
            name: "loadFetchedEditorAssets"
        )

        let schemeHandler = CachedAssetSchemeHandler(library: assetsLibrary)
        for scheme in CachedAssetSchemeHandler.supportedURLSchemes {
            configuration.setURLSchemeHandler(schemeHandler, forURLScheme: scheme)
        }
    }
}

// MARK: - WebPage support (SwiftUI)

@available(iOS 26.0, *)
extension WebBridge {
    func configure(with configuration: inout WebPage.Configuration) {
        configuration.userContentController.addUserScript(getEditorConfiguration())

        configuration.userContentController.add(editorDelegate, name: "editorDelegate")

        configuration.userContentController.addScriptMessageHandler(
            EditorAssetsProvider(library: assetsLibrary),
            contentWorld: .page,
            name: "loadFetchedEditorAssets"
        )

        let schemeHandler = CachedAssetSchemeHandler(library: assetsLibrary)
        for scheme in CachedAssetSchemeHandler.supportedURLSchemes {
            if let urlScheme = URLScheme(scheme) {
                configuration.urlSchemeHandlers[urlScheme] = schemeHandler
            }
        }
    }
}

private extension WebBridge {
    func getEditorConfiguration() -> WKUserScript {
        let escapedTitle = configuration.title.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let escapedContent = configuration.content.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!

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
}

private class EditorDelegate: NSObject, WKScriptMessageHandler {
    weak var bridge: WebBridge?

    func attach(to controller: WKUserContentController) {
        controller.add(self, name: "editorDelegate")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let message = EditorJSMessage(message: message) else {
            return NSLog("Unsupported message: \(message.body)")
        }
        bridge?.didReceiveMessageFromWebView(message)
    }
}
