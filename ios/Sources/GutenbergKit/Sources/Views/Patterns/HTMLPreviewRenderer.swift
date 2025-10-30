import UIKit
import WebKit

/// Renders HTML content to images using a pool of WKWebView instances
///
/// This class manages a pool of reusable WKWebView instances to efficiently
/// render HTML content off-screen and capture screenshots. It includes:
/// - WKWebView pooling to reduce memory overhead
/// - Off-screen rendering for performance
/// - Image caching to avoid redundant renders
/// - Concurrent rendering with request queuing
@MainActor
final class HTMLPreviewRenderer {
    static let shared = HTMLPreviewRenderer()

    // MARK: - Configuration

    private let poolSize = 3
    private let maxContentHeight: CGFloat = 2000 // Maximum height to prevent excessive memory usage
    private let cacheLimit = 50

    // MARK: - State

    private var webViewPool: [PooledWebView] = []
    private var cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 50
        return cache
    }()
    private var pendingRequests: [RenderRequest] = []
    private var activeRenders: Set<String> = []

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

            // Create web view with initial frame for off-screen rendering
            // Frame will be adjusted per render based on viewport width
            webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1200, height: 2000), configuration: config)
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

    // MARK: - CSS Loading

    /// Lazily loaded Gutenberg CSS from bundled assets
    private lazy var gutenbergCSS: String = {
        loadGutenbergCSS() ?? ""
    }()

    /// Loads the Gutenberg CSS from the bundled assets
    /// - Returns: The CSS content, or nil if not found
    private func loadGutenbergCSS() -> String? {
        // Find the Gutenberg assets directory
        guard let assetsURL = Bundle.module.url(forResource: "Gutenberg", withExtension: nil),
              let assetsPath = try? FileManager.default.contentsOfDirectory(
                at: assetsURL.appendingPathComponent("assets"),
                includingPropertiesForKeys: nil
              ) else {
            print("Warning: Could not find Gutenberg assets directory")
            return nil
        }

        // Find the main CSS file (starts with "index-" and ends with ".css")
        guard let cssURL = assetsPath.first(where: { url in
            let filename = url.lastPathComponent
            return filename.hasPrefix("index-") && filename.hasSuffix(".css")
        }) else {
            print("Warning: Could not find Gutenberg CSS file")
            return nil
        }

        // Read the CSS content
        guard let cssContent = try? String(contentsOf: cssURL, encoding: .utf8) else {
            print("Warning: Could not read Gutenberg CSS file")
            return nil
        }

        return cssContent
    }

    // MARK: - Initialization

    private init() {
        // Pre-populate the pool
        for _ in 0..<poolSize {
            webViewPool.append(PooledWebView())
        }
    }

    // MARK: - Public API

    /// Renders HTML content to an image
    /// - Parameters:
    ///   - html: The HTML content to render
    ///   - viewportWidth: The viewport width for rendering
    ///   - cacheKey: Unique key for caching (typically pattern name)
    /// - Returns: Rendered image
    func render(html: String, viewportWidth: Int, cacheKey: String) async throws -> UIImage {
        // Check cache first
        if let cachedImage = cache.object(forKey: cacheKey as NSString) {
            return cachedImage
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

        return try await performRender(
            html: html,
            viewportWidth: viewportWidth,
            cacheKey: cacheKey,
            pooledView: pooledView
        )
    }

    /// Clears the image cache
    func clearCache() {
        cache.removeAllObjects()
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

        // Set initial frame with viewport width and large height to accommodate content
        let width = CGFloat(viewportWidth)
        webView.frame = CGRect(x: 0, y: 0, width: width, height: maxContentHeight)

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

        // Cache the result
        cache.setObject(image, forKey: cacheKey as NSString)

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
        // Base styles matching Gutenberg's BlockPreview component
        // These match the auto.js implementation for pattern previews
        let baseStyles = """
            /* Base container styles */
            * {
                box-sizing: border-box;
            }

            html {
                margin: 0;
                padding: 0;
            }

            /* Matches Gutenberg's BlockPreview iframe body styles */
            body {
                height: auto;
                overflow: hidden;
                border: none;
                padding: 16px;
                margin: 0;
                width: \(viewportWidth)px;
                background: white;
                box-sizing: border-box;
            }
        """

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=\(viewportWidth), initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                \(baseStyles)
            </style>
            <style>
                /* Gutenberg Editor Styles */
                \(gutenbergCSS)
            </style>
        </head>
        <body class="block-editor-iframe__body editor-styles-wrapper wp-embed-responsive">
            \(content)
        </body>
        </html>
        """
    }
}
