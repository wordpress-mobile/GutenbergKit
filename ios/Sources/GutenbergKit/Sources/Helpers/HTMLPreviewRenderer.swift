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
/// - Two-tier caching strategy:
///   - Disk cache: Stores full-size rendered images at pattern viewport width
///   - Memory cache: Stores size-specific thumbnails created via preparingThumbnail()
/// - Concurrent rendering with request queuing
/// - Background execution of disk I/O operations
@MainActor
public final class HTMLPreviewRenderer {
    public static let shared = HTMLPreviewRenderer()

    // MARK: - Configuration

    private let poolSize = 2
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
    private let urlCache: URLCache

    // Cached CSS for background HTML generation
    private let gutenbergCSS: String
    private let gutenbergCSSHash: String

    // MARK: - Types

    private struct RenderRequest {
        let diskCacheKey: String
        let html: String
        let viewportWidth: Int
        let maximumDimension: MaximumDimension
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
            diskCapacity: 16 * 1024 * 1024, // 16 MB disk limit
            directory: urlCacheDirectory
        )

        // Pre-populate the web view pool
        for _ in 0..<poolSize {
            webViewPool.append(PooledWebView())
        }
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

    /// Maximum dimension constraint for thumbnail generation
    enum MaximumDimension {
        case width(CGFloat)
        case height(CGFloat)

        var value: CGFloat {
            switch self {
            case .width(let value), .height(let value):
                return value
            }
        }
    }

    /// Renders HTML content to an image
    /// - Parameters:
    ///   - html: The HTML content to render
    ///   - viewportWidth: The viewport width for rendering
    ///   - maximumDimension: Maximum dimension constraint (width or height) for the thumbnail
    /// - Returns: Thumbnail image constrained by the specified dimension
    func render(html: String, viewportWidth: Int, maximumDimension: MaximumDimension) async throws -> UIImage {

        print("request \(html.count)")

        // Generate disk cache key (HTML + viewport width + CSS hash)
        let diskCacheKey = await generateDiskCacheKey(html: html, viewportWidth: viewportWidth, cssHash: gutenbergCSSHash)

        // Generate memory cache key (includes maximum dimension)
        let memoryCacheKey = await generateMemoryCacheKey(diskKey: diskCacheKey, maximumDimension: maximumDimension)

        // Check memory cache first (stores thumbnails at specific sizes)
        if let cachedImage = memoryCache.object(forKey: memoryCacheKey as NSString) {
            print("mem cache hit \(html.count)")
            return cachedImage
        }

        // Check disk cache (stores full-size images at viewport width)
        if let diskImage = loadImageFromCache(forKey: diskCacheKey) {
            print("disk cache hit \(html.count)")
            // Create thumbnail from disk image using preparingThumbnail
            let thumbnail = await createThumbnail(from: diskImage, maximumDimension: maximumDimension)
            memoryCache.setObject(thumbnail, forKey: memoryCacheKey as NSString)
            return thumbnail
        }

        print("miss \(html.count)")

        // Check if already rendering this content
        if activeRenders.contains(diskCacheKey) {
            // Wait for existing render to complete by creating a new request
            return try await withCheckedThrowingContinuation { continuation in
                let request = RenderRequest(
                    diskCacheKey: diskCacheKey,
                    html: html,
                    viewportWidth: viewportWidth,
                    maximumDimension: maximumDimension,
                    continuation: continuation
                )
                pendingRequests.append(request)
            }
        }

        // Mark as actively rendering
        activeRenders.insert(diskCacheKey)
        defer { activeRenders.remove(diskCacheKey) }

        // Get available web view or queue the request
        guard let pooledView = getAvailableWebView() else {
            return try await withCheckedThrowingContinuation { continuation in
                let request = RenderRequest(
                    diskCacheKey: diskCacheKey,
                    html: html,
                    viewportWidth: viewportWidth,
                    maximumDimension: maximumDimension,
                    continuation: continuation
                )
                pendingRequests.append(request)
                processNextRequest()
            }
        }

        // Perform actual rendering (returns full-size image)
        let fullSizeImage = try await performRender(
            html: html,
            viewportWidth: viewportWidth,
            diskCacheKey: diskCacheKey,
            pooledView: pooledView
        )

        // Save full-size image to disk cache
        saveImageToCache(fullSizeImage, forKey: diskCacheKey)

        // Create thumbnail for the requested dimension
        let thumbnail = await createThumbnail(from: fullSizeImage, maximumDimension: maximumDimension)

        // Cache thumbnail in memory
        memoryCache.setObject(thumbnail, forKey: memoryCacheKey as NSString)

        return thumbnail
    }



    /// Clears the image cache (both memory and disk)
    public func clearCache() async {
        memoryCache.removeAllObjects()
        urlCache.removeAllCachedResponses()
    }

    /// Clears only the memory cache (keeps disk cache intact)
    func clearMemoryCache() {
        memoryCache.removeAllObjects()
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
        guard let data = imageToHEICData(image) else { return }

        print("store \(image.size) \(image.scale) \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")

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

    private func getAvailableWebView() -> PooledWebView? {
        return webViewPool.first { $0.isAvailable }
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
            processNextRequest()
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

        // Wait for rendering to complete using the delegate
        let contentHeight = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGFloat, Error>) in
            delegate.onRenderComplete = { height in
                delegate.onRenderComplete = nil
                continuation.resume(returning: height ?? width) // Fallback to square
            }
            webView.loadHTMLString(fullHTML, baseURL: nil)
        }

        // Take screenshot of entire content with the maximum target size we'll ever need (roughly)
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: width, height: contentHeight)
        config.snapshotWidth = NSNumber(value: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) - 48)

        let image = try await webView.takeSnapshot(configuration: config)

        notifyPendingRequests(for: diskCacheKey, with: image)

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
                let fullSizeImage = try await performRender(
                    html: request.html,
                    viewportWidth: request.viewportWidth,
                    diskCacheKey: request.diskCacheKey,
                    pooledView: pooledView
                )

                // Save full-size image to disk
                saveImageToCache(fullSizeImage, forKey: request.diskCacheKey)

                // Create thumbnail for requested dimension
                let thumbnail = await createThumbnail(from: fullSizeImage, maximumDimension: request.maximumDimension)

                // Cache thumbnail in memory
                let memoryCacheKey = await generateMemoryCacheKey(diskKey: request.diskCacheKey, maximumDimension: request.maximumDimension)
                memoryCache.setObject(thumbnail, forKey: memoryCacheKey as NSString)

                request.continuation.resume(returning: thumbnail)
            } catch {
                request.continuation.resume(throwing: error)
            }
        }
    }

    private func notifyPendingRequests(for diskCacheKey: String, with fullSizeImage: UIImage) {
        let matchingRequests = pendingRequests.filter { $0.diskCacheKey == diskCacheKey }
        pendingRequests.removeAll { $0.diskCacheKey == diskCacheKey }

        // Each pending request needs its own thumbnail at its target dimension
        for request in matchingRequests {
            Task {
                let thumbnail = await createThumbnail(from: fullSizeImage, maximumDimension: request.maximumDimension)

                // Cache the thumbnail in memory
                let memoryCacheKey = await generateMemoryCacheKey(diskKey: diskCacheKey, maximumDimension: request.maximumDimension)
                memoryCache.setObject(thumbnail, forKey: memoryCacheKey as NSString)

                request.continuation.resume(returning: thumbnail)
            }
        }
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

/// Generates a memory cache key from disk key and maximum dimension
private func generateMemoryCacheKey(diskKey: String, maximumDimension: HTMLPreviewRenderer.MaximumDimension) async -> String {
    let suffix: String
    switch maximumDimension {
    case .width(let value):
        suffix = "w\(Int(value))"
    case .height(let value):
        suffix = "h\(Int(value))"
    }
    let combined = "\(diskKey)-\(suffix)"
    return await hashString(combined)
}

/// Creates a thumbnail from an image using preparingThumbnail (runs in background)
private func createThumbnail(from image: UIImage, maximumDimension: HTMLPreviewRenderer.MaximumDimension) async -> UIImage {
    let scale = await UIScreen.main.scale

    // Calculate the thumbnail size in points maintaining aspect ratio
    // Note: image.size is already in points (accounts for scale)
    let aspectRatio = image.size.width / image.size.height

    let thumbnailSizePoints: CGSize
    switch maximumDimension {
    case .width(let maxWidth):
        // Constrain by width
        let thumbnailWidthPoints = min(maxWidth, image.size.width)
        let thumbnailHeightPoints = thumbnailWidthPoints / aspectRatio
        thumbnailSizePoints = CGSize(width: thumbnailWidthPoints, height: thumbnailHeightPoints)
    case .height(let maxHeight):
        // Constrain by height
        let thumbnailHeightPoints = min(maxHeight, image.size.height)
        let thumbnailWidthPoints = thumbnailHeightPoints * aspectRatio
        thumbnailSizePoints = CGSize(width: thumbnailWidthPoints, height: thumbnailHeightPoints)
    }

    // Convert to pixel dimensions for preparingThumbnail
    // We render at screen scale to maintain quality
    let thumbnailSizePixels = CGSize(
        width: thumbnailSizePoints.width * scale,
        height: thumbnailSizePoints.height * scale
    )

    // Use preparingThumbnail for efficient thumbnail generation
    // This method downsamples the image efficiently without loading full resolution
    if let thumbnailCGImage = image.preparingThumbnail(of: thumbnailSizePixels)?.cgImage {
        // Create UIImage with correct scale factor so it displays at the right size
        return UIImage(cgImage: thumbnailCGImage, scale: scale, orientation: image.imageOrientation)
    }

    // Fallback if preparingThumbnail fails - use UIGraphicsImageRenderer which handles scale
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    let renderer = UIGraphicsImageRenderer(size: thumbnailSizePoints, format: format)
    return renderer.image { context in
        image.draw(in: CGRect(origin: .zero, size: thumbnailSizePoints))
    }
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

/// Converts UIImage to HEIC data format
private func imageToHEICData(_ image: UIImage) -> Data? {
    guard let cgImage = image.cgImage else { return nil }

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.heic.identifier as CFString, 1, nil) else {
        return nil
    }

    let options: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: 0.85
    ]

    CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

    guard CGImageDestinationFinalize(destination) else {
        return nil
    }

    return data as Data
}

