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
/// When an asset is not found in the local cache (e.g., images referenced in CSS that
/// weren't downloaded), the provider fetches the asset from its original HTTPS URL
/// and serves it to the WebView.
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
    private let urlSession: URLSession

    override public init() {
        self.urlSession = URLSession(configuration: .default)
        super.init()
    }

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

            // Check if the path is valid and the asset exists in the bundle.
            // If not, fetch from the original HTTPS URL (e.g., for plugin SVGs
            // referenced in CSS that weren't downloaded into the bundle).
            let shouldFetchFromRemote = !bundle.isValidAssetPath(for: url) || !bundle.hasAssetData(for: url)

            guard !shouldFetchFromRemote else {
                loggerMessages.append("     Asset not in bundle – fetching from remote")
                self.fetchFromRemote(url: url, urlSchemeTask: urlSchemeTask, loggerMessages: &loggerMessages)
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

    /// Fetches an asset from its original remote URL and serves it to the WebView.
    ///
    /// This is used when an asset isn't in the local bundle (e.g., images referenced
    /// in CSS files that weren't downloaded because only JS/CSS files are cached).
    private func fetchFromRemote(
        url: URL,
        urlSchemeTask: any WKURLSchemeTask,
        loggerMessages: inout [String]
    ) {
        guard let originalURL = self.originalURL(for: url) else {
            loggerMessages.append("     Failed to construct original URL")
            let response = HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: nil)!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didFinish()
            return
        }

        loggerMessages.append("     Fetching from: \(originalURL)")

        let task = urlSession.dataTask(with: originalURL) { data, response, error in
            if let error {
                Logger.assetLibrary.error("📚 Failed to fetch remote asset: \(error.localizedDescription)")
                urlSchemeTask.didFailWithError(error)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, let data else {
                urlSchemeTask.didFailWithError(URLError(.badServerResponse))
                return
            }

            // Create a new response with the original URL scheme task's URL
            let schemeResponse = HTTPURLResponse(
                url: url,
                statusCode: httpResponse.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: httpResponse.allHeaderFields as? [String: String]
            )!

            urlSchemeTask.didReceive(schemeResponse)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        }
        task.resume()
    }

    /// Converts a `gbk-cache-https` URL back to its original `https` URL.
    ///
    /// For example: `gbk-cache-https://example.com/path` → `https://example.com/path`
    private func originalURL(for url: URL) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        // The scheme "gbk-cache-https" encodes the original scheme after the prefix
        let schemePrefix = "gbk-cache-"
        guard let scheme = components?.scheme, scheme.hasPrefix(schemePrefix) else {
            return nil
        }
        components?.scheme = String(scheme.dropFirst(schemePrefix.count))
        return components?.url
    }
}
