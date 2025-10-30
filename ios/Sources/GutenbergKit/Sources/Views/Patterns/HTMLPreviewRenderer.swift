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
    private let previewHeight: CGFloat = 120
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

    private class PooledWebView {
        let webView: WKWebView
        var isAvailable: Bool = true

        init() {
            let config = WKWebViewConfiguration()
            config.suppressesIncrementalRendering = true

            // Create web view with fixed frame for off-screen rendering
            self.webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 480), configuration: config)
            self.webView.scrollView.isScrollEnabled = false
            self.webView.scrollView.bounces = false
            self.webView.isOpaque = false
            self.webView.backgroundColor = .white
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

        // Update web view frame based on viewport width
        let scale = previewHeight / 480.0 // Scale to fit preview height
        let adjustedWidth = CGFloat(viewportWidth) * scale
        webView.frame = CGRect(x: 0, y: 0, width: adjustedWidth, height: previewHeight)

        // Generate full HTML with styling
        let fullHTML = generateFullHTML(content: html, viewportWidth: viewportWidth)

        // Load HTML
        webView.loadHTMLString(fullHTML, baseURL: nil)

        // Wait for load to complete
        try await waitForLoad(webView: webView)

        // Take screenshot
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: adjustedWidth, height: previewHeight)

        guard let image = try? await webView.takeSnapshot(configuration: config) else {
            throw PreviewError.screenshotFailed
        }

        // Cache the result
        cache.setObject(image, forKey: cacheKey as NSString)

        // Notify any waiting requests
        notifyPendingRequests(for: cacheKey, with: image)

        return image
    }

    private func waitForLoad(webView: WKWebView) async throws {
        // Wait for web view to finish loading
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var observer: NSKeyValueObservation?

            observer = webView.observe(\.isLoading, options: [.new]) { webView, _ in
                if !webView.isLoading {
                    observer?.invalidate()
                    // Give a small delay for rendering to stabilize
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                        continuation.resume()
                    }
                }
            }

            // If already loaded, resume immediately
            if !webView.isLoading {
                observer?.invalidate()
                continuation.resume()
            }
        }
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
        <html>
        <head>
            <meta name="viewport" content="width=\(viewportWidth), initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * {
                    box-sizing: border-box;
                }

                html, body {
                    margin: 0;
                    padding: 16px;
                    background: white;
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Oxygen-Sans, Ubuntu, Cantarell, "Helvetica Neue", sans-serif;
                    font-size: 16px;
                    line-height: 1.5;
                    color: #1e1e1e;
                    overflow: hidden;
                }

                body {
                    width: \(viewportWidth)px;
                    min-height: 100vh;
                }

                /* WordPress block styles */
                .wp-block-image img {
                    max-width: 100%;
                    height: auto;
                }

                .wp-block-image {
                    margin: 0 0 1em 0;
                }

                .wp-block-heading,
                h1, h2, h3, h4, h5, h6 {
                    font-weight: 600;
                    margin: 0.67em 0;
                    line-height: 1.3;
                }

                .wp-block-paragraph,
                p {
                    margin: 0 0 1em 0;
                }

                .wp-block-quote {
                    margin: 1em 0;
                    padding-left: 1em;
                    border-left: 4px solid #e0e0e0;
                }

                .wp-block-list,
                ul, ol {
                    margin: 0 0 1em 0;
                    padding-left: 1.5em;
                }

                .wp-block-button {
                    margin: 0.5em 0;
                }

                .wp-block-button__link {
                    background-color: #007cba;
                    border: none;
                    border-radius: 4px;
                    color: white;
                    padding: 0.5em 1em;
                    text-decoration: none;
                    display: inline-block;
                }

                .wp-block-columns {
                    display: flex;
                    gap: 2em;
                    margin: 1em 0;
                }

                .wp-block-column {
                    flex: 1;
                }

                .wp-block-group {
                    margin: 1em 0;
                }

                /* Hide elements that don't render well in preview */
                .wp-block-embed,
                .wp-block-video,
                .wp-block-audio {
                    background: #f0f0f0;
                    padding: 2em;
                    text-align: center;
                    color: #666;
                }

                /* Ensure images load properly */
                img {
                    max-width: 100%;
                    height: auto;
                    display: block;
                }

                /* Figcaption styling */
                figcaption {
                    font-size: 0.875em;
                    color: #666;
                    margin-top: 0.5em;
                }

                /* Cover block */
                .wp-block-cover {
                    min-height: 200px;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    padding: 1em;
                    background: #f0f0f0;
                }
            </style>
        </head>
        <body>
            \(content)
        </body>
        </html>
        """
    }
}
