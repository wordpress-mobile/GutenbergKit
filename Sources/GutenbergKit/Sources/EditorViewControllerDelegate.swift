import Foundation

public protocol EditorViewControllerDelegate: AnyObject {
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

    func editor(_ viewController: EditorViewController, didRequestMediaFromSiteMediaLibrary config: OpenMediaLibrary)
}

public struct EditorState {
    /// Set to `true` if the editor has non-empty content.
    public var isEmpty = true
}

public struct OpenMediaLibrary: Decodable {
    public let allowedTypes: [MediaType]
    public let multiple: Bool
    public let value: Value?

    private enum CodingKeys: String, CodingKey {
        case allowedTypes, multiple, value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        multiple = try container.decode(Bool.self, forKey: .multiple)

        // Decode allowedTypes as [String] and convert to [MediaType]
        // If allowedTypes is not present in the JSON, use an empty array
        let stringTypes = try container.decodeIfPresent([String].self, forKey: .allowedTypes) ?? []
        allowedTypes = stringTypes.map { MediaType(fromJSString: $0) }

        // Decode value as either Int? or [Int]?
        if let singleValue = try? container.decodeIfPresent(Int.self, forKey: .value) {
            value = .single(singleValue)
        } else if let multipleValues = try? container.decodeIfPresent([Int].self, forKey: .value) {
            value = .multiple(multipleValues)
        } else {
            value = nil
        }
    }

    public enum MediaType: String, Decodable {
        case image
        case video
        case audio
        case other
        case any
    }

    public enum Value {
        case single(Int)
        case multiple([Int])
    }
}

extension OpenMediaLibrary.MediaType {
    init(fromJSString rawValue: String) {
        self = OpenMediaLibrary.MediaType(rawValue: rawValue) ?? .other
    }
}

public struct MediaInfo: Encodable {
    public let id: Int32?
    public let url: String?
    public let type: String?
    public let title: String?
    public let caption: String?
    public let alt: String?
    public let metadata: [String: Any]

    private enum CodingKeys: String, CodingKey {
        case id, url, type, title, caption, alt
    }

    public init(id: Int32?, url: String?, type: String?, caption: String? = nil, title: String? = nil, alt: String? = nil, metadata: [String: Any] = [:]) {
        self.id = id
        self.url = url
        self.type = type
        self.caption = caption
        self.title = title
        self.alt = alt
        self.metadata = metadata
    }

    public func encode(to encoder: Encoder) throws {
       var container = encoder.container(keyedBy: CodingKeys.self)
       try container.encodeIfPresent(id, forKey: .id)
       try container.encode(url ?? "", forKey: .url)
       try container.encode(type ?? "", forKey: .type)
       try container.encode(title ?? "", forKey: .title)
       try container.encode(caption ?? "", forKey: .caption)
       try container.encode(alt ?? "", forKey: .alt)
   }
}
