import Foundation
import Testing

@testable import GutenbergKit

#if canImport(UIKit)
import UIKit

/// What happens to an in-flight dependency fetch when its editor is covered or
/// released. Nothing restarts the fetch, so the editor never recovers from a cancel.
@Suite("EditorViewController dependency fetch lifecycle")
struct EditorViewControllerLifecycleTests: MakesTestFixtures {
    static let testSiteURL = URL(string: "https://test.example.com")!
    static let testApiRoot = URL(string: "https://test.example.com/wp-json/wp/v2")!

    @MainActor
    @Test("covering the editor leaves the dependency fetch running")
    func coveringTheEditorDoesNotCancelTheDependencyFetch() async throws {
        let session = ParkedURLSession()
        let configuration = makeIsolatedConfiguration()
        defer { removeStorage(for: configuration) }
        defer { session.release() }
        let editor = makeEditor(configuration: configuration, session: session)

        _ = editor.view  // triggers `viewDidLoad`, which starts the fetch
        try await session.waitUntilStarted()

        // The editor appears, then a full-screen modal or a push covers it.
        editor.beginAppearanceTransition(true, animated: false)
        editor.endAppearanceTransition()
        editor.beginAppearanceTransition(false, animated: false)
        editor.endAppearanceTransition()

        let cancelled = await session.waitUntilCancelled(timeout: .milliseconds(500))
        #expect(!cancelled)
    }

    /// Why `deinit` can't cancel the fetch: `await self?.prepareEditor()` keeps the
    /// editor alive until the load finishes, so `deinit` only runs once it's over.
    @MainActor
    @Test("the in-flight fetch keeps the editor alive until it finishes")
    func theInFlightFetchKeepsTheEditorAlive() async throws {
        let session = ParkedURLSession()
        let configuration = makeIsolatedConfiguration()
        defer { removeStorage(for: configuration) }
        // Safety net if a throw skips the `release()` below; calling it twice is fine.
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
    /// Pair every call with `removeStorage(for:)`: nothing else deletes the site's files.
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

    /// Deletes what the editor wrote for this site. `EditorViewController` can't be
    /// pointed at a temporary directory the way `MakesTestFixtures.makeService` can.
    private func removeStorage(for configuration: EditorConfiguration) {
        try? FileManager.default.removeItem(at: Paths.storageRoot(for: configuration))
        try? FileManager.default.removeItem(at: Paths.cacheRoot(for: configuration))
    }
}

/// A `URLSessionProtocol` whose requests hang until `release()`, so a fetch stays in
/// flight for as long as the test needs. Records whether any request was cancelled.
///
/// Also lets a test load the editor's view, which starts the dependency fetch, without
/// the editor then loading a page over whatever the test put in its WebView.
final class ParkedURLSession: URLSessionProtocol, @unchecked Sendable {
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

    /// Makes every parked request fail, so the fetch ends. Always call it: a request
    /// left parked keeps its editor alive for the rest of the run.
    func release() {
        lock.withLock { released = true }
    }

    /// Suspends until `release()` or until the calling task is cancelled.
    /// `Never` because every exit throws, so it fits both methods' return types.
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

enum ParkedURLSessionTimeout: Error {
    case requestNeverStarted
}

#endif
