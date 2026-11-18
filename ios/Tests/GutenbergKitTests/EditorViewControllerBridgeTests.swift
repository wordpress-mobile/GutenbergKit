import Foundation
import Testing

@testable import GutenbergKit

#if canImport(UIKit)
import UIKit

/// How the editor's bridge handles the messages a page posts to it, sent from a real
/// web view. The dependency fetch is parked, so the editor never replaces the test page.
@Suite("EditorViewController bridge messages")
struct EditorViewControllerBridgeTests: MakesTestFixtures {
    static let testSiteURL = URL(string: "https://test.example.com")!
    static let testApiRoot = URL(string: "https://test.example.com/wp-json/wp/v2")!

    @MainActor
    @Test("accepts messages from the main frame and ignores those from subframes")
    func acceptsOnlyMainFrameMessages() async throws {
        let session = ParkedURLSession()
        let configuration = makeIsolatedConfiguration()
        defer { removeStorage(for: configuration) }
        defer { session.release() }
        let spy = BridgeDelegateSpy()
        let editor = try await makeLoadedEditor(configuration: configuration, session: session, delegate: spy)

        let subframeReply = try await editor.webView.callAsyncJavaScript(
            Self.subframeScript,
            contentWorld: .page
        )
        #expect(subframeReply as? String == #"{"content":null}"#)

        let mainFrameReply = try await editor.webView.callAsyncJavaScript(
            """
            const handlers = window.webkit.messageHandlers;
            handlers.editorDelegate.postMessage({ message: 'onEditorHistoryChanged', body: { hasUndo: true, hasRedo: false } });
            return await handlers.requestLatestContent.postMessage(null);
            """,
            contentWorld: .page
        )
        #expect(mainFrameReply as? [String: String] == ["title": "Title", "content": "Content"])

        // The subframe posted first, so its message would have arrived before this one.
        try await waitUntil { !spy.historyStates.isEmpty }
        #expect(spy.historyStates == [[true, false]])
    }

    @MainActor
    @Test("drops a message it can't decode, and keeps handling the next", arguments: [
        "undefined",
        "null",
        "5",
        "{ hasUndo: new Date(), hasRedo: false }",
        "{ hasUndo: NaN, hasRedo: false }",
    ])
    func dropsUndecodableMessages(_ body: String) async throws {
        let session = ParkedURLSession()
        let configuration = makeIsolatedConfiguration()
        defer { removeStorage(for: configuration) }
        defer { session.release() }
        let spy = BridgeDelegateSpy()
        let editor = try await makeLoadedEditor(configuration: configuration, session: session, delegate: spy)

        _ = try await editor.webView.callAsyncJavaScript(
            """
            const delegate = window.webkit.messageHandlers.editorDelegate;
            delegate.postMessage({ message: 'onEditorHistoryChanged', body: \(body) });
            delegate.postMessage({ message: 'onEditorHistoryChanged', body: { hasUndo: true, hasRedo: true } });
            """,
            contentWorld: .page
        )

        try await waitUntil { !spy.historyStates.isEmpty }
        #expect(spy.historyStates == [[true, true]])
    }

    /// Posts a valid message from a sandboxed (null-origin) iframe, then reports the
    /// reply it got for the latest content.
    private static let subframeScript = #"""
        const frame = document.createElement('iframe');
        frame.sandbox = 'allow-scripts';
        frame.srcdoc = `<script>
            (async () => {
                const handlers = window.webkit.messageHandlers;
                handlers.editorDelegate.postMessage({ message: 'onEditorHistoryChanged', body: { hasUndo: true, hasRedo: true } });
                const content = await handlers.requestLatestContent.postMessage(null);
                parent.postMessage({ content: content ?? null }, '*');
            })();
        <\/script>`;
        const reply = new Promise((resolve) => {
            window.addEventListener('message', (event) => resolve(event.data), { once: true });
        });
        document.body.append(frame);
        return JSON.stringify(await reply);
        """#

    /// An editor showing a blank `file://` page, as the editor's own page is, with its
    /// bridge wired to `delegate`.
    @MainActor
    private func makeLoadedEditor(
        configuration: EditorConfiguration,
        session: ParkedURLSession,
        delegate: BridgeDelegateSpy
    ) async throws -> EditorViewController {
        let editor = EditorViewController(
            configuration: configuration,
            httpClient: EditorHTTPClient(configuration: configuration, urlSession: session)
        )
        editor.delegate = delegate
        _ = editor.view  // triggers `viewDidLoad`, which wires up the bridge

        let directory = URL.randomTemporaryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let page = directory.appending(component: "index.html")
        try Data("<!doctype html><title>Bridge</title><body></body>".utf8).write(to: page)
        editor.webView.loadFileURL(page, allowingReadAccessTo: directory)
        try await waitUntil { !editor.webView.isLoading && editor.webView.url?.lastPathComponent == "index.html" }
        return editor
    }

    /// A unique `siteId` per call, so no earlier run's cache can serve the fetch.
    /// Pair every call with `removeStorage(for:)`: nothing else deletes the site's files.
    private func makeIsolatedConfiguration() -> EditorConfiguration {
        makeConfiguration(
            siteURL: URL(string: "https://\(UUID().uuidString).example.invalid")!
        )
    }

    private func removeStorage(for configuration: EditorConfiguration) {
        try? FileManager.default.removeItem(at: Paths.storageRoot(for: configuration))
        try? FileManager.default.removeItem(at: Paths.cacheRoot(for: configuration))
    }
}

/// Records the history states the editor reports, and answers requests for the latest
/// content with a fixed title and content.
@MainActor
private final class BridgeDelegateSpy: EditorViewControllerDelegate {
    private(set) var historyStates: [[Bool]] = []

    func editor(_ viewController: EditorViewController, didUpdateHistoryState state: EditorState) {
        historyStates.append([state.hasUndo, state.hasRedo])
    }

    func editorDidRequestLatestContent(_ controller: EditorViewController) -> (title: String, content: String)? {
        ("Title", "Content")
    }

    func editorDidLoad(_ viewContoller: EditorViewController) {}
    func editor(_ viewContoller: EditorViewController, didDisplayInitialContent content: String) {}
    func editor(_ viewContoller: EditorViewController, didEncounterCriticalError error: Error) {}
    func editorDidBecomeUnavailable(_ viewController: EditorViewController) {}
    func editor(_ viewController: EditorViewController, didUpdateContentWithState state: EditorState) {}
    func editor(_ viewController: EditorViewController, didUpdateFeaturedImage mediaID: Int) {}
    func editor(_ viewController: EditorViewController, didLogException error: GutenbergJSException) {}
    func editor(_ viewController: EditorViewController, didRequestMediaFromSiteMediaLibrary config: OpenMediaLibraryAction) {}
    func editor(_ viewController: EditorViewController, didTriggerAutocompleter type: String) {}
    func editor(_ viewController: EditorViewController, didOpenModalDialog dialogType: String) {}
    func editor(_ viewController: EditorViewController, didCloseModalDialog dialogType: String) {}
    func editor(_ viewController: EditorViewController, didLogNetworkRequest request: RecordedNetworkRequest) {}
}

#endif
