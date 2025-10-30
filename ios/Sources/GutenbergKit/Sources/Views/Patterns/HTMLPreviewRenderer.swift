import UIKit
import WebKit
import CryptoKit

/// Renders HTML content to images using a pool of WKWebView instances
///
/// This class manages a pool of reusable WKWebView instances to efficiently
/// render HTML content off-screen and capture screenshots. It includes:
/// - WKWebView pooling to reduce memory overhead
/// - Off-screen rendering for performance
/// - Memory and disk image caching to avoid redundant renders
/// - Concurrent rendering with request queuing
@MainActor
final class HTMLPreviewRenderer {
    static let shared = HTMLPreviewRenderer()

    // MARK: - Configuration

    private let poolSize = 3
    private let maxContentHeight: CGFloat = 2000 // Maximum height to prevent excessive memory usage
    private let memoryCacheLimit = 50

    // MARK: - State

    private var webViewPool: [PooledWebView] = []
    private var memoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 50
        return cache
    }()
    private var pendingRequests: [RenderRequest] = []
    private var activeRenders: Set<String> = []
    private let diskCache: DiskCache

    // MARK: - Types

    private struct RenderRequest {
        let id: String
        let html: String
        let viewportWidth: Int
        let continuation: CheckedContinuation<UIImage, Error>
    }

    @MainActor
    private class PooledWebView {
        let webView: WKWebView
        let delegate: RenderDelegate
        var isAvailable: Bool = true

        init() {
            let config = WKWebViewConfiguration()
            config.suppressesIncrementalRendering = true

            // Create web view with small initial frame for off-screen rendering
            // Frame will be adjusted per render based on viewport width and content height
            webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1200, height: 100), configuration: config)
            webView.backgroundColor = .clear
            webView.isOpaque = false // gets rid of the white flash upon content load in dark mode.
            webView.translatesAutoresizingMaskIntoConstraints = false
            webView.scrollView.bounces = false
            webView.scrollView.showsVerticalScrollIndicator = false
            webView.scrollView.backgroundColor = .clear

            delegate = RenderDelegate()
            webView.navigationDelegate = delegate
        }
    }

    private class RenderDelegate: NSObject, WKNavigationDelegate {
        var onRenderComplete: ((CGFloat) -> Void)?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Wait until the HTML document finished loading
            // This also waits for all resources within the HTML (images, videos) to be fully loaded
            webView.evaluateJavaScript("document.readyState") { [weak self] complete, _ in
                guard complete != nil else {
                    return
                }

                // Get content height using document.documentElement.scrollHeight
                // This captures margins on <html> tag, unlike document.body.scrollHeight
                webView.evaluateJavaScript("document.documentElement.scrollHeight") { height, _ in
                    guard let height = height as? CGFloat else {
                        self?.onRenderComplete?(480) // Fallback height
                        return
                    }

                    self?.onRenderComplete?(height)
                }
            }
        }
    }

    enum PreviewError: Error, LocalizedError {
        case renderingFailed
        case screenshotFailed
        case cancelled

        var errorDescription: String? {
            switch self {
            case .renderingFailed:
                return "Failed to render HTML content"
            case .screenshotFailed:
                return "Failed to capture screenshot"
            case .cancelled:
                return "Rendering was cancelled"
            }
        }
    }


    // MARK: - Initialization

    private init() {
        // Initialize disk cache
        self.diskCache = DiskCache()

        // Check CSS hash and clear cache if changed
        let currentCSSHash = Self.hashString(GutenbergCSSLoader.shared.css)
        if diskCache.cssHashChanged(currentHash: currentCSSHash) {
            diskCache.clearCache()
            diskCache.saveCSSHash(currentCSSHash)
        }

        // Pre-populate the pool
        for _ in 0..<poolSize {
            webViewPool.append(PooledWebView())
        }
    }

    /// Creates a SHA256 hash of a string
    private static func hashString(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Public API

    /// Renders HTML content to an image
    /// - Parameters:
    ///   - html: The HTML content to render
    ///   - viewportWidth: The viewport width for rendering
    ///   - cacheKey: Unique key for caching (typically pattern name)
    /// - Returns: Rendered image
    func render(html: String, viewportWidth: Int, cacheKey: String) async throws -> UIImage {
        // Generate cache key from HTML and viewport width
        let diskCacheKey = Self.generateCacheKey(html: html, viewportWidth: viewportWidth)

        // Check memory cache first
        if let cachedImage = memoryCache.object(forKey: cacheKey as NSString) {
            return cachedImage
        }

        // Check disk cache
        if let diskImage = diskCache.loadImage(forKey: diskCacheKey) {
            // Store in memory cache for faster access next time
            memoryCache.setObject(diskImage, forKey: cacheKey as NSString)
            return diskImage
        }

        // Check if already rendering this content
        if activeRenders.contains(cacheKey) {
            // Wait for existing render to complete by creating a new request
            return try await withCheckedThrowingContinuation { continuation in
                let request = RenderRequest(
                    id: cacheKey,
                    html: html,
                    viewportWidth: viewportWidth,
                    continuation: continuation
                )
                pendingRequests.append(request)
            }
        }

        // Mark as actively rendering
        activeRenders.insert(cacheKey)
        defer { activeRenders.remove(cacheKey) }

        // Get available web view or queue the request
        guard let pooledView = getAvailableWebView() else {
            return try await withCheckedThrowingContinuation { continuation in
                let request = RenderRequest(
                    id: cacheKey,
                    html: html,
                    viewportWidth: viewportWidth,
                    continuation: continuation
                )
                pendingRequests.append(request)
                processNextRequest()
            }
        }

        let image = try await performRender(
            html: html,
            viewportWidth: viewportWidth,
            cacheKey: cacheKey,
            pooledView: pooledView
        )

        // Save to disk cache
        diskCache.saveImage(image, forKey: diskCacheKey)

        return image
    }

    /// Generates a cache key from HTML content and viewport width
    private static func generateCacheKey(html: String, viewportWidth: Int) -> String {
        let combined = "\(html)-\(viewportWidth)"
        return hashString(combined)
    }

    /// Clears the image cache
    func clearCache() {
        memoryCache.removeAllObjects()
        diskCache.clearCache()
    }

    // MARK: - Private Methods

    private func getAvailableWebView() -> PooledWebView? {
        return webViewPool.first { $0.isAvailable }
    }

    private func performRender(
        html: String,
        viewportWidth: Int,
        cacheKey: String,
        pooledView: PooledWebView
    ) async throws -> UIImage {
        pooledView.isAvailable = false
        defer {
            pooledView.isAvailable = true
            processNextRequest()
        }

        let webView = pooledView.webView
        let delegate = pooledView.delegate

        // Set initial frame with small height so content can expand naturally
        // This ensures scrollHeight returns actual content height, not viewport height
        let width = CGFloat(viewportWidth)
        let minHeight: CGFloat = 100
        webView.frame = CGRect(x: 0, y: 0, width: width, height: minHeight)

        // Generate full HTML with styling
        let fullHTML = generateFullHTML(content: html, viewportWidth: viewportWidth)

        // Wait for rendering to complete using the delegate
        let contentHeight = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGFloat, Error>) in
            delegate.onRenderComplete = { height in
                continuation.resume(returning: height)
            }

            // Load HTML - the delegate will notify when ready
            webView.loadHTMLString(fullHTML, baseURL: nil)
        }

        let finalHeight = min(contentHeight, maxContentHeight)

        // Update frame to actual content size
        webView.frame = CGRect(x: 0, y: 0, width: width, height: finalHeight)

        // Force layout update
        webView.layoutIfNeeded()

        // Take screenshot of entire content
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: width, height: finalHeight)

        guard let image = try? await webView.takeSnapshot(configuration: config) else {
            throw PreviewError.screenshotFailed
        }

        // Clear the delegate callback
        delegate.onRenderComplete = nil

        // Cache the result in memory
        memoryCache.setObject(image, forKey: cacheKey as NSString)

        // Notify any waiting requests
        notifyPendingRequests(for: cacheKey, with: image)

        return image
    }

    private func processNextRequest() {
        guard !pendingRequests.isEmpty,
              let pooledView = getAvailableWebView() else {
            return
        }

        let request = pendingRequests.removeFirst()

        Task {
            do {
                let image = try await performRender(
                    html: request.html,
                    viewportWidth: request.viewportWidth,
                    cacheKey: request.id,
                    pooledView: pooledView
                )
                request.continuation.resume(returning: image)
            } catch {
                request.continuation.resume(throwing: error)
            }
        }
    }

    private func notifyPendingRequests(for cacheKey: String, with image: UIImage) {
        let matchingRequests = pendingRequests.filter { $0.id == cacheKey }
        pendingRequests.removeAll { $0.id == cacheKey }

        for request in matchingRequests {
            request.continuation.resume(returning: image)
        }
    }

    private func generateFullHTML(content: String, viewportWidth: Int) -> String {
        return """
        <!DOCTYPE html>
        <html style="margin: 0; padding: 0;">
        <head>
            <meta name="viewport" content="width=\(viewportWidth), initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * { box-sizing: border-box; }
                body {
                    margin: 0;
                    padding: 0;
                    width: \(viewportWidth)px;
                    background: white;
                }
            </style>
            <style>
                \(GutenbergCSSLoader.shared.css)
            </style>
        </head>
        <body class="block-editor-iframe__body editor-styles-wrapper wp-embed-responsive">
            \(content)
        </body>
        </html>
        """
    }
}

// MARK: - Disk Cache

/// Manages disk caching of rendered preview images
class DiskCache {
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let manifestURL: URL

    init() {
        // Create cache directory in Caches folder
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = cachesDirectory.appendingPathComponent("pattern-previews", isDirectory: true)
        self.manifestURL = cacheDirectory.appendingPathComponent("manifest.json")

        // Create directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Check if CSS hash has changed
    func cssHashChanged(currentHash: String) -> Bool {
        guard let manifest = loadManifest() else {
            return true // No manifest means first run or cache cleared
        }
        return manifest.cssHash != currentHash
    }

    /// Save CSS hash to manifest
    func saveCSSHash(_ hash: String) {
        let manifest = CacheManifest(cssHash: hash)
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: manifestURL)
    }

    /// Load image from disk cache
    func loadImage(forKey key: String) -> UIImage? {
        let fileURL = cacheDirectory.appendingPathComponent("\(key).png")
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }

    /// Save image to disk cache
    func saveImage(_ image: UIImage, forKey key: String) {
        let fileURL = cacheDirectory.appendingPathComponent("\(key).png")
        guard let data = image.pngData() else { return }
        try? data.write(to: fileURL)
    }

    /// Clear all cached images
    func clearCache() {
        guard let contents = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        for fileURL in contents {
            // Keep manifest, delete everything else
            if fileURL != manifestURL {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    private func loadManifest() -> CacheManifest? {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(CacheManifest.self, from: data) else {
            return nil
        }
        return manifest
    }

    private struct CacheManifest: Codable {
        let cssHash: String
    }
}

// MARK: - Shared CSS Loader

@MainActor
class GutenbergCSSLoader {
    static let shared = GutenbergCSSLoader()

    /// Cached Gutenberg CSS loaded once
    let css: String

    private init() {
        self.css = Self.loadGutenbergCSS() ?? ""
    }

    /// Loads the Gutenberg CSS from the bundled assets
    private static func loadGutenbergCSS() -> String? {
        guard let assetsURL = Bundle.module.url(forResource: "Gutenberg", withExtension: nil),
              let assetsPath = try? FileManager.default.contentsOfDirectory(
                at: assetsURL.appendingPathComponent("assets"),
                includingPropertiesForKeys: nil
              ) else {
            return nil
        }

        guard let cssURL = assetsPath.first(where: { url in
            let filename = url.lastPathComponent
            return filename.hasPrefix("index-") && filename.hasSuffix(".css")
        }) else {
            return nil
        }

        return try? String(contentsOf: cssURL, encoding: .utf8)
    }
}
