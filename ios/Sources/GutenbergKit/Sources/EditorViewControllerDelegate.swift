import Foundation

#if canImport(UIKit)
@MainActor
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

    /// Notifies the client about a new featured image.
    func editor(_ viewController: EditorViewController, didUpdateFeaturedImage mediaID: Int)

    /// Notifies the client about an exception that occurred during the editor
    func editor(_ viewController: EditorViewController, didLogException error: GutenbergJSException)

    /// Notifies the client about a log message emitted by the editor
    func editor(_ viewController: EditorViewController, didLogMessage message: String, level: LogLevel)

    func editor(_ viewController: EditorViewController, didRequestMediaFromSiteMediaLibrary config: OpenMediaLibraryAction)

    /// Notifies the client that an autocompleter was triggered.
    ///
    /// - parameter type: The type of autocompleter that was triggered (e.g., "plus-symbol", "at-symbol").
    func editor(_ viewController: EditorViewController, didTriggerAutocompleter type: String)

    /// Notifies the client that a modal dialog has opened in the web editor.
    ///
    /// - parameter dialogType: The type of modal dialog that opened (e.g., "block-inserter", "media-library").
    func editor(_ viewController: EditorViewController, didOpenModalDialog dialogType: String)

    /// Notifies the client that a modal dialog has closed in the web editor.
    ///
    /// - parameter dialogType: The type of modal dialog that closed (e.g., "block-inserter", "media-library").
    func editor(_ viewController: EditorViewController, didCloseModalDialog dialogType: String)
}

#endif

public struct EditorState {
    /// Set to `true` if the editor has non-empty content.
    public var isEmpty = true
    /// Set to `true` if the editor has undo history.
    public var hasUndo = false
    /// Set to `true` if the editor has redo history.
    public var hasRedo = false
}

// Definition of JavaScript exception, which will be used to
// log exception to the Crash Logging service.
public struct GutenbergJSException {
    public let type: String
    public let message: String
    public let stacktrace: [StacktraceLine]
    public let context: [String: Any]
    public let tags: [String: String]
    public let isHandled: Bool
    public let handledBy: String

    public struct StacktraceLine {
        public let filename: String?
        public let function: String
        public let lineno: NSNumber?
        public let colno: NSNumber?

        init?(from dict: [AnyHashable: Any]) {
            guard let function = dict["function"] as? String else {
                return nil
            }
            self.filename = dict["filename"] as? String
            self.function = function
            self.lineno = dict["lineno"] as? NSNumber
            self.colno = dict["colno"] as? NSNumber
        }
    }

    init?(from dict: [AnyHashable: Any]) {
        guard let type = dict["type"] as? String,
              let message = dict["message"] as? String,
              let rawStacktrace = dict["stacktrace"] as? [[AnyHashable: Any]],
              let context = dict["context"] as? [String: Any],
              let tags = dict["tags"] as? [String: String],
              let isHandled = dict["isHandled"] as? Bool,
              let handledBy = dict["handledBy"] as? String
        else {
            return nil
        }

        self.type = type
        self.message = message
        self.stacktrace = rawStacktrace.compactMap { StacktraceLine(from: $0) }
        self.context = context
        self.tags = tags
        self.isHandled = isHandled
        self.handledBy = handledBy
    }
}

public struct OpenMediaLibraryAction: Codable {
    public let allowedTypes: [MediaType]?
    public let multiple: Bool
    public let value: Value?
    public let contextId: String?

    private enum CodingKeys: String, CodingKey {
        case allowedTypes, multiple, value, contextId
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.allowedTypes = try container.decodeIfPresent([OpenMediaLibraryAction.MediaType].self, forKey: .allowedTypes)
        self.multiple = try container.decode(Bool.self, forKey: .multiple)
        self.contextId = try container.decodeIfPresent(String.self, forKey: .contextId)

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
