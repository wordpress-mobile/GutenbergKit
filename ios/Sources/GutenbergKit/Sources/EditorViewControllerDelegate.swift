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

    /// Called after an error that prevents the editor from loading is displayed.
    func editor(_ viewController: EditorViewController, didFailToLoad error: Error)

    /// Notifies the client about the new edits.
    ///
    /// - note: To get the latest content, call ``EditorViewController/getTitleAndContent()``.
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

    /// Notifies the client about a network request and its response.
    ///
    /// This method is called when network logging is enabled via `EditorConfiguration.enableNetworkLogging`.
    /// It provides visibility into all fetch-based network requests made by the editor.
    ///
    /// - parameter request: The network request details including URL, headers, body, response, and timing.
    func editor(_ viewController: EditorViewController, didLogNetworkRequest request: RecordedNetworkRequest)

    /// Provides the latest persisted content for recovery after WebView refresh.
    ///
    /// Called when the WebView requests content during initialization. The host app should return
    /// the most recently persisted title and content from autosave. This allows content recovery
    /// when the WebView is re-initialized (e.g., due to OS memory pressure or page refresh).
    ///
    /// Note: The values in `EditorConfiguration.title` and `EditorConfiguration.content` are "initial values"
    /// injected at WebView load time. After a WebView refresh, these may be stale. This delegate method
    /// allows the host app to provide fresher content from its autosave mechanism.
    ///
    /// - Returns: A tuple of (title, content), or nil if no persisted content is available.
    func editorDidRequestLatestContent(_ controller: EditorViewController) -> (title: String, content: String)?
}

extension EditorViewControllerDelegate {
    public func editor(_ viewController: EditorViewController, didFailToLoad error: Error) {}
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
    /// Source-map Debug IDs for the files in the stack trace, used to symbolicate
    /// the exception in Sentry regardless of the on-device file paths.
    public let debugImages: [DebugImage]

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

    /// Pairs a minified file with the Debug ID that identifies its source map.
    public struct DebugImage {
        public let codeFile: String
        public let debugID: String

        init?(from dict: [AnyHashable: Any]) {
            guard let codeFile = dict["code_file"] as? String,
                  let debugID = dict["debug_id"] as? String
            else {
                return nil
            }
            self.codeFile = codeFile
            self.debugID = debugID
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
        // Optional: absent in payloads from builds without Debug IDs.
        let rawDebugImages = dict["debug_images"] as? [[AnyHashable: Any]] ?? []
        self.debugImages = rawDebugImages.compactMap { DebugImage(from: $0) }
    }
}

public struct OpenMediaLibraryAction: Codable {
    public let allowedTypes: [MediaType]?
    public let multiple: Bool
    public let value: Value?
    public let contextId: String

    private enum CodingKeys: String, CodingKey {
        case allowedTypes, multiple, value, contextId
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.allowedTypes = try container.decodeIfPresent([OpenMediaLibraryAction.MediaType].self, forKey: .allowedTypes)
        self.multiple = try container.decode(Bool.self, forKey: .multiple)
        self.contextId = try container.decode(String.self, forKey: .contextId)

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

public struct RecordedNetworkRequest {
    /// The request URL
    public let url: String
    /// The HTTP method (GET, POST, etc.)
    public let method: String
    /// The request headers
    public let requestHeaders: [String: String]
    /// The request body
    public let requestBody: String?
    /// The HTTP response status code
    public let status: Int
    /// The HTTP response status text (e.g., "OK", "Not Found")
    public let statusText: String
    /// The response headers
    public let responseHeaders: [String: String]
    /// The response body
    public let responseBody: String?
    /// The request duration in milliseconds
    public let duration: Int

    init?(from dict: [AnyHashable: Any]) {
        guard let url = dict["url"] as? String,
              let method = dict["method"] as? String,
              let requestHeaders = dict["requestHeaders"] as? [String: String],
              let status = dict["status"] as? Int,
              let responseHeaders = dict["responseHeaders"] as? [String: String],
              let duration = dict["duration"] as? Int
        else {
            return nil
        }

        self.url = url
        self.method = method
        self.requestHeaders = requestHeaders
        self.requestBody = dict["requestBody"] as? String
        self.status = status
        self.statusText = dict["statusText"] as? String ?? ""
        self.responseHeaders = responseHeaders
        self.responseBody = dict["responseBody"] as? String
        self.duration = duration
    }
}
