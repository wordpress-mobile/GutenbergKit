import Foundation
import WebKit

/// Handles `gbk-media-file://` URL scheme requests in WKWebView.
/// Serves media files from MediaFileManager with appropriate CORS headers.
final class MediaFileSchemeHandler: NSObject, WKURLSchemeHandler {
    /// The custom URL scheme handled by this class
    nonisolated static let scheme = "gbk-media-file"

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        Task {
            do {
                let (response, data) = try await getResponse(for: url)
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch {
                urlSchemeTask.didFailWithError(error)
            }
        }
    }

    private func getResponse(for url: URL) async throws -> (URLResponse, Data) {
        let data = try await MediaFileManager.shared.getData(for: url)

        let headers = [
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
            "Access-Control-Allow-Headers": "*",
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
        // Nothing to do here for simple file serving
    }
}
