import Foundation
import Testing

@testable import GutenbergKit

#if canImport(UIKit)

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
