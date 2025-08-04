import WebKit

class EditorFileSchemeHandler: NSObject, WKURLSchemeHandler {
    nonisolated static let scheme = "gbk-file"

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        Task {
            do {
                let fileManager = EditorFileManager.shared
                let (response, data) = try await fileManager.getResponse(for: url)
                
                // Send response and data
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch {
                urlSchemeTask.didFailWithError(error)
            }
        }
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Nothing to do here for simple file serving
    }
}
