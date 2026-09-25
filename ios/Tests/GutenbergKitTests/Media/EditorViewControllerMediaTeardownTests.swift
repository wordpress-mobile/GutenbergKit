import Foundation
import Testing

@testable import GutenbergKit

#if canImport(UIKit)
import WebKit

/// Pins that ``EditorViewController/stopMediaHandling()`` opens the ownership cycle a host
/// can form, and that a host which doesn't form one needs nothing.
///
/// The editor holds `mediaProcessor` strongly so an in-flight upload can't lose it
/// mid-request. The cost is that a host which holds the editor back closes a cycle ARC
/// cannot break — and `deinit`, which does this work on every other path, is exactly what
/// a cycle prevents. `stopMediaHandling()` is the way out, and it has to be the host's
/// call: not because UIKit can't report a teardown, but because it can't report whether
/// one is permanent. A host may re-present or re-attach the same editor, and the call is
/// terminal, so guessing wrong disables media in an editor that survived.
@Suite("EditorViewController media teardown")
struct EditorViewControllerMediaTeardownTests: MakesTestFixtures {
    static let testSiteURL = URL(string: "https://test.example.com")!
    static let testApiRoot = URL(string: "https://test.example.com/wp-json/wp/v2")!

    @MainActor
    @Test("stopMediaHandling frees the editor and the host processor that owns it")
    func stopMediaHandlingBreaksTheOwnershipCycle() async {
        weak var weakEditor: EditorViewController?
        weak var weakHost: EditorOwningProcessor?

        do {
            let host = EditorOwningProcessor(configuration: makeConfiguration())
            weakEditor = host.editor
            weakHost = host
            host.editor.stopMediaHandling()
        }

        await waitForRelease { weakHost == nil && weakEditor == nil }

        #expect(weakHost == nil, "host processor leaked — stopMediaHandling did not release it")
        #expect(weakEditor == nil, "EditorViewController leaked — cycle through mediaProcessor")
    }

    @MainActor
    @Test("a host that does not retain the editor is freed without stopMediaHandling")
    func standaloneProcessorIsFreed() async {
        weak var weakEditor: EditorViewController?

        do {
            let editor = EditorViewController(
                configuration: makeConfiguration(),
                mediaProcessor: StandaloneProcessor()
            )
            weakEditor = editor
        }

        await waitForRelease { weakEditor == nil }

        #expect(weakEditor == nil, "EditorViewController leaked — nothing here retains it")
    }

    // MARK: - Which handlers bring the server up

    /// The regression this pins: `startUploadServer()` reads "did the host supply a
    /// handler" twice — once before starting, once after the bind returns — and the two
    /// reads drifted. The first gained `mediaUploader`, the second kept checking the
    /// processor alone, so an uploader-only host bound a listener and then immediately
    /// stopped it. `uploadServer` stayed nil, the page was advertised `nativeUploadPort:
    /// nil`, and `api-fetch.js` fell through to the plain WebView path — so the host's
    /// `upload(_:)` was never called for any file, with nothing logged.
    ///
    /// Android pins the same gate (`GutenbergViewUploadServerTest`, "the upload server
    /// starts for an uploader with no processor"); iOS had no equivalent, which is why the
    /// drift survived three commits with a green suite.
    @MainActor
    @Test(
        "the upload server starts for whichever handler the host supplied",
        .enabled(if: canBindUploadServer),
        arguments: [
            ("uploader only", false, true),
            ("processor only", true, false),
            ("both", true, true)
        ]
    )
    func uploadServerStartsForAnyHandler(_ label: String, processor: Bool, uploader: Bool) async {
        let editor = EditorViewController(
            configuration: makeConfiguration(),
            mediaProcessor: processor ? StandaloneProcessor() : nil,
            mediaUploader: uploader ? InertUploader() : nil
        )
        defer { editor.stopMediaHandling() }

        await editor.startUploadServer()

        #expect(editor.uploadServer != nil, "\(label): no upload server, so the host's media handling never runs")
    }

    // MARK: - Coming back from the background

    /// The failure this file's sibling PR is named for. Once the device can idle-sleep, the
    /// system reclaims a suspended app's listening socket and reports nothing, so the editor
    /// returns advertising a port that refuses connections, and every upload in that session
    /// fails. Stopping the server behind the editor's back leaves exactly that state.
    @MainActor
    @Test("an upload server whose port stopped answering is replaced", .enabled(if: canBindUploadServer))
    func restartsAnUnreachableUploadServer() async throws {
        let editor = EditorViewController(
            configuration: makeConfiguration(),
            mediaProcessor: StandaloneProcessor()
        )
        defer { editor.stopMediaHandling() }
        await editor.startUploadServer()

        guard let original = editor.uploadServer else {
            Issue.record("no upload server to begin with")
            return
        }
        original.stop()
        try await waitUntilSilent(original)

        await editor.restartUploadServerIfUnreachable()

        guard let restarted = editor.uploadServer else {
            Issue.record("the editor was left without a server, so uploads fall back to the WebView path")
            return
        }
        #expect(restarted !== original, "kept the server whose port had stopped answering")
        #expect(await restarted.isAnswering(), "the replacement server does not answer either")
    }

    /// The other half: a check that runs on every foreground must not churn the port, which
    /// would mean re-advertising it to the page for no reason.
    @MainActor
    @Test("an upload server that still answers is left alone", .enabled(if: canBindUploadServer))
    func leavesAnAnsweringUploadServerAlone() async {
        let editor = EditorViewController(
            configuration: makeConfiguration(),
            mediaProcessor: StandaloneProcessor()
        )
        defer { editor.stopMediaHandling() }
        await editor.startUploadServer()
        let original = editor.uploadServer

        await editor.restartUploadServerIfUnreachable()

        #expect(editor.uploadServer === original, "replaced a server that was answering")
    }

    /// What the page goes through between losing the socket and the restart, run in the
    /// editor's own `WKWebView` from a `file://` page, which is where the editor loads from.
    ///
    /// An upload sent in that window fails, reaching nothing; the window closes promptly; and
    /// the next upload after the restart lands on the new port. The request is the one
    /// `nativeMediaUploadMiddleware` sends, built from `window.GBKit`. The middleware's own
    /// part is covered in JS: that it reads the endpoint on every request
    /// (`api-fetch-upload-middleware.test.js`) from the live `window.GBKit`
    /// (`bridge.test.js`), and that it neither retries a rejected `fetch` nor falls back to
    /// the WebView's own upload.
    @MainActor
    @Test(
        "an upload sent before the restart fails, and the next one lands on the new port",
        .enabled(if: canBindUploadServer)
    )
    func uploadFailsUntilTheRestartThenLands() async throws {
        let uploader = CountingUploader()
        let editor = EditorViewController(configuration: makeConfiguration(), mediaUploader: uploader)
        defer { editor.stopMediaHandling() }
        await editor.startUploadServer()
        let original = try #require(editor.uploadServer)

        try await loadFilePage(in: editor.webView)
        // What the injected user script sets at document start.
        try await editor.webView.callAsyncJavaScript(
            "window.GBKit = { nativeUploadPort: port, nativeUploadToken: token };",
            arguments: ["port": Int(original.port), "token": original.token],
            contentWorld: .page
        )

        let beforeLoss = try await sendNativeUpload(from: editor.webView)
        #expect(beforeLoss.status == 201, "the upload never worked, so the rest proves nothing: \(beforeLoss)")

        original.stop()
        try await waitUntilSilent(original)

        let duringLoss = try await sendNativeUpload(from: editor.webView)
        #expect(duringLoss.port == Int(original.port))
        #expect(duringLoss.error != nil, "an upload to the dead port didn't fail: \(duringLoss)")
        // Failing is the point; failing *promptly* rules out WebKit holding the request open
        // and presenting a hang instead.
        #expect(duringLoss.milliseconds < 1000, "the upload to the dead port hung: \(duringLoss)")
        #expect(uploader.uploads == 1, "the upload sent to the dead port reached the uploader")

        // Until this returns, the page holds the dead port and every upload fails like the
        // one above, so its duration is how long that lasts after the app comes back.
        let restartDuration = await ContinuousClock().measure {
            await editor.restartUploadServerIfUnreachable()
        }
        #expect(restartDuration < .seconds(1), "took \(restartDuration) to replace the dead server")
        let restarted = try #require(editor.uploadServer)

        let afterRestart = try await sendNativeUpload(from: editor.webView)
        #expect(afterRestart.port == Int(restarted.port), "the page still holds the old port")
        #expect(afterRestart.status == 201, "the upload after the restart didn't land: \(afterRestart)")
        #expect(uploader.uploads == 2)
    }

    /// Loads an empty `file://` page, the origin the editor itself runs from.
    @MainActor
    private func loadFilePage(in webView: WKWebView) async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let page = directory.appending(path: "index.html")
        try Data("<!doctype html><title>upload recovery</title>".utf8).write(to: page)

        webView.loadFileURL(page, allowingReadAccessTo: directory)
        for _ in 0..<200 {
            let loaded = try? await webView.evaluateJavaScript(
                "location.protocol === 'file:' && document.readyState === 'complete'"
            ) as? Bool
            if loaded == true { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("the file:// page never finished loading")
    }

    /// Sends the request `nativeMediaUploadMiddleware` sends for `POST /wp/v2/media`.
    @MainActor
    private func sendNativeUpload(from webView: WKWebView) async throws -> NativeUploadOutcome {
        let result = try await webView.callAsyncJavaScript(
            """
            const { nativeUploadPort: port, nativeUploadToken: token } = window.GBKit;
            const body = new FormData();
            body.append('file', new File(['not really a jpeg'], 'photo.jpg', { type: 'image/jpeg' }));
            const started = performance.now();
            try {
                const response = await fetch(`http://localhost:${port}/upload`, {
                    method: 'POST',
                    headers: { 'Relay-Authorization': `Bearer ${token}` },
                    body,
                });
                return { port, status: response.status, milliseconds: performance.now() - started };
            } catch (error) {
                return { port, error: `${error.name}: ${error.message}`, milliseconds: performance.now() - started };
            }
            """,
            contentWorld: .page
        )
        let outcome = try #require(result as? [String: Any])
        return NativeUploadOutcome(
            port: outcome["port"] as? Int,
            status: outcome["status"] as? Int,
            error: outcome["error"] as? String,
            milliseconds: outcome["milliseconds"] as? Double ?? -1
        )
    }

    /// `cancel()` completes on the listener's own queue, so the socket can outlive `stop()`
    /// by a moment.
    private func waitUntilSilent(_ server: MediaUploadServer) async throws {
        for _ in 0..<20 {
            if await !server.isAnswering(timeout: .milliseconds(300)) { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        Issue.record("the stopped server kept answering, so this test could not set up its own premise")
    }

    @MainActor
    @Test("no handler leaves the upload server down", .enabled(if: canBindUploadServer))
    func noHandlerLeavesServerDown() async {
        let editor = EditorViewController(configuration: makeConfiguration())

        await editor.startUploadServer()

        #expect(editor.uploadServer == nil, "started a server with nothing to route through it")
    }

    /// Polls instead of asserting outright, because a `UIViewController` can sit in an
    /// autorelease pool past the end of the scope that held it. Asserting synchronously
    /// passes in isolation and fails in a full suite, where other tests keep the main
    /// actor busy and the pool drains later. A real leak still fails this, a second later.
    @MainActor
    private func waitForRelease(_ isReleased: () -> Bool) async {
        for _ in 0..<100 where !isReleased() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// The shape that cycles: owns the editor *and* is its processor. Hosts reach for this
/// because the coordinator driving the editor already has the site context.
@MainActor
private final class EditorOwningProcessor: MediaProcessor {
    /// Implicitly unwrapped so `self` can be passed as the editor's processor: every stored
    /// property then has a value (nil) on entry to `init`, which is what makes `self`
    /// available there. Taking the processor at `init` doesn't prevent this shape — it just
    /// moves where the host writes it.
    private(set) var editor: EditorViewController!

    init(configuration: EditorConfiguration) {
        editor = EditorViewController(configuration: configuration, mediaProcessor: self)
    }

    nonisolated func handlesFile(ofType mimeType: String, named filename: String) -> Bool { false }

    nonisolated func processFile(at url: URL, mimeType: String, filename: String) async throws -> ProcessedProxyFile {
        .original
    }
}

private final class StandaloneProcessor: MediaProcessor {
    func handlesFile(ofType mimeType: String, named filename: String) -> Bool { false }

    func processFile(at url: URL, mimeType: String, filename: String) async throws -> ProcessedProxyFile {
        .original
    }
}

#endif

/// Supplied only to bring the upload server up; never invoked by these tests.
private struct InertUploader: MediaUploader {
    func upload(_ upload: MediaUpload) async throws -> Data { Data() }
}

/// Counts the uploads that reach it, and returns a finished attachment.
private final class CountingUploader: MediaUploader, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var uploads: Int { lock.withLock { count } }

    func upload(_ upload: MediaUpload) async throws -> Data {
        lock.withLock { count += 1 }
        return Data(#"{"id":7,"source_url":"https://example.com/photo.jpg","title":{"raw":"photo"}}"#.utf8)
    }
}

/// What a WebView upload came back with: an HTTP status, or the error `fetch` rejected with.
private struct NativeUploadOutcome: CustomStringConvertible {
    let port: Int?
    let status: Int?
    let error: String?
    let milliseconds: Double

    var description: String {
        let result = status.map { "HTTP \($0)" } ?? error ?? "nothing"
        return "\(result) from port \(port.map(String.init) ?? "none") after \(Int(milliseconds))ms"
    }
}

/// Whether `HTTPServer` can bind here — it cannot in some sandboxes, and these tests
/// assert on a real listener.
private let canBindUploadServer: Bool = {
    let result = UnsafeSendableBox(false)
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        if let server = try? await MediaUploadServer.start() {
            server.stop()
            result.value = true
        }
        semaphore.signal()
    }
    semaphore.wait()
    return result.value
}()

private final class UnsafeSendableBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
