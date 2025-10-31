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
public actor HTMLPreviewManager {
    public static let shared = HTMLPreviewManager()

    // MARK: - Configuration

    private let maxConcurrentRenders = 2

    // MARK: - State

    private let htmlRenderer = HTMLWebViewRenderer()

    // All requests (both queued and executing)
    private var requests: [RenderRequest] = []
    private var executingTaskCount: Int = 0

    private let urlCache: URLCache

    private let gutenbergCSS: String
    private let gutenbergCSSHash: String

    private class RenderRequest {
        let diskCacheKey: String
        let html: String
        let viewportWidth: Int
        var continuations: [UUID: CheckedContinuation<UIImage, Error>] = [:]
        var task: Task<Void, Never>?

        init(diskCacheKey: String, html: String, viewportWidth: Int) {
            self.diskCacheKey = diskCacheKey
            self.html = html
            self.viewportWidth = viewportWidth
        }
    }

    // MARK: - Initialization

    private init() {
        let css = Self.loadGutenbergCSS() ?? ""
        self.gutenbergCSS = css
        assert(!css.isEmpty, "Failed to load Gutenberg CSS from bundle. Previews will not render correctly.")

        // Precompute CSS hash for cache key generation
        self.gutenbergCSSHash = css.sha256

        let cacheDirectory = URL.cachesDirectory.appendingPathComponent("gbk-html-preview-cache", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        } catch {
            assertionFailure("failed to create cache directory: \(error)")
        }

        // The previews often have graphics included and are non opaque. The
        // most efficient format for it on iOS is HEIF.
        self.urlCache = URLCache(
            memoryCapacity: 0, // Disable memory cache (we use NSCache for thumbnails)
            diskCapacity: 16 * 1024 * 1024, // 16 MB
            directory: cacheDirectory
        )
    }

    /// Loads the Gutenberg CSS from the bundled assets
    private static func loadGutenbergCSS() -> String? {
        guard let assetsURL = Bundle.module.url(forResource: "Gutenberg", withExtension: nil) else {
            assertionFailure("Gutenberg resource not found in bundle")
            return nil
        }

        let assetsDirectory = assetsURL.appendingPathComponent("assets")
        guard let files = try? FileManager.default.contentsOfDirectory(at: assetsDirectory, includingPropertiesForKeys: nil),
              let cssURL = files.first(where: { $0.lastPathComponent.hasPrefix("index-") && $0.lastPathComponent.hasSuffix(".css") }),
              let css = try? String(contentsOf: cssURL, encoding: .utf8) else {
            assertionFailure("Failed to load Gutenberg CSS from bundle")
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
        let diskCacheKey = makeDiskCacheKey(html: html, viewportWidth: viewportWidth, cssHash: gutenbergCSSHash)

        if let diskImage = loadImageFromCache(forKey: diskCacheKey) {
            return diskImage
        }

        let uuid = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Check if this content is already queued or executing (deduplication)
                if let existingRequest = requests.first(where: { $0.diskCacheKey == diskCacheKey }) {
                    existingRequest.continuations[uuid] = continuation
                    return
                }
                let request = RenderRequest(
                    diskCacheKey: diskCacheKey,
                    html: html,
                    viewportWidth: viewportWidth,
                )
                request.continuations[uuid] = continuation
                requests.append(request)
                performPendingTasksIfNeeded()
            }
        } onCancel: {
            Task {
                await cancelRender(forKey: diskCacheKey, uuid: uuid)
            }
        }
    }

    /// Cancels a specific continuation for a render request
    /// - Parameters:
    ///   - key: The disk cache key identifying the request
    ///   - uuid: The unique identifier for the continuation to cancel
    private func cancelRender(forKey key: String, uuid: UUID) {
        guard let request = requests.first(where: { $0.diskCacheKey == key }) else {
            return
        }
        // Remove and resume the specific continuation with cancellation error
        if let continuation = request.continuations.removeValue(forKey: uuid) {
            continuation.resume(throwing: CancellationError())
        }
        // If no continuations left, cancel the task and remove the request
        if request.continuations.isEmpty {
            request.task?.cancel()
            removeRequest(request)
            performPendingTasksIfNeeded()
        }
    }

    // MARK: - URLCache

    /// Clears the disk cache
    public func clearCache() async {
        urlCache.removeAllCachedResponses()
    }

    /// Load image from URLCache
    private func loadImageFromCache(forKey key: String) -> UIImage? {
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

    private func perform(_ request: RenderRequest) {
        executingTaskCount += 1
        request.task = Task {
            do {
                let fullHTML = makeHTML(
                    content: request.html,
                    viewportWidth: request.viewportWidth,
                    css: gutenbergCSS
                )

                let image = try await htmlRenderer.render(
                    html: fullHTML,
                    viewportWidth: request.viewportWidth
                )

                saveImageToCache(image, forKey: request.diskCacheKey)

                for continuation in request.continuations.values {
                    continuation.resume(returning: image)
                }
            } catch {
                for continuation in request.continuations.values {
                    continuation.resume(throwing: error)
                }
            }
            removeRequest(request)
            performPendingTasksIfNeeded()
        }
    }

    private func removeRequest(_ request: RenderRequest) {
        if request.task != nil {
            executingTaskCount -= 1
            request.task = nil
        }
        requests.removeAll { $0 === request }
    }

    private func performPendingTasksIfNeeded() {
        while executingTaskCount < maxConcurrentRenders,
              let request = requests.first(where: { $0.task == nil }) {
            perform(request)
        }
    }
}

// MARK: - Private Helper Functions

private func makeDiskCacheKey(html: String, viewportWidth: Int, cssHash: String) -> String {
    "\(html)-\(viewportWidth)-\(cssHash)".sha256
}

private func makeHTML(content: String, viewportWidth: Int, css: String) -> String {
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
    <body>
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

private extension String {
    /// Creates a SHA256 hash of the string
    var sha256: String {
        let data = Data(self.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

