import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import GutenbergKit

#if canImport(UIKit)

/// Exercises `processSelectedPhotosPickerItems` end-to-end. The picker hands it
/// `PhotosPickerItem`s, which can't be constructed in a test, so imports run
/// against a mock `ImportableMediaItem` instead. The view model's file manager is
/// pointed at a throwaway directory so successful imports stay off the real
/// Library folder.
@MainActor
@Suite("BlockInserterViewModel media import")
struct BlockInserterViewModelTests {

    private static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])

    /// A view model whose imports write under a unique temp directory. Returns the
    /// root too, so the caller can delete it when the test ends.
    private func makeViewModel() -> (BlockInserterViewModel, root: URL) {
        let root = URL.temporaryDirectory.appending(component: "GBKTests-\(UUID().uuidString)")
        let viewModel = BlockInserterViewModel(
            sections: [],
            fileManager: MediaFileManager(rootURL: root)
        )
        return (viewModel, root)
    }

    // The bug this fixes: a failure used to abort the loop, so items picked
    // alongside a bad one were dropped and — because something did import — no
    // error was shown.
    @Test("A failure alongside successes still inserts the successes and reports the failure")
    func partialFailureKeepsSuccessesAndReportsError() async {
        let (viewModel, root) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: root) }

        let results = await viewModel.processSelectedPhotosPickerItems([
            MockImportableMediaItem(.data(Self.jpeg)),
            MockImportableMediaItem(.failure),
            MockImportableMediaItem(.data(Self.jpeg)),
        ])

        #expect(results.count == 2)
        #expect(viewModel.error != nil)
        #expect(viewModel.isProcessingMedia == false)
    }

    @Test("Every item failing inserts nothing and reports an error")
    func totalFailureReportsErrorAndInsertsNothing() async {
        let (viewModel, root) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: root) }

        let results = await viewModel.processSelectedPhotosPickerItems([
            MockImportableMediaItem(.failure),
            MockImportableMediaItem(.empty),
        ])

        #expect(results.isEmpty)
        #expect(viewModel.error != nil)
    }

    @Test("Every item importing reports no error")
    func allSuccessReportsNoError() async {
        let (viewModel, root) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: root) }

        let results = await viewModel.processSelectedPhotosPickerItems([
            MockImportableMediaItem(.data(Self.jpeg)),
            MockImportableMediaItem(.data(Self.jpeg)),
        ])

        #expect(results.count == 2)
        #expect(viewModel.error == nil)
    }

    @Test("Partial and total failures read differently")
    func partialAndTotalMessagesDiffer() {
        let partial = BlockInserterViewModel.importError(failureCount: 2, successCount: 3)?.message
        let total = BlockInserterViewModel.importError(failureCount: 2, successCount: 0)?.message
        #expect(partial != total)
    }
}

/// A stand-in for `PhotosPickerItem` that returns canned transfer data or fails,
/// so the import loop can be driven without the real Photos picker.
private struct MockImportableMediaItem: ImportableMediaItem {
    enum Load: Sendable {
        case data(Data)   // `loadTransferable` returns this
        case failure      // `loadTransferable` throws
        case empty        // `loadTransferable` returns nil
    }

    let load: Load
    let supportedContentTypes: [UTType]

    init(_ load: Load, contentTypes: [UTType] = [.jpeg]) {
        self.load = load
        self.supportedContentTypes = contentTypes
    }

    func loadTransferable<T: Transferable>(type: T.Type) async throws -> T? {
        switch load {
        case .data(let data): return data as? T
        case .failure: throw MockError.loadFailed
        case .empty: return nil
        }
    }

    private enum MockError: Error { case loadFailed }
}

#endif
