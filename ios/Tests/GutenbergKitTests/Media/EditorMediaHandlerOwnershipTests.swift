import Foundation
import Testing

@testable import GutenbergKit

#if canImport(UIKit)

/// The editor takes **strong** ownership of the media handlers it is given, so a host
/// can assign one and immediately drop its own reference. These pin that ownership: if
/// the properties regressed to `weak`, the handler would deallocate the moment the host
/// released it and the expectations below would fail.
///
/// The mirror invariant — that the upload *server* holds them **weakly**, so it can't
/// form a retain cycle back through the view controller — lives in
/// `MediaUploadServerTests.doesNotStronglyRetainProcessor`.
@Suite("Editor media-handler ownership")
struct EditorMediaHandlerOwnershipTests: MakesTestFixtures {
    static let testSiteURL = URL(string: "https://test.example.com")!
    static let testApiRoot = URL(string: "https://test.example.com/wp-json/wp/v2")!

    @MainActor
    @Test("the editor retains its mediaProcessor after the host releases it")
    func editorRetainsMediaProcessor() {
        let editor = EditorViewController(configuration: makeConfiguration())
        weak var weakProcessor: OwnershipTestProcessor?
        do {
            let processor = OwnershipTestProcessor()
            weakProcessor = processor
            editor.mediaProcessor = processor
        }
        withExtendedLifetime(editor) {
            #expect(weakProcessor != nil, "the editor must own its mediaProcessor for its lifetime")
        }
    }

    @MainActor
    @Test("the editor retains its mediaUploader after the host releases it")
    func editorRetainsMediaUploader() {
        let editor = EditorViewController(configuration: makeConfiguration())
        weak var weakUploader: OwnershipTestUploader?
        do {
            let uploader = OwnershipTestUploader()
            weakUploader = uploader
            editor.mediaUploader = uploader
        }
        withExtendedLifetime(editor) {
            #expect(weakUploader != nil, "the editor must own its mediaUploader for its lifetime")
        }
    }
}

private final class OwnershipTestProcessor: MediaProcessor, @unchecked Sendable {
    func handlesFile(ofType mimeType: String, named filename: String) -> Bool { false }
    func processFile(at url: URL, mimeType: String, filename: String) async throws -> ProcessedProxyFile { .original }
}

private final class OwnershipTestUploader: MediaUploader, @unchecked Sendable {
    func upload(_ upload: MediaUpload) async throws -> Data { Data() }
}

#endif
