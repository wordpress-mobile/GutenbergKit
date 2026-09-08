import Foundation
import Testing

@testable import GutenbergKit

#if canImport(UIKit)

/// Pins the ownership contract documented on ``EditorViewController/mediaUploadDelegate``:
/// the editor holds the delegate strongly for its lifetime and lets go on `deinit`.
///
/// The server-side half of this — that `MediaUploadServer` releases the delegate the
/// moment the host releases the server — is covered on the host platform by
/// `MediaUploadServerTests`. This suite covers the half that only exists
/// under UIKit: that owning the delegate strongly does not keep the editor itself
/// alive, so `deinit` actually runs and the release actually happens.
@Suite("EditorViewController media upload lifetime")
struct EditorViewControllerMediaLifetimeTests: MakesTestFixtures {
    static let testSiteURL = URL(string: "https://test.example.com")!
    static let testApiRoot = URL(string: "https://test.example.com/wp-json/wp/v2")!

    @MainActor
    @Test("deinit releases the editor and the media upload delegate it owns")
    func deinitReleasesEditorAndDelegate() throws {
        weak var weakEditor: EditorViewController?
        weak var weakDelegate: LifetimeProbeDelegate?

        do {
            let editor = EditorViewController(configuration: makeConfiguration())
            let delegate = LifetimeProbeDelegate()
            editor.mediaUploadDelegate = delegate
            weakEditor = editor
            weakDelegate = delegate
        }

        // `mediaUploadDelegate` is a strong `var` (the `weak_delegate` rule is
        // disabled on it deliberately). That is only safe while the delegate does
        // not retain the editor back, so pin that the editor is still freed.
        #expect(weakEditor == nil, "EditorViewController leaked — check for a cycle through mediaUploadDelegate")

        // And that the host does not have to hold the delegate itself: assigning it
        // and dropping every other reference must not leak it for the process's life.
        #expect(weakDelegate == nil, "mediaUploadDelegate outlived the editor that owned it")
    }
}

/// A delegate that does nothing but be observed for deallocation.
private final class LifetimeProbeDelegate: MediaUploadDelegate, @unchecked Sendable {
    func handlesFile(ofType mimeType: String, named filename: String) -> Bool { false }

    func processFile(at url: URL, mimeType: String, filename: String) async throws -> ProcessedProxyFile {
        .original
    }
}

#endif
