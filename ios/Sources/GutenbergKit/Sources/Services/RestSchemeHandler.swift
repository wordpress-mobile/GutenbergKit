import Foundation
import WebKit

/// Serves the editor's REST API traffic from ``RestRelay`` over the
/// ``RestRelay/scheme`` URL scheme.
///
/// The handler is only the transport seam: it turns a `WKURLSchemeTask` into a
/// `URLRequest`, hands it to the relay, and delivers the relay's answer back.
/// Everything about *what* is forwarded lives in ``RestRelay``, which needs no
/// WebView to exercise.
@MainActor
final class RestSchemeHandler: NSObject, WKURLSchemeHandler {

    private let relay: RestRelay

    /// The in-flight request per scheme task. A task is removed as it is either
    /// answered or stopped, so the entry doubles as the record of whether the
    /// task is still ours to message.
    private var activeTasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(relay: RestRelay) {
        self.relay = relay
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let request = urlSchemeTask.request
        guard let url = request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        let key = ObjectIdentifier(urlSchemeTask)
        let relay = self.relay

        activeTasks[key] = Task { [weak self] in
            let response = await relay.response(for: request)

            // WebKit raises an Objective-C exception if a stopped task is
            // messaged, and `stop(_:)` removes the entry before this resumes
            // (both run on the main actor, so neither can interleave with the
            // other's bookkeeping). No entry means the task is no longer ours.
            guard let self, self.activeTasks.removeValue(forKey: key) != nil else {
                return
            }

            guard let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: response.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers
            ) else {
                urlSchemeTask.didFailWithError(URLError(.badServerResponse))
                return
            }

            urlSchemeTask.didReceive(httpResponse)
            if !response.body.isEmpty {
                urlSchemeTask.didReceive(response.body)
            }
            urlSchemeTask.didFinish()
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        activeTasks.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
    }
}
