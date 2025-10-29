import UIKit
import WebKit

/// Loads pattern preview images from the WebView bridge
@MainActor
final class PatternPreviewLoader {
    static let shared = PatternPreviewLoader()

    private var webView: WKWebView?
    private var cache: [String: UIImage] = [:]

    private init() {}

    /// Sets the WebView to use for loading previews
    func configure(webView: WKWebView) {
        self.webView = webView
    }

    /// Loads a preview image for the given pattern
    func loadPreview(for pattern: PatternType) async throws -> UIImage {
        // Check cache first
        if let cachedImage = cache[pattern.name] {
            return cachedImage
        }

        guard let webView else {
            throw PreviewError.webViewNotConfigured
        }

        // Use evaluateJavaScript with a polling approach since callAsyncJavaScript
        // with .page content world returns nil, and .defaultClient doesn't have access
        // to window.blockInserter
        return try await withCheckedThrowingContinuation { continuation in
            let requestId = UUID().uuidString
            let script = """
            (function() {
                window.blockInserter.generatePatternPreview('\(pattern.name.escapedForJavaScript())')
                    .then(result => {
                        window['__preview_\(requestId)'] = { success: true, data: result };
                    })
                    .catch(error => {
                        window['__preview_\(requestId)'] = { success: false, error: error.toString() };
                    });
            })();
            """

            webView.evaluateJavaScript(script) { _, error in
                if let error = error {
                    continuation.resume(throwing: PreviewError.javascriptError(error))
                    return
                }

                // Poll for the result
                var attempts = 0
                func checkResult() {
                    webView.evaluateJavaScript("window['__preview_\(requestId)']") { result, error in
                        if let error = error {
                            continuation.resume(throwing: PreviewError.javascriptError(error))
                            return
                        }

                        guard let resultDict = result as? [String: Any] else {
                            attempts += 1
                            if attempts < 50 { // 5 seconds max (50 * 100ms)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    checkResult()
                                }
                            } else {
                                continuation.resume(throwing: PreviewError.javascriptReturnedNull(patternName: pattern.name))
                            }
                            return
                        }

                        // Clean up
                        webView.evaluateJavaScript("delete window['__preview_\(requestId)']") { _, _ in }

                        guard let success = resultDict["success"] as? Bool, success else {
                            let errorMsg = resultDict["error"] as? String ?? "Unknown error"
                            print("JavaScript preview generation error: \(errorMsg)")
                            continuation.resume(throwing: PreviewError.javascriptReturnedNull(patternName: pattern.name))
                            return
                        }

                        guard let dataURL = resultDict["data"] as? String else {
                            continuation.resume(throwing: PreviewError.noDataURL)
                            return
                        }

                        guard let image = self.decodeDataURL(dataURL) else {
                            continuation.resume(throwing: PreviewError.invalidDataURL)
                            return
                        }

                        self.cache[pattern.name] = image
                        continuation.resume(returning: image)
                    }
                }

                // Start checking after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    checkResult()
                }
            }
        }
    }

    /// Decodes a base64 data URL to a UIImage
    private func decodeDataURL(_ dataURL: String) -> UIImage? {
        // Data URL format: data:image/png;base64,iVBORw0KGgo...
        guard let base64String = dataURL.components(separatedBy: ",").last,
              let imageData = Data(base64Encoded: base64String) else {
            return nil
        }

        return UIImage(data: imageData)
    }

    enum PreviewError: Error, LocalizedError {
        case webViewNotConfigured
        case noDataURL
        case invalidDataURL
        case javascriptReturnedNull(patternName: String)
        case unexpectedReturnType(value: String)
        case javascriptError(Error)

        var errorDescription: String? {
            switch self {
            case .webViewNotConfigured:
                return "WebView not configured for preview loading"
            case .noDataURL:
                return "No data URL returned from JavaScript"
            case .invalidDataURL:
                return "Invalid data URL format"
            case .javascriptReturnedNull(let patternName):
                return "JavaScript returned null for pattern '\(patternName)' - pattern may not exist or preview generation failed"
            case .unexpectedReturnType(let value):
                return "Unexpected return type from JavaScript: \(value)"
            case .javascriptError(let error):
                return "JavaScript error: \(error.localizedDescription)"
            }
        }
    }
}

private extension String {
    /// Escapes a string for safe use in JavaScript
    func escapedForJavaScript() -> String {
        return self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
