import UIKit

public struct MediaPickerAction: Identifiable {
    public let id: String
    public let title: String
    public let image: UIImage
    public let perform: @MainActor (UIViewController, @escaping ([MediaInfo]) -> Void) -> Void

    public init(id: String, title: String, image: UIImage, perform: @escaping @MainActor (UIViewController, @escaping ([MediaInfo]) -> Void) -> Void) {
        self.id = id
        self.title = title
        self.image = image
        self.perform = perform
    }
}

public struct MediaPickerParameters {
    public enum MediaFilter {
        case images
        case videos
        case all
    }

    public var filter: MediaFilter?
    public var isMultipleSelectionEnabled: Bool

    public init(filter: MediaFilter? = nil, isMultipleSelectionEnabled: Bool = false) {
        self.filter = filter
        self.isMultipleSelectionEnabled = isMultipleSelectionEnabled
    }
}

/// A type that manages media picker sources.
public protocol MediaPickerController {
    /// A grouped list of available actions.
    var actions: [[MediaPickerAction]] { get }
}
