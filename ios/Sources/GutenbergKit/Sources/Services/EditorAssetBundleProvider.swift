import Foundation
import OSLog
import WebKit

/// Serves cached plugin and theme assets to the editor WebView.
///
/// `EditorAssetBundleProvider` acts as a bridge between the WKWebView and the on-disk
/// asset cache. It registers itself as both a script message handler (to provide the
/// asset manifest to JavaScript) and a URL scheme handler (to serve individual cached
/// files via the `gbk-cache-https` scheme).
///
/// ## Usage
///
/// ```swift
/// let provider = EditorAssetBundleProvider()
/// provider.bind(to: webViewConfiguration)
/// provider.set(bundle: assetBundle)
/// ```
///
/// The provider must be bound to the WebView configuration before loading the editor,
/// and must have a bundle set before the editor requests assets.
public final class EditorAssetBundleProvider: NSObject, @unchecked Sendable {

    private let lock = NSLock()
    private var bundle: EditorAssetBundle?

    /// Sets the asset bundle to serve to the WebView.
    ///
    /// This method is thread-safe and can be called from any thread.
    ///
    /// - Parameter bundle: The downloaded asset bundle containing cached scripts and styles.
    public func set(bundle: EditorAssetBundle) {
        lock.withLock {
            self.bundle = bundle
        }
    }

    /// Registers this provider with a WebView configuration.
    ///
    /// This method registers a script message handler for the editor to request the asset
    /// manifest, and a URL scheme handler to serve individual cached files.
    ///
    /// - Parameter configuration: The WebView configuration to register with.
    @MainActor
    public func bind(to configuration: WKWebViewConfiguration) {
        // Register the callback that provides the cached asset manifest
        configuration.userContentController.addScriptMessageHandler(
            self,
            contentWorld: .page,
            name: "loadFetchedEditorAssets"
        )

        // Register the handler for individual cached assets
        configuration.setURLSchemeHandler(self, forURLScheme: "gbk-cache-https")
    }
}

extension EditorAssetBundleProvider: WKScriptMessageHandlerWithReply {

    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        logExecutionTime("Retrieved Asset Manifest") {
            Logger.assetLibrary.info("📚 Editor requested asset manifest")

            guard let payload = message.body as? NSDictionary,
                  let asset = payload.object(forKey: "asset") as? String,
                  asset == "manifest"
            else {
                replyHandler(nil, "Unexpected message")
                return
            }

            guard let bundle else {
                preconditionFailure("Cannot read manifest with no bundle present. This is a programmer error.")
            }

            do {
                let reply: Any = try bundle.getEditorRepresentation()
                replyHandler(reply, nil)
            } catch {
                Logger.assetLibrary.error("📚 Failed to fetch asset manifest: \(error.localizedDescription)")
            }
        }
    }
}

extension EditorAssetBundleProvider: WKURLSchemeHandler {
    public func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        logExecutionTime("Retrieved cached asset") {
            var loggerMessages = ["📚 Editor requested a cached asset"]

            defer {
                Logger.assetLibrary.info("\(loggerMessages.joined(separator: "\n"))")
            }

            guard let url = urlSchemeTask.request.url else {
                loggerMessages.append("     URL: <missing>")
                urlSchemeTask.didFailWithError(URLError(.badURL))
                return
            }

            loggerMessages.append("     URL: \(url)")

            guard let bundle else {
                preconditionFailure("Cannot read asset with no bundle present. This is a programmer error.")
            }

            guard bundle.hasAssetData(for: url) else {
                loggerMessages.append("     Path: <missing>")

                loggerMessages.append("     Not found – sending 404")
                let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didFinish()
                return
            }

            do {
                loggerMessages.append("     Path: \(bundle.assetDataPath(for: url))")

                let data = try bundle.assetData(for: url)
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch {
                loggerMessages.append("     Error: \(error.localizedDescription)")
                urlSchemeTask.didFailWithError(error)
            }

        }
    }

    public func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        // No-op: since we're reading from disk synchronously, there's nothing to cancel
    }
}
