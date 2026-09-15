import Foundation
import Testing

@testable import GutenbergKit

#if canImport(UIKit)
import UIKit

/// Covers what the editor does with its in-flight dependency fetch as it leaves
/// the screen.
///
/// The fetch has exactly one starting point — the "no dependencies" branch of
/// `viewDidLoad` — and nothing restarts it, so cancelling it strands the editor
/// on its error screen for good. `viewDidDisappear` is not a teardown signal: it
/// fires whenever the editor is merely covered, which is what presenting a media
/// picker over a still-loading editor does.
@Suite("EditorViewController dependency fetch lifecycle")
struct EditorViewControllerLifecycleTests: MakesTestFixtures {
    static let testSiteURL = URL(string: "https://test.example.com")!
    static let testApiRoot = URL(string: "https://test.example.com/wp-json/wp/v2")!

    @MainActor
    @Test("covering the editor leaves the dependency fetch running")
    func coveringTheEditorDoesNotCancelTheDependencyFetch() async throws {
        let session = ParkedURLSession()
        let editor = makeEditor(session: session)
        defer { session.release() }

        _ = editor.view  // triggers `viewDidLoad`, which starts the fetch
        try await session.waitUntilStarted()

        // Stands in for a modal presented over the editor. UIKit sends this pair
        // for any covering presentation, not just for teardown.
        editor.viewWillDisappear(false)
        editor.viewDidDisappear(false)

        let cancelled = await session.waitUntilCancelled(timeout: .milliseconds(500))
        #expect(!cancelled)
    }

    /// The invariant that makes leaving the fetch running safe, and that rules
    /// `deinit` out as a place to cancel it from: the task's `self?.prepareEditor()`
    /// holds a strong `self` for the duration of the call, so a released editor
    /// outlives the fetch and is freed the moment it finishes.
    @MainActor
    @Test("the in-flight fetch keeps the editor alive until it finishes")
    func theInFlightFetchKeepsTheEditorAlive() async throws {
        let session = ParkedURLSession()
        var editor: EditorViewController? = makeEditor(session: session)
        weak let releasedEditor = editor

        _ = editor?.view
        try await session.waitUntilStarted()

        editor = nil
        try await Task.sleep(for: .milliseconds(250))
        #expect(releasedEditor != nil, "the fetch should hold the editor alive")

        session.release()
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)
        while releasedEditor != nil && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(releasedEditor == nil, "the editor should be freed once the fetch ends")
    }

    /// An editor whose every network call lands in `session`, on a site whose
    /// `siteId` (the host) no earlier run can have cached, so the fetch is
    /// guaranteed to reach the network rather than being served from disk.
    @MainActor
    private func makeEditor(session: ParkedURLSession) -> EditorViewController {
        let configuration = makeConfiguration(
            siteURL: URL(string: "https://\(UUID().uuidString).example.invalid")!
        )
        return EditorViewController(
            configuration: configuration,
            httpClient: EditorHTTPClient(urlSession: session, authHeader: configuration.authHeader)
        )
    }
}

/// A `URLSessionProtocol` whose requests never finish until the test lets them,
/// so a dependency fetch started against it stays in flight for as long as it
/// needs to, and records whether the surrounding task was cancelled.
private final class ParkedURLSession: URLSessionProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private var cancelled = false
    private var released = false

    private var isStarted: Bool { lock.withLock { started } }
    private var isCancelled: Bool { lock.withLock { cancelled } }
    private var isReleased: Bool { lock.withLock { released } }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await park()
    }

    func download(for request: URLRequest, delegate: (any URLSessionTaskDelegate)?) async throws -> (URL, URLResponse) {
        try await park()
    }

    /// Lets every parked request fail, so the fetch — and the task running it —
    /// finishes. Always call this: a request left parked keeps its editor alive
    /// for the rest of the run.
    func release() {
        lock.withLock { released = true }
    }

    /// Suspends until `release()` or until the calling task is cancelled.
    private func park<T>() async throws -> T {
        lock.withLock { started = true }
        while !isReleased {
            do {
                try await Task.sleep(for: .milliseconds(20))
            } catch {
                lock.withLock { cancelled = true }
                throw URLError(.cancelled)
            }
        }
        throw URLError(.networkConnectionLost)
    }

    func waitUntilStarted(timeout: Duration = .seconds(10)) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if isStarted { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw ParkedURLSessionTimeout.requestNeverStarted
    }

    func waitUntilCancelled(timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if isCancelled { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return isCancelled
    }
}

private enum ParkedURLSessionTimeout: Error {
    case requestNeverStarted
}

#endif
