import Foundation
import Testing

@testable import GutenbergKit

#if canImport(UIKit)
import UIKit

/// Covers what the editor does with its in-flight dependency fetch as it leaves
/// the screen. Nothing restarts the fetch, so cancelling it is terminal.
@Suite("EditorViewController dependency fetch lifecycle")
struct EditorViewControllerLifecycleTests: MakesTestFixtures {
    static let testSiteURL = URL(string: "https://test.example.com")!
    static let testApiRoot = URL(string: "https://test.example.com/wp-json/wp/v2")!

    @MainActor
    @Test("covering the editor leaves the dependency fetch running")
    func coveringTheEditorDoesNotCancelTheDependencyFetch() async throws {
        let session = ParkedURLSession()
        let configuration = makeIsolatedConfiguration()
        // Before the release so it runs after it — `defer`s unwind in reverse.
        defer { removeStorage(for: configuration) }
        defer { session.release() }
        let editor = makeEditor(configuration: configuration, session: session)

        _ = editor.view  // triggers `viewDidLoad`, which starts the fetch
        try await session.waitUntilStarted()

        // Stands in for a full-screen modal or a push over the editor. The
        // "calling -viewWillDisappear: directly is not supported" warning is
        // expected: `beginAppearanceTransition` delivers nothing to a windowless,
        // parentless controller, so it would pass against the regression.
        editor.viewWillDisappear(false)
        editor.viewDidDisappear(false)

        let cancelled = await session.waitUntilCancelled(timeout: .milliseconds(500))
        #expect(!cancelled)
    }

    /// Why `deinit` is not a place to cancel from: `self?.prepareEditor()` holds a
    /// strong `self` for the call, so a released editor outlives its own fetch.
    @MainActor
    @Test("the in-flight fetch keeps the editor alive until it finishes")
    func theInFlightFetchKeepsTheEditorAlive() async throws {
        let session = ParkedURLSession()
        let configuration = makeIsolatedConfiguration()
        defer { removeStorage(for: configuration) }
        // The `release()` below is the test's trigger; this is the safety net for
        // the throwing calls before it. `release()` is idempotent.
        defer { session.release() }
        var editor: EditorViewController? = makeEditor(configuration: configuration, session: session)
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

    /// A unique `siteId` per call, so no earlier run's cache can serve the fetch.
    /// Pair every call with `removeStorage(for:)` — nothing else reclaims it.
    private func makeIsolatedConfiguration() -> EditorConfiguration {
        makeConfiguration(
            siteURL: URL(string: "https://\(UUID().uuidString).example.invalid")!
        )
    }

    /// An editor whose every network call lands in `session`.
    @MainActor
    private func makeEditor(
        configuration: EditorConfiguration,
        session: ParkedURLSession
    ) -> EditorViewController {
        EditorViewController(
            configuration: configuration,
            httpClient: EditorHTTPClient(urlSession: session, authHeader: configuration.authHeader)
        )
    }

    /// `EditorViewController` has no seam to redirect its storage roots the way
    /// `MakesTestFixtures.makeService` does, so the test cleans up behind itself.
    private func removeStorage(for configuration: EditorConfiguration) {
        try? FileManager.default.removeItem(at: Paths.storageRoot(for: configuration))
        try? FileManager.default.removeItem(at: Paths.cacheRoot(for: configuration))
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
    /// `Never` because every exit throws — it satisfies both return types.
    private func park() async throws -> Never {
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
