import UIKit
import WebKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Renders HTML content to images using a pool of WKWebView instances.
///
/// This actor manages a pool of reusable WKWebView instances to efficiently
/// render HTML content off-screen and capture screenshots. It includes:
/// - WKWebView pooling to reduce memory overhead
/// - Off-screen rendering for performance
/// - Disk cache: Stores full-size rendered images at pattern viewport width
/// - Concurrent rendering with request queuing
/// - Background execution of disk I/O operations
public actor HTMLPreviewRenderer {
    public static let shared = HTMLPreviewRenderer()

    // MARK: - Configuration

    private let maxConcurrentRenders = 2

    // MARK: - State

    private let webViewRenderer = WebViewRenderer()

    // All requests (both queued and executing)
    private var requests: [RenderRequest] = []

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
        let diskCacheKey = generateDiskCacheKey(html: html, viewportWidth: viewportWidth, cssHash: gutenbergCSSHash)

        // Check disk cache (stores full-size images at viewport width)
        if let diskImage = loadImageFromCache(forKey: diskCacheKey) {
            print("disk cache hit \(html.count)")
            return diskImage
        }

        print("miss \(html.count)")

        return try await withCheckedThrowingContinuation { continuation in
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

    private func startRender(request: RenderRequest) {
        request.task = Task {
            do {
                // Generate full HTML (expensive operation on actor)
                let fullHTML = generateFullHTML(
                    content: request.html,
                    viewportWidth: request.viewportWidth,
                    css: gutenbergCSS
                )

                // Perform actual rendering
                let image = try await webViewRenderer.render(
                    fullHTML: fullHTML,
                    viewportWidth: request.viewportWidth
                )

                // Save to disk cache
                await saveImageToCache(image, forKey: request.diskCacheKey)

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
            await self.removeRequest(request)

            // Process next queued request if any
            await processNextRequest()
        }
    }

    private func removeRequest(_ request: RenderRequest) {
        requests.removeAll { $0 === request }
    }

    private func processNextRequest() {
        // Find first queued request (not executing yet)
        guard let nextRequest = requests.first(where: { $0.task == nil }) else {
            return
        }

        // Check if we have capacity
        let executingCount = requests.filter { $0.task != nil }.count
        guard executingCount < maxConcurrentRenders else {
            return
        }

        startRender(request: nextRequest)
    }

}

// MARK: - Private Helper Functions

/// Creates a SHA256 hash of a string
private func hashString(_ string: String) -> String {
    let data = Data(string.utf8)
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}

/// Generates a disk cache key from HTML content, viewport width, and CSS hash
private func generateDiskCacheKey(html: String, viewportWidth: Int, cssHash: String) -> String {
    let combined = "\(html)-\(viewportWidth)-\(cssHash)"
    return hashString(combined)
}

/// Generates full HTML with styling
private func generateFullHTML(content: String, viewportWidth: Int, css: String) -> String {
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

