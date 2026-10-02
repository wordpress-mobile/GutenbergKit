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

    /// The loader owns the fetch and reaches the editor only weakly, so a released
    /// editor is freed while its fetch is still parked — and the fetch keeps running.
    @MainActor
    @Test("releasing the editor mid-fetch frees it, and leaves the fetch running")
    func releasingTheEditorMidFetchFreesIt() async throws {
        let session = ParkedURLSession()
        let configuration = makeIsolatedConfiguration()
        defer { removeStorage(for: configuration) }
        defer { session.release() }
        var editor: EditorViewController? = makeEditor(configuration: configuration, session: session)
        weak let releasedEditor = editor

        _ = editor?.view  // triggers `viewDidLoad`, which starts the fetch
        try await session.waitUntilStarted()

        // Polled rather than checked once, so it doesn't depend on exactly when UIKit
        // lets go. The fetch stays parked throughout, so it can't be what lets go.
        editor = nil
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)
        while releasedEditor != nil && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(releasedEditor == nil, "the fetch should not hold the editor")

        let cancelled = await session.waitUntilCancelled(timeout: .milliseconds(250))
        #expect(!cancelled, "freeing the editor should not cancel the fetch")
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

#endif
