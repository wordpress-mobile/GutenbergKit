#if canImport(UIKit)
import WebKit

/// Manages a pool of WKWebView instances for rendering HTML content.
///
/// This class handles:
/// - Pooling and reusing WKWebView instances to reduce memory overhead
/// - Automatic cleanup of idle webviews after 5 seconds of inactivity
@MainActor
final class HTMLWebViewRenderer {
    private var webViewPool: [PooledWebView] = []
    private var idleCleanupTask: Task<Void, Never>?

    nonisolated init() {}

    /// Renders HTML content to an image.
    func render(html: String, viewportWidth: Int) async throws -> UIImage {
        cancelCleanup()

        let pooledView = getAvailableWebView()
        pooledView.isAvailable = false
        defer {
            pooledView.isAvailable = true
            scheduleCleanup()
        }

        let webView = pooledView.webView

        let width = CGFloat(viewportWidth)

        // Set initial frame with small height so content can expand naturally
        // This ensures scrollHeight returns actual content height, not viewport height
        webView.frame = CGRect(x: 0, y: 0, width: width, height: 80)

        let contentHeight = try await pooledView.render(html: html) ?? width

        // Take screenshot of entire content with the maximum target size we'll ever need (roughly)
        // Calculate snapshot width such that neither dimension exceeds the maximum size
        let maxDimension = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height, 640) - 48
        let scaleForWidth = maxDimension / width
        let scaleForHeight = maxDimension / contentHeight
        let scale = min(scaleForWidth, scaleForHeight, 1.0) // Don't scale up, only down
        let snapshotWidth = width * scale

        let config = WKSnapshotConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: width, height: contentHeight)
        config.snapshotWidth = NSNumber(value: snapshotWidth)

        let image = try await webView.takeSnapshot(configuration: config)

        return image
    }

    private func getAvailableWebView() -> PooledWebView {
        if let pooledView = webViewPool.first(where: \.isAvailable) {
            return pooledView
        }
        let pooledView = PooledWebView()
        webViewPool.append(pooledView)
        return pooledView
    }

    // MARK: - Cleanup

    private func scheduleCleanup() {
        idleCleanupTask?.cancel()
        idleCleanupTask = Task {
            do {
                try await Task.sleep(for: .seconds(5))
                webViewPool.removeAll()
            } catch {
                // Do nothing (cancelled)
            }
        }
    }

    private func cancelCleanup() {
        idleCleanupTask?.cancel()
        idleCleanupTask = nil
    }

    // MARK: - Nested Types

    @MainActor
    private class PooledWebView {
        let webView: WKWebView
        let delegate: RenderDelegate
        var isAvailable = true

        init() {
            let config = WKWebViewConfiguration()
            config.suppressesIncrementalRendering = true

            // Create web view with small initial frame for off-screen rendering
            // Frame will be adjusted per render based on viewport width and content height
            webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1200, height: 100), configuration: config)
            webView.applicationNameForUserAgent = "GutenbergKit/\(GBKVersion.version)"

            delegate = RenderDelegate()
            webView.navigationDelegate = delegate
        }

        /// Loads HTML content and waits for rendering to complete with timeout.
        func render(html: String) async throws -> CGFloat? {
            try await withCheckedThrowingContinuation { continuation in
                let timeoutTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(16))
                    if !Task.isCancelled {
                        delegate.onRenderComplete = nil
                        continuation.resume(throwing: URLError(.timedOut))
                    }
                }
                delegate.onRenderComplete = { [weak self] height in
                    guard !timeoutTask.isCancelled else { return }
                    timeoutTask.cancel()
                    self?.delegate.onRenderComplete = nil
                    continuation.resume(returning: height)
                }
                webView.loadHTMLString(html, baseURL: nil)
            }
        }
    }

    @MainActor
    private class RenderDelegate: NSObject, WKNavigationDelegate {
        var onRenderComplete: ((CGFloat?) -> Void)?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Get content height using document.documentElement.scrollHeight
            // This captures margins on <html> tag, unlike document.body.scrollHeight
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { [weak self] height, _ in
                self?.onRenderComplete?(height as? CGFloat)
            }
        }
    }
}
#endif
