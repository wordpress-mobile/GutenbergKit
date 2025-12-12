import Foundation
import WebKit

/// Handles `gbk-bundle://` URL scheme requests in WKWebView.
/// Serves bundled editor assets from the app bundle, allowing the WebView
/// to load local assets while using a remote site URL as the document origin.
final class BundledAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    /// The custom URL scheme handled by this class
    nonisolated static let scheme = "gbk-bundle"

    /// MIME types for common file extensions
    private static let mimeTypes: [String: String] = [
        "html": "text/html",
        "js": "application/javascript",
        "css": "text/css",
        "json": "application/json",
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "gif": "image/gif",
        "svg": "image/svg+xml",
        "woff": "font/woff",
        "woff2": "font/woff2",
        "ttf": "font/ttf",
        "map": "application/json"
    ]

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        do {
            let (response, data) = try getResponse(for: url)
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    private func getResponse(for url: URL) throws -> (URLResponse, Data) {
        // Extract the path from gbk-bundle:///path/to/file.js
        // The path starts with / so we need to handle that
        var path = url.path
        if path.hasPrefix("/") {
            path = String(path.dropFirst())
        }

        // Handle paths like "assets/file.js" or just "file.js"
        let resourcePath: String
        let subdirectory: String

        if path.contains("/") {
            // Split into directory and filename
            let components = path.components(separatedBy: "/")
            let filename = components.last ?? path
            let directory = components.dropLast().joined(separator: "/")
            resourcePath = (filename as NSString).deletingPathExtension
            subdirectory = "Gutenberg/\(directory)"
        } else {
            resourcePath = (path as NSString).deletingPathExtension
            subdirectory = "Gutenberg"
        }

        let fileExtension = (path as NSString).pathExtension

        guard let fileURL = Bundle.module.url(
            forResource: resourcePath,
            withExtension: fileExtension,
            subdirectory: subdirectory
        ) else {
            throw URLError(.fileDoesNotExist)
        }

        let data = try Data(contentsOf: fileURL)
        let mimeType = Self.mimeTypes[fileExtension.lowercased()] ?? "application/octet-stream"

        let headers = [
            "Content-Type": mimeType,
            "Content-Length": String(data.count),
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "no-cache"
        ]

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            throw URLError(.unknown)
        }

        return (response, data)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Nothing to cancel for synchronous file reads
    }
}
