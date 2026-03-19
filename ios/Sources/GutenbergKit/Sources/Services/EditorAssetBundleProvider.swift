import Foundation
import OSLog
import WebKit

/// Serves cached plugin and theme assets to the editor WebView.
///
/// `EditorAssetBundleProvider` acts as a bridge between the WKWebView and the on-disk
/// asset cache. It registers itself as a URL scheme handler to serve individual cached
/// files via the `gbk-cache-https` scheme.
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
@MainActor
public final class EditorAssetBundleProvider: NSObject {

    private var bundle: EditorAssetBundle?
    private let httpClient: EditorHTTPClient
    private var runningTasks: [Task<Void, Never>] = []

    public init(httpClient: EditorHTTPClient) {
        self.httpClient = httpClient
        super.init()
    }

    /// Sets the asset bundle to serve to the WebView.
    ///
    /// This method is thread-safe and can be called from any thread.
    ///
    /// - Parameter bundle: The downloaded asset bundle containing cached scripts and styles.
    public func set(bundle: EditorAssetBundle) {
        self.bundle = bundle
    }

    /// Registers this provider with a WebView configuration.
    ///
    /// This method registers a URL scheme handler to serve individual cached files.
    ///
    /// - Parameter configuration: The WebView configuration to register with.
    @MainActor
    public func bind(to configuration: WKWebViewConfiguration) {
        // Register the handler for individual cached assets
        configuration.setURLSchemeHandler(self, forURLScheme: "gbk-cache-https")
    }
}

extension EditorAssetBundleProvider: WKURLSchemeHandler {
    public func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        logExecutionTime("Retrieved cached asset") {
            Logger.assetLibrary.info("📚 Editor requested a cached asset")

            guard let url = urlSchemeTask.request.url else {
                Logger.assetLibrary.info("     URL: <missing>")
                urlSchemeTask.didFailWithError(URLError(.badURL))
                return
            }

            Logger.assetLibrary.info("     URL: \(url)")

            guard let bundle else {
                preconditionFailure("Cannot read asset with no bundle present. This is a programmer error.")
            }

            // Check if the path is valid and the asset exists in the bundle.
            // If not, fetch from the original HTTPS URL (e.g., for plugin SVGs
            // referenced in CSS that weren't downloaded into the bundle).
            let shouldFetchFromRemote = !bundle.isValidAssetPath(for: url) || !bundle.hasAssetData(for: url)

            guard !shouldFetchFromRemote else {
                Logger.assetLibrary.info("     Asset not in bundle – fetching from remote")
                self.fetchFromRemote(for: urlSchemeTask)
                return
            }

            do {
                Logger.assetLibrary.info("     Path: \(bundle.assetDataPath(for: url))")

                let data = try bundle.assetData(for: url)
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch {
                Logger.assetLibrary.warning("     Error: \(error.localizedDescription)")
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
    private func fetchFromRemote(for urlSchemeTask: any WKURLSchemeTask) {
        guard let originalRequest = self.originalRequest(for: urlSchemeTask.request) else {
            Logger.assetLibrary.info("     Failed to construct original URL")
            let response = HTTPURLResponse(
                url: urlSchemeTask.request.url!,
                statusCode: 400,
                httpVersion: nil,
                headerFields: nil
            )!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didFinish()
            return
        }

        Logger.assetLibrary.info("     Fetching: \(originalRequest)")

        let taskHandle = Task {
            do {
                let (data, response) = try await self.httpClient.perform(originalRequest)

                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            }
            catch {
                Logger.assetLibrary.error("📚 Failed to fetch remote asset: \(error.localizedDescription)")
                urlSchemeTask.didFailWithError(error)
            }
        }

        self.runningTasks.append(taskHandle)
    }

    /// Converts a `gbk-cache-https` URL back to its original `https` URL.
    ///
    /// For example: `gbk-cache-https://example.com/path` → `https://example.com/path`
    private func originalRequest(for request: URLRequest) -> URLRequest? {
        guard let url = request.url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        // The scheme "gbk-cache-https" encodes the original scheme after the prefix
        let schemePrefix = "gbk-cache-"
        guard let scheme = components.scheme, scheme.hasPrefix(schemePrefix) else {
            return nil
        }
        components.scheme = String(scheme.dropFirst(schemePrefix.count))

        var mutableCopy = request
        mutableCopy.url = components.url
        return mutableCopy
    }
}
