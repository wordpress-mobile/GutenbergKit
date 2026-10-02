import Foundation
import WebKit

/// Serves ``RestRelay`` to the editor's page over a `gbk-rest:` URL scheme.
///
/// The page's `fetch` wrapper (`src/utils/fetch-relay.js`) rewrites a request for
/// the site's REST API to `gbk-rest://relay/proxy/<path>`, and this hands it to
/// the relay and answers with what the site said.
@MainActor
final class RestRelaySchemeHandler: NSObject, WKURLSchemeHandler {
    nonisolated static let scheme = "gbk-rest"

    /// The URL the page appends an upstream path to, slash-terminated.
    nonisolated static let baseURL = "\(scheme)://relay\(RestRelay.route)/"

    private let relay: RestRelay

    /// Every request WebKit has started and not stopped, held strongly: a finished
    /// task's identity can be reused by the next one, so tracking tasks by identifier
    /// alone answers the wrong request.
    private var active: [ObjectIdentifier: ActiveRequest] = [:]

    private struct ActiveRequest {
        let task: any WKURLSchemeTask
        var work: Task<Void, Never>?
    }

    init(relay: RestRelay) {
        self.relay = relay
        super.init()
    }

    // MARK: - WKURLSchemeHandler

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        start(urlSchemeTask)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        stop(urlSchemeTask)
    }

    /// `webView(_:start:)` without the web view, for tests.
    func start(_ task: any WKURLSchemeTask) {
        let key = ObjectIdentifier(task)
        let request = task.request
        let relay = relay
        active[key] = ActiveRequest(task: task, work: nil)
        active[key]?.work = Task { [weak self] in
            let response = await relay.handle(request)
            self?.reply(to: key, with: response)
        }
    }

    /// `webView(_:stop:)` without the web view, for tests.
    ///
    /// WebKit stops a task when the page aborts its `fetch` or goes away. Cancelling
    /// the work cancels the request to the site, and dropping the task keeps `reply`
    /// from answering it: answering a stopped task raises an Objective-C exception.
    func stop(_ task: any WKURLSchemeTask) {
        active.removeValue(forKey: ObjectIdentifier(task))?.work?.cancel()
    }

    var activeRequestCount: Int { active.count }

    private func reply(to key: ObjectIdentifier, with response: SchemeResponse) {
        guard let request = active.removeValue(forKey: key) else {
            return  // Stopped: WebKit raises if a stopped task is answered.
        }
        let task = request.task
        guard let url = task.request.url,
              let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: response.status,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers
              ) else {
            task.didFailWithError(URLError(.badServerResponse))
            return
        }
        task.didReceive(httpResponse)
        if !response.body.isEmpty {
            task.didReceive(response.body)
        }
        task.didFinish()
    }
}
