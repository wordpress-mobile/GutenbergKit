import Foundation
import Testing

@testable import GutenbergKit

#if canImport(UIKit)

/// Pins that ``EditorViewController/stopMediaHandling()`` opens the ownership cycle a host
/// can form, and that a host which doesn't form one needs nothing.
///
/// The editor holds `mediaUploadDelegate` strongly so an in-flight upload can't lose it
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
    @Test("stopMediaHandling frees the editor and the host delegate that owns it")
    func stopMediaHandlingBreaksTheOwnershipCycle() async {
        weak var weakEditor: EditorViewController?
        weak var weakHost: EditorOwningDelegate?

        do {
            let host = EditorOwningDelegate(configuration: makeConfiguration())
            weakEditor = host.editor
            weakHost = host
            host.editor.stopMediaHandling()
        }

        await waitForRelease { weakHost == nil && weakEditor == nil }

        #expect(weakHost == nil, "host delegate leaked — stopMediaHandling did not release it")
        #expect(weakEditor == nil, "EditorViewController leaked — cycle through mediaUploadDelegate")
    }

    @MainActor
    @Test("a host that does not retain the editor is freed without stopMediaHandling")
    func standaloneDelegateIsFreed() async {
        weak var weakEditor: EditorViewController?

        do {
            let editor = EditorViewController(
                configuration: makeConfiguration(),
                mediaUploadDelegate: StandaloneDelegate()
            )
            weakEditor = editor
        }

        await waitForRelease { weakEditor == nil }

        #expect(weakEditor == nil, "EditorViewController leaked — nothing here retains it")
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

/// The shape that cycles: owns the editor *and* is its delegate. Hosts reach for this
/// because the coordinator driving the editor already has the site context.
@MainActor
private final class EditorOwningDelegate: MediaUploadDelegate {
    /// Implicitly unwrapped so `self` can be passed as the editor's delegate: every stored
    /// property then has a value (nil) on entry to `init`, which is what makes `self`
    /// available there. Taking the delegate at `init` doesn't prevent this shape — it just
    /// moves where the host writes it.
    private(set) var editor: EditorViewController!

    init(configuration: EditorConfiguration) {
        editor = EditorViewController(configuration: configuration, mediaUploadDelegate: self)
    }

    nonisolated func handlesFile(ofType mimeType: String, named filename: String) -> Bool { false }

    nonisolated func processFile(at url: URL, mimeType: String, filename: String) async throws -> ProcessedProxyFile {
        .original
    }
}

private final class StandaloneDelegate: MediaUploadDelegate {
    func handlesFile(ofType mimeType: String, named filename: String) -> Bool { false }

    func processFile(at url: URL, mimeType: String, filename: String) async throws -> ProcessedProxyFile {
        .original
    }
}

#endif
