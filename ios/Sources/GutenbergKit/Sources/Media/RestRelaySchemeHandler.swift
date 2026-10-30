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

    /// The request header that carries an `XMLHttpRequest`'s `timeout`, in
    /// milliseconds. Never sent on.
    ///
    /// WebKit doesn't apply that timeout to a request a scheme handler answers:
    /// one that was never answered was still waiting long after it (iOS 27.0
    /// Simulator). A task failed with `URLError(.timedOut)` does make the page's
    /// request fire `timeout`, so the relay enforces it here.
    nonisolated static let timeoutHeader = "X-GBK-Relay-Timeout"

    /// The request header that names an `XMLHttpRequest` upload, so the page can tell
    /// which request each upload progress report is for. Never sent on.
    ///
    /// WebKit fires no upload `progress` events for a request a scheme handler answers,
    /// so the handler reports how much of the body has reached the server instead.
    nonisolated static let uploadHeader = "X-GBK-Relay-Upload"

    /// The page function each upload progress report calls.
    nonisolated static let uploadProgressFunction = "window.editor?.relayUploadProgress?.(id, sent, total)"

    /// How much of an upload's body has reached the server.
    struct UploadProgress: Equatable, Sendable {
        /// The upload's name, from ``uploadHeader``.
        let id: String
        let sent: Int64
        let total: Int64
    }

    /// The relay requests go through. The editor replaces it when its page loads, so it
    /// relays for the configuration the page was given.
    var relay: RestRelay

    private var active = ActiveSchemeTasks()

    /// The shortest time between two progress reports for one upload.
    private let uploadProgressInterval: Duration

    /// - Parameter uploadProgressInterval: The shortest time between two progress
    ///   reports for one upload. A browser fires upload `progress` about every 50 ms.
    init(relay: RestRelay, uploadProgressInterval: Duration = .milliseconds(50)) {
        self.relay = relay
        self.uploadProgressInterval = uploadProgressInterval
        super.init()
    }

    // MARK: - WKURLSchemeHandler

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        start(urlSchemeTask) { [weak webView] progress in
            webView?.callAsyncJavaScript(
                Self.uploadProgressFunction,
                arguments: ["id": progress.id, "sent": progress.sent, "total": progress.total],
                in: nil,
                in: .page
            )
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        stop(urlSchemeTask)
    }

    /// `webView(_:start:)` without the web view, for tests.
    ///
    /// A failure to reach the site fails the page's request as a network failure would.
    /// See ``RestRelay/handle(_:onUploadProgress:)``.
    ///
    /// - Parameter reportUploadProgress: Given how much of the body has reached the
    ///   server, when the request names an upload in ``uploadHeader``.
    func start(
        _ task: any WKURLSchemeTask,
        reportUploadProgress: (@MainActor @Sendable (UploadProgress) -> Void)? = nil
    ) {
        let request = task.request
        let relay = relay
        active.start(task) { key in
            let onUploadProgress = reportUploadProgress.flatMap {
                uploadProgress(of: request, for: key, reportingTo: $0)
            }
            return Task { [weak self] in
                await self?.answer(key, relaying: request, through: relay, onUploadProgress: onUploadProgress)
            }
        }
    }

    /// Reports the progress of the upload `request` names in ``uploadHeader``, at most
    /// once every ``uploadProgressInterval``, while the task under `key` is unanswered.
    /// `nil` when `request` names no upload.
    ///
    /// The report for the whole body is always sent: the page fires the upload's
    /// `load` and `loadend` on it, before the response arrives, as WebKit does for a
    /// request it sends itself.
    private func uploadProgress(
        of request: URLRequest,
        for key: ActiveSchemeTasks.Key,
        reportingTo report: @escaping @MainActor @Sendable (UploadProgress) -> Void
    ) -> (@Sendable (Int64, Int64) -> Void)? {
        guard let id = request.value(forHTTPHeaderField: Self.uploadHeader), !id.isEmpty else {
            return nil
        }
        let throttle = Throttle(interval: uploadProgressInterval)
        return { [weak self] sent, total in
            guard total > 0, sent >= total || throttle.allows() else { return }
            Task { @MainActor [weak self] in
                // The page stopped the request, or its response has arrived.
                guard self?.active.task(for: key) != nil else { return }
                report(UploadProgress(id: id, sent: sent, total: total))
            }
        }
    }

    /// Fails the task under `key` as timed out after the time its request asks for, if
    /// it is still unanswered. Cancels the request to the site.
    private func enforceTimeout(of request: URLRequest, for key: ActiveSchemeTasks.Key) -> Task<Void, Never>? {
        guard let value = request.value(forHTTPHeaderField: Self.timeoutHeader),
              let milliseconds = Int(value), milliseconds > 0 else {
            return nil
        }
        return Task { [weak self] in
            guard (try? await Task.sleep(for: .milliseconds(milliseconds))) != nil else { return }
            self?.active.abandon(key, failingWith: URLError(.timedOut))
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
    private func answer(
        _ key: ActiveSchemeTasks.Key,
        relaying request: URLRequest,
        through relay: RestRelay,
        onUploadProgress: (@Sendable (Int64, Int64) -> Void)?
    ) async {
        let timeout = enforceTimeout(of: request, for: key)
        defer { timeout?.cancel() }
        do {
            let response = try await relay.handle(request, onUploadProgress: onUploadProgress)
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

/// Lets through one call per interval.
///
/// `@unchecked Sendable`: the mutable state is guarded by `lock`.
private final class Throttle: @unchecked Sendable {
    private let interval: Duration
    private let lock = NSLock()
    private var last: ContinuousClock.Instant?

    init(interval: Duration) {
        self.interval = interval
    }

    /// Whether a call made now gets through: the first does, and then each one an
    /// interval or more after the last that got through.
    func allows() -> Bool {
        let now = ContinuousClock.now
        return lock.withLock {
            if let last, now - last < interval {
                return false
            }
            last = now
            return true
        }
    }
}
