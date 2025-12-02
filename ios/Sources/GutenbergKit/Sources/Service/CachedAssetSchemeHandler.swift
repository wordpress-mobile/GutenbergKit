import Foundation
import WebKit

class CachedAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    nonisolated static let cachedURLSchemePrefix = "gbk-cache-"
    nonisolated static let supportedURLSchemes = ["gbk-cache-http", "gbk-cache-https"]

    nonisolated static func originalHTTPURL(from url: URL) -> URL? {
        guard let scheme = url.scheme, supportedURLSchemes.contains(scheme) else { return nil }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return nil
        }

        components.scheme = String(scheme.suffix(from: scheme.index(scheme.startIndex, offsetBy: cachedURLSchemePrefix.count)))
        return components.url
    }

    nonisolated static func cachedURL(forWebLink link: String) -> String? {
        if link.starts(with: "http://") || link.starts(with: "https://") {
            return cachedURLSchemePrefix + link
        }
        return nil
    }

    let service: EditorService

    init(service: EditorService) {
        self.service = service
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        Task {
            do {
                let (response, content) = try await service.getCachedAsset(from: url)
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(content)
                urlSchemeTask.didFinish()
            } catch {
                urlSchemeTask.didFailWithError(error)
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        // No-op: since we're reading from disk synchronously, there's nothing to cancel
    }
}

