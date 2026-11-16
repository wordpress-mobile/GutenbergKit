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

        // Three successes and two failures, so a mixed-up count shows up in the
        // message. Both kinds of failure are included: a thrown error, and a
        // load that returns nothing.
        let results = await viewModel.processSelectedPhotosPickerItems([
            MockImportableMediaItem(.data(Self.jpeg)),
            MockImportableMediaItem(.failure),
            MockImportableMediaItem(.data(Self.jpeg)),
            MockImportableMediaItem(.empty),
            MockImportableMediaItem(.data(Self.jpeg)),
        ])

        #expect(results.count == 3)
        #expect(viewModel.error?.title == EditorLocalization[.someMediaFailedToInsert])
        #expect(viewModel.error?.message == EditorLocalization[.someSelectedMediaFailedToLoad(2)])
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
        #expect(viewModel.error?.title == EditorLocalization[.failedToInsertMedia])
        #expect(viewModel.error?.message == EditorLocalization[.failedToLoadSelectedMedia])
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

    @Test("Cancelling partway through inserts nothing and shows no alert", .timeLimit(.minutes(1)))
    func cancellingMidImportInsertsNothing() async {
        let (viewModel, root) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: root) }

        let (started, didStart) = AsyncStream<Void>.makeStream()
        let processing = Task {
            await viewModel.processSelectedPhotosPickerItems([
                MockImportableMediaItem(.data(Self.jpeg)),
                MockImportableMediaItem(.waitForCancellation(didStart)),
                MockImportableMediaItem(.data(Self.jpeg)),
            ])
        }

        // Cancel once the second item is loading, after the first has imported.
        for await _ in started { break }
        viewModel.cancelProcessing()

        let results = await processing.value
        #expect(results.isEmpty)
        #expect(viewModel.error == nil)
        #expect(viewModel.isProcessingMedia == false)
    }
}

/// A stand-in for `PhotosPickerItem` that returns canned transfer data or fails,
/// so the import loop can be driven without the real Photos picker.
private struct MockImportableMediaItem: ImportableMediaItem {
    enum Load: Sendable {
        case data(Data)   // `loadTransferable` returns this
        case failure      // `loadTransferable` throws
        case empty        // `loadTransferable` returns nil
        /// `loadTransferable` signals that it started, then waits until the
        /// import is cancelled.
        case waitForCancellation(AsyncStream<Void>.Continuation)
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
        case .waitForCancellation(let didStart):
            didStart.yield()
            try await Task.sleep(for: .seconds(120))
            return nil
        }
    }

    private enum MockError: Error { case loadFailed }
}

#endif
