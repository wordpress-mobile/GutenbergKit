import UIKit

public struct MediaPickerAction: Identifiable {
    public let id: String
    public let title: String
    public let image: UIImage

    public init(id: String, title: String, image: UIImage) {
        self.id = id
        self.title = title
        self.image = image
    }
}

public struct MediaPickerActionGroup: Identifiable {
    public let id: String
    public let actions: [MediaPickerAction]

    public init(id: String, actions: [MediaPickerAction]) {
        self.id = id
        self.actions = actions
    }
}

/// Configuration parameters for media picker behavior.
public struct MediaPickerParameters {
    /// Filter that determines which types of media can be selected.
    public enum MediaFilter {
        case images
        case videos
        case all
    }

    /// Optional filter to restrict the types of media that can be selected.
    public var filter: MediaFilter?

    /// Whether users can select multiple media items at once.
    public var isMultipleSelectionEnabled: Bool

    public init(filter: MediaFilter? = nil, isMultipleSelectionEnabled: Bool = false) {
        self.filter = filter
        self.isMultipleSelectionEnabled = isMultipleSelectionEnabled
    }
}

@MainActor
public protocol MediaPickerController {
    /// Returns a grouped list of media picker actions for the given parameters.
    func getActions(for parameters: MediaPickerParameters) -> [MediaPickerActionGroup]

    /// Perform the action and return the selected media.
    func perform(_ action: MediaPickerAction, parameters: MediaPickerParameters, from presentingViewController: UIViewController) async -> [MediaInfo]
}

final class MediaPickerPresentationContext {
    weak var viewController: UIViewController?
}
