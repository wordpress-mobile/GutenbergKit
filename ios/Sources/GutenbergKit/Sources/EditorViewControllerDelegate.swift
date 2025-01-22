import Foundation

public protocol EditorViewControllerDelegate: AnyObject {
    /// Called when the editor loads.
    func editorDidLoad(_ viewContoller: EditorViewController)

    /// Gets called when the editor is loaded and the initial content is displayed.
    ///
    /// - parameter content: Content serialized according to the editor's settings.
    func editor(_ viewContoller: EditorViewController, didDisplayInitialContent content: String)

    /// Editor encounterd a critical error and has to be stopped.
    ///
    /// - warning: Make sure not to update user content if that happens (it shouldn't)
    func editor(_ viewContoller: EditorViewController, didEncounterCriticalError error: Error)

    /// Notifies the client about the new edits.
    ///
    /// - note: To get the latest content, call ``EditorViewController/getContent()``.
    /// Retrieving the content is a relatively expensive operation and should not
    /// be performed too frequently during editing.
    ///
    /// - warning: This is currently also called for the initial render, which
    /// is probably not how it should be in the production design.
    func editor(_ viewController: EditorViewController, didUpdateContentWithState state: EditorState)

    /// Notifies the client about new history state.
    func editor(_ viewController: EditorViewController, didUpdateHistoryState state: EditorState)

    /// Notifies the client about an error that occurred during the editor
    func editor(_ viewController: EditorViewController, didLogError error: EditorError)

    func editor(_ viewController: EditorViewController, didRequestMediaFromSiteMediaLibrary config: OpenMediaLibraryAction)
}

public struct EditorState {
    /// Set to `true` if the editor has non-empty content.
    public var isEmpty = true
    /// Set to `true` if the editor has undo history.
    public var hasUndo = false
    /// Set to `true` if the editor has redo history.
    public var hasRedo = false
}

public struct EditorError {
    public let message: String
    public let stack: String
    public let sourceURL: String
    public let line: Int
    public let column: Int
}

public struct OpenMediaLibraryAction: Codable {
    public let allowedTypes: [MediaType]?
    public let multiple: Bool
    public let value: Value?

    private enum CodingKeys: String, CodingKey {
        case allowedTypes, multiple, value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.allowedTypes = try container.decodeIfPresent([OpenMediaLibraryAction.MediaType].self, forKey: .allowedTypes)
        self.multiple = try container.decode(Bool.self, forKey: .multiple)

        // Decode value as either Int? or [Int]?
        if let singleValue = try? container.decodeIfPresent(Int.self, forKey: .value) {
            self.value = .single(singleValue)
        } else if let multipleValues = try? container.decodeIfPresent([Int].self, forKey: .value) {
            self.value = .multiple(multipleValues)
        } else {
            self.value = nil
        }
    }

    public enum MediaType: String, Codable {
        case image
        case video
        case audio
        case other
        case any
    }

    public enum Value: Codable {
        case single(Int)
        case multiple([Int])
    }
}

public struct MediaInfo: Codable {
    public let id: Int32?
    public let url: String?
    public let type: String?
    public let title: String?
    public let caption: String?
    public let alt: String?
    public let metadata: [String: String]

    private enum CodingKeys: String, CodingKey {
        case id, url, type, title, caption, alt, metadata
    }

    public init(id: Int32?, url: String?, type: String?, caption: String? = nil, title: String? = nil, alt: String? = nil, metadata: [String: String] = [:]) {
        self.id = id
        self.url = url
        self.type = type
        self.caption = caption
        self.title = title
        self.alt = alt
        self.metadata = metadata
    }
}
