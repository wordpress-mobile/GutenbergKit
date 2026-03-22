import Foundation

/// Represents the progress of an editor loading operation.
///
/// Used to report progress during asset downloads and other long-running operations.
/// The progress is expressed as a count of completed items out of a total.
public struct EditorProgress: Codable, Sendable, Equatable {
    /// The number of items that have been completed.
    public let completed: Int

    /// The total number of items for the operation.
    public let total: Int

    /// The progress as a fraction between 0.0 and 1.0.
    ///
    /// Returns 0 if either `completed` or `total` is zero.
    /// The value is clamped to a maximum of 1.0.
    public var fractionCompleted: Double {
        guard completed != 0 && total != 0 else { return 0 }
        return min(Double(completed) / Double(total), 1.0)
    }

    /// Creates a new progress value.
    ///
    /// - Parameters:
    ///   - completed: The number of completed items.
    ///   - total: The total number of items.
    init(completed: Int, total: Int) {
        self.completed = completed
        self.total = total
    }

    /// A progress value representing no progress (0 of 0).
    public static let zero = EditorProgress(completed: 0, total: 0)
}

/// A callback that receives progress updates during long-running operations.
public typealias EditorProgressCallback = @Sendable (EditorProgress) async -> Void
