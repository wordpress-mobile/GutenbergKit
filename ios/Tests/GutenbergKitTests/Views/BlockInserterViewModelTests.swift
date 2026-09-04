import Foundation
import Testing
@testable import GutenbergKit

#if canImport(UIKit)

/// Covers the decision `processSelectedPhotosPickerItems` makes after importing
/// a selection: which failures surface an alert, and which message. The import
/// loop itself takes `PhotosPickerItem`s, which can't be constructed in a test,
/// so the outcome logic is factored into `importError` and verified here.
@MainActor
@Suite("BlockInserterViewModel media import error")
struct BlockInserterViewModelTests {

    @Test("Every item imported: no alert")
    func allSucceededProducesNoError() {
        #expect(BlockInserterViewModel.importError(failureCount: 0, successCount: 3) == nil)
        #expect(BlockInserterViewModel.importError(failureCount: 0, successCount: 0) == nil)
    }

    @Test("Every item failed: surfaces an alert")
    func totalFailureSurfacesError() {
        #expect(BlockInserterViewModel.importError(failureCount: 2, successCount: 0) != nil)
    }

    // The bug this fixes: a failure alongside a success used to be dropped
    // silently because the alert only showed when nothing imported.
    @Test("Partial failure still surfaces an alert")
    func partialFailureSurfacesError() {
        #expect(BlockInserterViewModel.importError(failureCount: 1, successCount: 2) != nil)
    }

    @Test("Partial and total failures read differently")
    func partialAndTotalMessagesDiffer() {
        let partial = BlockInserterViewModel.importError(failureCount: 2, successCount: 3)?.message
        let total = BlockInserterViewModel.importError(failureCount: 2, successCount: 0)?.message
        #expect(partial != total)
    }
}

#endif
