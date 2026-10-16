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
                do {
                    let response = try await relay.handle(request)
                    self?.active.answer(key, with: response)
                } catch {
                    self?.active.fail(key, with: error)
                }
            }
        }
    }

    /// `webView(_:stop:)` without the web view, for tests. Cancels the request to the site.
    func stop(_ task: any WKURLSchemeTask) {
        active.stop(task)
    }

    var activeRequestCount: Int { active.count }
}
