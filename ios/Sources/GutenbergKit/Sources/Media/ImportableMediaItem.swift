import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The slice of `PhotosPickerItem` that ``MediaFileManager/import(_:)`` relies on.
///
/// `PhotosPickerItem` can't be constructed in a test, so the import path is
/// written against this protocol rather than the concrete type. `PhotosPickerItem`
/// already provides both members, so it conforms with an empty extension; tests
/// substitute a mock that returns canned transfer data or throws.
///
/// `Sendable` because items cross into the `MediaFileManager` actor — a
/// requirement `PhotosPickerItem` already meets (the picker selection is captured
/// by a `@Sendable` task before it gets here).
protocol ImportableMediaItem: Sendable {
    var supportedContentTypes: [UTType] { get }
    func loadTransferable<T: Transferable>(type: T.Type) async throws -> T?
}

extension PhotosPickerItem: ImportableMediaItem {}
