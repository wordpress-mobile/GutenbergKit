import UIKit
import WebKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Renders HTML content to images using a pool of WKWebView instances.
///
/// This class manages a pool of reusable WKWebView instances to efficiently
/// render HTML content off-screen and capture screenshots. It includes:
/// - WKWebView pooling to reduce memory overhead
/// - Off-screen rendering for performance
/// - Disk cache: Stores full-size rendered images at pattern viewport width
/// - Concurrent rendering with request queuing
/// - Background execution of disk I/O operations
@MainActor
public final class HTMLPreviewRenderer {
    public static let shared = HTMLPreviewRenderer()

    // MARK: - Configuration

    private let maxConcurrentRenders = 2

    // MARK: - State

    private var webViewPool: [PooledWebView] = []

    // All requests (both queued and executing)
    private var requests: [RenderRequest] = []

    // Timer to clear pool when idle
    private var idleCleanupTask: Task<Void, Never>?

    private let urlCache: URLCache
    private var totalCachedBytes: Int64 = 0
    private var cachedImageCount: Int = 0

    // Cached CSS for background HTML generation
    private let gutenbergCSS: String
    private let gutenbergCSSHash: String

    // MARK: - Types

    private class RenderRequest {
        let diskCacheKey: String
        let html: String
        let viewportWidth: Int
        var continuations: [CheckedContinuation<UIImage, Error>]
        var task: Task<Void, Never>?

        init(diskCacheKey: String, html: String, viewportWidth: Int, continuation: CheckedContinuation<UIImage, Error>) {
            self.diskCacheKey = diskCacheKey
            self.html = html
            self.viewportWidth = viewportWidth
            self.continuations = [continuation]
        }
    }

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

            delegate = RenderDelegate()
            webView.navigationDelegate = delegate
        }
    }

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

    // MARK: - Initialization

    private init() {
        let css = Self.loadGutenbergCSS() ?? ""
        self.gutenbergCSS = css
        assert(!css.isEmpty, "Failed to load Gutenberg CSS from bundle. Previews will not render correctly.")

        // Precompute CSS hash for cache key generation
        let data = Data(css.utf8)
        let hash = SHA256.hash(data: data)
        self.gutenbergCSSHash = hash.compactMap { String(format: "%02x", $0) }.joined()

        let urlCacheDirectory = URL.cachesDirectory.appendingPathComponent("gbk-pattern-previews", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: urlCacheDirectory, withIntermediateDirectories: true)
        } catch {
            assertionFailure("failed to create cache directory: \(error)")
        }

        // The previews often have graphics included and are non opaque. The
        // most efficient format for it on iOS is HEIF.
        self.urlCache = URLCache(
            memoryCapacity: 0, // Disable memory cache (we use NSCache for thumbnails)
            diskCapacity: 16 * 1024 * 1024, // 16 MB
            directory: urlCacheDirectory
        )
    }

    /// Loads the Gutenberg CSS from the bundled assets
    private static func loadGutenbergCSS() -> String? {
        // Check if Gutenberg resource exists in bundle
        guard let assetsURL = Bundle.module.url(forResource: "Gutenberg", withExtension: nil) else {
            assertionFailure("Gutenberg resource not found in bundle")
            return nil
        }

        // Check if assets directory exists
        let assetsDirectory = assetsURL.appendingPathComponent("assets")
        guard let assetsPath = try? FileManager.default.contentsOfDirectory(
            at: assetsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            assertionFailure("Failed to read assets directory at: \(assetsDirectory.path)")
            return nil
        }

        // Find CSS file matching pattern: index-*.css
        guard let cssURL = assetsPath.first(where: { url in
            let filename = url.lastPathComponent
            return filename.hasPrefix("index-") && filename.hasSuffix(".css")
        }) else {
            assertionFailure("No CSS file matching 'index-*.css' found in assets. Available files: \(assetsPath.map { $0.lastPathComponent })")
            return nil
        }

        // Load CSS file contents
        guard let css = try? String(contentsOf: cssURL, encoding: .utf8) else {
            assertionFailure("Failed to load CSS from: \(cssURL.path)")
            return nil
        }

        return css
    }


    // MARK: - Public API

    /// Renders HTML content to an image
    /// - Parameters:
    ///   - html: The HTML content to render
    ///   - viewportWidth: The viewport width for rendering
    /// - Returns: Full-size rendered image at the specified viewport width
    func render(html: String, viewportWidth: Int) async throws -> UIImage {

        print("request \(html.count)")

        // Generate disk cache key (HTML + viewport width + CSS hash)
        let diskCacheKey = await generateDiskCacheKey(html: html, viewportWidth: viewportWidth, cssHash: gutenbergCSSHash)

        // Check disk cache (stores full-size images at viewport width)
        if let diskImage = loadImageFromCache(forKey: diskCacheKey) {
            print("disk cache hit \(html.count)")
            return diskImage
        }

        print("miss \(html.count)")

        return try await withCheckedThrowingContinuation { continuation in
            // Cancel idle cleanup since we have work to do
            idleCleanupTask?.cancel()
            idleCleanupTask = nil

            // Check if this content is already queued or executing (deduplication)
            if let existingRequest = requests.first(where: { $0.diskCacheKey == diskCacheKey }) {
                existingRequest.continuations.append(continuation)
                return
            }

            // Create new request
            let request = RenderRequest(
                diskCacheKey: diskCacheKey,
                html: html,
                viewportWidth: viewportWidth,
                continuation: continuation
            )
            requests.append(request)

            // Start rendering if under capacity
            let executingCount = requests.filter { $0.task != nil }.count
            if executingCount < maxConcurrentRenders {
                startRender(request: request)
            }
        }
    }

    /// Clears the disk cache
    public func clearCache() async {
        urlCache.removeAllCachedResponses()
    }

    // MARK: - URLCache Helpers

    /// Load image from URLCache
    private func loadImageFromCache(forKey key: String) -> UIImage? {

        #warning("TEMP")
        return nil

        let url = URL(string: "preview://\(key)")!
        let request = URLRequest(url: url)

        guard let cachedResponse = urlCache.cachedResponse(for: request),
              let image = UIImage(data: cachedResponse.data) else {
            return nil
        }
        return image
    }

    /// Save image to URLCache
    private func saveImageToCache(_ image: UIImage, forKey key: String) {
        guard let data = encode(image) else { return }

        totalCachedBytes += Int64(data.count)
        cachedImageCount += 1
        let averageSize = totalCachedBytes / Int64(cachedImageCount)

        print("store \(image.size) \(image.scale) size=\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)) avg=\(ByteCountFormatter.string(fromByteCount: averageSize, countStyle: .file))")

        let url = URL(string: "preview://\(key)")!
        let request = URLRequest(url: url)
        let response = URLResponse(
            url: url,
            mimeType: "image/heic",
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        let cachedResponse = CachedURLResponse(response: response, data: data)
        urlCache.storeCachedResponse(cachedResponse, for: request)
    }

    // MARK: - Private Methods

    private func getAvailableWebView() -> PooledWebView {
        // Try to find an available web view
        if let pooledView = webViewPool.first(where: { $0.isAvailable }) {
            return pooledView
        }

        // Create new web view if needed
        let pooledView = PooledWebView()
        webViewPool.append(pooledView)
        return pooledView
    }

    private func startRender(request: RenderRequest) {
        request.task = Task {
            do {
                let pooledView = getAvailableWebView()

                // Perform actual rendering
                let image = try await performRender(
                    html: request.html,
                    viewportWidth: request.viewportWidth,
                    diskCacheKey: request.diskCacheKey,
                    pooledView: pooledView
                )

                // Save to disk cache
                saveImageToCache(image, forKey: request.diskCacheKey)

                // Resume all continuations with success
                for continuation in request.continuations {
                    continuation.resume(returning: image)
                }
            } catch {
                // Resume all continuations with error
                for continuation in request.continuations {
                    continuation.resume(throwing: error)
                }
            }

            // Remove this request from the list
            requests.removeAll { $0 === request }

            // Process next queued request if any
            processNextRequest()
        }
    }

    private func processNextRequest() {
        // Find first queued request (not executing yet)
        guard let nextRequest = requests.first(where: { $0.task == nil }) else {
            // No more requests - schedule cleanup
            scheduleIdleCleanup()
            return
        }

        // Check if we have capacity
        let executingCount = requests.filter { $0.task != nil }.count
        guard executingCount < maxConcurrentRenders else {
            return
        }

        startRender(request: nextRequest)
    }

    private func scheduleIdleCleanup() {
        // Cancel any existing cleanup task
        idleCleanupTask?.cancel()

        // Schedule cleanup after 5 seconds of inactivity
        idleCleanupTask = Task {
            do {
                try await Task.sleep(for: .seconds(5))
                // Clear the webview pool to free resources
                webViewPool.removeAll()
            } catch {
                // Task was cancelled, which is fine
            }
        }
    }

    private func performRender(
        html: String,
        viewportWidth: Int,
        diskCacheKey: String,
        pooledView: PooledWebView
    ) async throws -> UIImage {
        pooledView.isAvailable = false
        defer {
            pooledView.isAvailable = true
        }

        let webView = pooledView.webView
        let delegate = pooledView.delegate

        let width = CGFloat(viewportWidth)

        // Set initial frame with small height so content can expand naturally
        // This ensures scrollHeight returns actual content height, not viewport height
        webView.frame = CGRect(x: 0, y: 0, width: width, height: 80)

        let fullHTML = await generateFullHTML(
            content: html,
            viewportWidth: viewportWidth,
            css: gutenbergCSS
        )

        // Wait for rendering to complete using the delegate with 16-second timeout
        let contentHeight: CGFloat = try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(16))
                if !Task.isCancelled {
                    delegate.onRenderComplete = nil
                    continuation.resume(throwing: URLError(.timedOut))
                }
            }
            delegate.onRenderComplete = { height in
                guard !timeoutTask.isCancelled else { return }
                timeoutTask.cancel()
                delegate.onRenderComplete = nil
                continuation.resume(returning: height ?? width) // Fallback to square
            }
            webView.loadHTMLString(fullHTML, baseURL: nil)
        }

        // Take screenshot of entire content with the maximum target size we'll ever need (roughly)
        // Calculate snapshot width such that neither dimension exceeds the maximum size
        let maxDimension = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) - 48
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

}

// MARK: - Private Helper Functions

/// Creates a SHA256 hash of a string (runs in background)
private func hashString(_ string: String) async -> String {
    let data = Data(string.utf8)
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}

/// Generates a disk cache key from HTML content, viewport width, and CSS hash
private func generateDiskCacheKey(html: String, viewportWidth: Int, cssHash: String) async -> String {
    let combined = "\(html)-\(viewportWidth)-\(cssHash)"
    return await hashString(combined)
}

/// Generates full HTML with styling (runs in background)
private func generateFullHTML(content: String, viewportWidth: Int, css: String) async -> String {
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
            \(css)
        </style>
    </head>
    <body class="block-editor-iframe__body editor-styles-wrapper wp-embed-responsive">
        \(content)
    </body>
    </html>
    """
}

/// Converts UIImage to HEIC data format.
private func encode(_ image: UIImage) -> Data? {
    guard let cgImage = image.cgImage else { return nil }

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.heic.identifier as CFString, 1, nil) else {
        return nil
    }

    // Important to ignore the alpha channel (we now screenshots are opaque)
    // to avoid warnings from ImageIO about saving HEIF with alpha channel but
    // opqaue pixels. Storing opqaue images reduces the image size and the
    // memory needed for decoding by two times.
    let options: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: 0.85,
        kCGImagePropertyHasAlpha: false,
    ]

    CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

    guard CGImageDestinationFinalize(destination) else {
        return nil
    }

    return data as Data
}

