import Foundation
import WebKit

/// Serves ``RestRelay`` to the editor's page over a `gbk-rest:` URL scheme.
///
/// The page's `fetch` wrapper (`src/utils/fetch-relay.js`) rewrites a request for
/// another origin to `gbk-rest://relay/fetch?url=<url>`. This hands it to the
/// relay and answers with what the server said.
@MainActor
final class RestRelaySchemeHandler: NSObject, WKURLSchemeHandler {
    nonisolated static let scheme = "gbk-rest"

    /// The URL the page sends each request to, with that request's URL in the `url`
    /// query parameter.
    nonisolated static let endpoint = "\(scheme)://relay\(RestRelay.route)"

    /// The relay requests go through. The editor replaces it when its page loads, so it
    /// relays for the configuration the page was given.
    var relay: RestRelay

    private var active = ActiveSchemeTasks()

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
    ///
    /// A failure to reach the site fails the page's request as a network failure would.
    /// See ``RestRelay/handle(_:)``.
    func start(_ task: any WKURLSchemeTask) {
        let request = task.request
        let relay = relay
        active.start(task) { key in
            Task { [weak self] in
                await self?.answer(key, relaying: request, through: relay)
            }
        }
    }

    /// `webView(_:stop:)` without the web view, for tests. Cancels the request to the site.
    func stop(_ task: any WKURLSchemeTask) {
        active.stop(task)
    }

    var activeRequestCount: Int { active.count }

    /// Cancels the work answering every request, as a teardown would. Each request
    /// still gets an answer.
    func cancelAll() {
        active.cancelAll()
    }

    /// Answers the task under `key` with the relay's response, sending each chunk of the
    /// body as it arrives. WebKit passes each chunk to the page's `fetch` straight away,
    /// with Lockdown Mode on or off (measured in the iOS 27.0 Simulator).
    ///
    /// Returning early drops the body, which cancels the request to the server.
    private func answer(_ key: ActiveSchemeTasks.Key, relaying request: URLRequest, through relay: RestRelay) async {
        do {
            let response = try await relay.handle(request)
            guard let task = active.respond(key, status: response.status, headers: response.headers) else { return }
            for try await chunk in response.body {
                // WebKit stopped the task while this chunk was on its way. Sending it now
                // would raise an exception.
                guard active.task(for: key) != nil else { return }
                task.didReceive(chunk)
            }
            // Cancelling this task ends the body early without an error. Fail the
            // page's request rather than finish it with part of the body.
            try Task.checkCancellation()
            active.finish(key)
        } catch {
            active.fail(key, with: error)
        }
    }
}
