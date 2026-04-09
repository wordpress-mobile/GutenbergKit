import Foundation

#if canImport(UIKit)

/// Delegate for editor persistence: content recovery and save lifecycle hooks.
///
/// Implement this protocol to provide content recovery after WebView refresh and
/// to hook into the save lifecycle. Set it on ``EditorViewController/persistenceDelegate``.
@MainActor
public protocol EditorPersistenceDelegate: AnyObject {

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

    /// Pre-save hook: receives the current post and returns a (possibly modified) version.
    ///
    /// Called by the editor's `savePost()` just before persisting changes. The editor passes
    /// the entity record to this method. The host may inspect and modify any fields — for
    /// example, updating categories or tags that were changed in native UI — and return the
    /// modified post.
    ///
    /// The returned value is merged into the entity record as edits before the save PUT is
    /// sent. The default implementation returns the post unmodified.
    ///
    /// - Parameter post: The current entity record.
    /// - Returns: The post, with any modifications applied.
    func editor(_ controller: EditorViewController, willSavePost post: EditorPost) -> EditorPost

    /// Called when the editor has successfully saved the post.
    func editor(_ controller: EditorViewController, didSavePost post: EditorPost)

    /// Called when the editor encountered an error while saving the post.
    func editor(_ controller: EditorViewController, didFailToSavePost post: EditorPost, error: Error)

    /// Notifies the client that the save availability state has changed.
    ///
    /// Use this to enable/disable save UI (e.g. a "Save" button) based on whether
    /// the post has unsaved changes, is saveable, or is currently being saved.
    ///
    /// - parameter state: The current save availability state.
    func editor(_ controller: EditorViewController, didUpdateSaveAvailability state: SaveAvailabilityState)
}

public extension EditorPersistenceDelegate {
    func editor(_ controller: EditorViewController, willSavePost post: EditorPost) -> EditorPost { post }
    func editor(_ controller: EditorViewController, didSavePost post: EditorPost) {}
    func editor(_ controller: EditorViewController, didFailToSavePost post: EditorPost, error: Error) {}
    func editor(_ controller: EditorViewController, didUpdateSaveAvailability state: SaveAvailabilityState) {}
}

#endif

/// A WordPress post entity used by the pre-save hook.
///
/// This struct models the common fields of a WordPress REST API post object.
/// All fields are optional so the host can return only the fields it modified.
///
/// Field names match the WordPress REST API (e.g. `featured_media`, `comment_status`)
/// and are bridged to Swift naming conventions via `CodingKeys`.
public struct EditorPost: Codable, Sendable {

    /// The post ID.
    public var id: Int?

    /// The post title (`{ raw, rendered }`).
    public var title: Content?

    /// The post content (`{ raw, rendered }`).
    public var content: Content?

    /// The post excerpt (`{ raw, rendered }`).
    public var excerpt: Content?

    /// The post status (e.g. `"draft"`, `"publish"`, `"pending"`).
    public var status: String?

    /// The post type slug (e.g. `"post"`, `"page"`).
    public var type: String?

    /// The post slug.
    public var slug: String?

    /// The author user ID.
    public var author: Int?

    /// The featured image attachment ID (0 means no featured image).
    public var featuredMedia: Int?

    /// Category term IDs.
    public var categories: [Int]?

    /// Tag term IDs.
    public var tags: [Int]?

    /// The post format (e.g. `"standard"`, `"aside"`, `"gallery"`).
    public var format: String?

    /// Post meta fields. Values use the ``JSON`` enum for flexible typing.
    public var meta: [String: JSON]?

    /// The page/block template file.
    public var template: String?

    /// Whether comments are open (`"open"` or `"closed"`).
    public var commentStatus: String?

    /// Whether pingbacks are open (`"open"` or `"closed"`).
    public var pingStatus: String?

    /// Whether the post is sticky.
    public var sticky: Bool?

    /// Term IDs for custom taxonomies, keyed by the taxonomy's `rest_base` slug.
    ///
    /// The WordPress REST API exposes custom taxonomies registered with
    /// `show_in_rest` as top-level `[Int]` arrays on the post object
    /// (e.g. `"genre": [4, 7]`). During decoding, any top-level `[Int]`
    /// key that isn't a known property is collected here. During encoding,
    /// these are spread back out as top-level keys so the REST API
    /// receives them in the expected format.
    ///
    /// ```swift
    /// // Reading custom taxonomy terms:
    /// let genres = post.customTerms?["genre"] // [4, 7]
    ///
    /// // Setting custom taxonomy terms in willSavePost:
    /// var post = post
    /// post.customTerms = (post.customTerms ?? [:]).merging(["genre": [4, 7, 12]]) { _, new in new }
    /// return post
    /// ```
    public var customTerms: [String: [Int]]?

    /// A `{ raw, rendered }` content value from the WordPress REST API.
    public struct Content: Codable, Sendable {
        public var raw: String?
        public var rendered: String?

        public init(raw: String? = nil, rendered: String? = nil) {
            self.raw = raw
            self.rendered = rendered
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, title, content, excerpt, status, type, slug, author
        case featuredMedia = "featured_media"
        case categories, tags, format, meta, template
        case commentStatus = "comment_status"
        case pingStatus = "ping_status"
        case sticky
    }

    /// All known coding key string values, used to identify custom taxonomy keys during decoding.
    private static let knownKeys: Set<String> = {
        var keys = Set<String>()
        for key in CodingKeys.allCases {
            keys.insert(key.rawValue)
            keys.insert(key.stringValue)
        }
        return keys
    }()

    /// Dynamic coding key for encoding/decoding unknown top-level fields.
    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(
        id: Int? = nil,
        title: Content? = nil,
        content: Content? = nil,
        excerpt: Content? = nil,
        status: String? = nil,
        type: String? = nil,
        slug: String? = nil,
        author: Int? = nil,
        featuredMedia: Int? = nil,
        categories: [Int]? = nil,
        tags: [Int]? = nil,
        format: String? = nil,
        meta: [String: JSON]? = nil,
        template: String? = nil,
        commentStatus: String? = nil,
        pingStatus: String? = nil,
        sticky: Bool? = nil,
        customTerms: [String: [Int]]? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.excerpt = excerpt
        self.status = status
        self.type = type
        self.slug = slug
        self.author = author
        self.featuredMedia = featuredMedia
        self.categories = categories
        self.tags = tags
        self.format = format
        self.meta = meta
        self.template = template
        self.commentStatus = commentStatus
        self.pingStatus = pingStatus
        self.sticky = sticky
        self.customTerms = customTerms
    }

    /// Creates an `EditorPost` from a dictionary, such as a WKWebView `message.body`.
    ///
    /// This avoids the round-trip through `JSONSerialization.data` → `JSONDecoder`
    /// when the source is already a Foundation dictionary (e.g. from the JS bridge).
    public init(dictionary dict: [String: Any]) {
        self.id = dict["id"] as? Int
        self.title = Self.content(from: dict["title"])
        self.content = Self.content(from: dict["content"])
        self.excerpt = Self.content(from: dict["excerpt"])
        self.status = dict["status"] as? String
        self.type = dict["type"] as? String
        self.slug = dict["slug"] as? String
        self.author = dict["author"] as? Int
        self.featuredMedia = dict["featured_media"] as? Int
        self.categories = Self.intArray(from: dict["categories"])
        self.tags = Self.intArray(from: dict["tags"])
        self.format = dict["format"] as? String
        self.meta = (dict["meta"] as? [String: Any]).map(Self.jsonDictionary)
        self.template = dict["template"] as? String
        self.commentStatus = dict["comment_status"] as? String
        self.pingStatus = dict["ping_status"] as? String
        self.sticky = dict["sticky"] as? Bool

        // Sweep unknown [Int] arrays into customTerms.
        var terms: [String: [Int]] = [:]
        for (key, value) in dict where !Self.knownKeys.contains(key) {
            if let ids = Self.intArray(from: value) {
                terms[key] = ids
            }
        }
        self.customTerms = terms.isEmpty ? nil : terms
    }

    private static func content(from value: Any?) -> Content? {
        if let dict = value as? [String: Any] {
            return Content(raw: dict["raw"] as? String, rendered: dict["rendered"] as? String)
        }
        return nil
    }

    private static func intArray(from value: Any?) -> [Int]? {
        guard let array = value as? [Any] else { return nil }
        let ints = array.compactMap { $0 as? Int }
        guard ints.count == array.count else { return nil }
        return ints
    }

    private static func jsonValue(from value: Any) -> JSON {
        switch value {
        case let bool as Bool:
            return .boolean(bool)
        case let int as Int:
            return .number(Double(int))
        case let double as Double:
            return .number(double)
        case let string as String:
            return .string(string)
        case let array as [Any]:
            return .array(array.map(jsonValue))
        case let dict as [String: Any]:
            return .object(jsonDictionary(from: dict))
        default:
            return .null
        }
    }

    private static func jsonDictionary(from dict: [String: Any]) -> [String: JSON] {
        dict.mapValues(jsonValue)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        title = try container.decodeIfPresent(Content.self, forKey: .title)
        content = try container.decodeIfPresent(Content.self, forKey: .content)
        excerpt = try container.decodeIfPresent(Content.self, forKey: .excerpt)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        slug = try container.decodeIfPresent(String.self, forKey: .slug)
        author = try container.decodeIfPresent(Int.self, forKey: .author)
        featuredMedia = try container.decodeIfPresent(Int.self, forKey: .featuredMedia)
        categories = try container.decodeIfPresent([Int].self, forKey: .categories)
        tags = try container.decodeIfPresent([Int].self, forKey: .tags)
        format = try container.decodeIfPresent(String.self, forKey: .format)
        meta = try container.decodeIfPresent([String: JSON].self, forKey: .meta)
        template = try container.decodeIfPresent(String.self, forKey: .template)
        commentStatus = try container.decodeIfPresent(String.self, forKey: .commentStatus)
        pingStatus = try container.decodeIfPresent(String.self, forKey: .pingStatus)
        sticky = try container.decodeIfPresent(Bool.self, forKey: .sticky)

        // Sweep unknown top-level [Int] arrays into customTerms.
        let dynamic = try decoder.container(keyedBy: DynamicKey.self)
        var terms: [String: [Int]] = [:]
        for key in dynamic.allKeys where !Self.knownKeys.contains(key.stringValue) {
            if let ids = try? dynamic.decode([Int].self, forKey: key) {
                terms[key.stringValue] = ids
            }
        }
        customTerms = terms.isEmpty ? nil : terms
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(excerpt, forKey: .excerpt)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(slug, forKey: .slug)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encodeIfPresent(featuredMedia, forKey: .featuredMedia)
        try container.encodeIfPresent(categories, forKey: .categories)
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encodeIfPresent(format, forKey: .format)
        try container.encodeIfPresent(meta, forKey: .meta)
        try container.encodeIfPresent(template, forKey: .template)
        try container.encodeIfPresent(commentStatus, forKey: .commentStatus)
        try container.encodeIfPresent(pingStatus, forKey: .pingStatus)
        try container.encodeIfPresent(sticky, forKey: .sticky)

        // Spread customTerms back out as top-level keys.
        if let customTerms {
            var dynamic = encoder.container(keyedBy: DynamicKey.self)
            for (slug, ids) in customTerms {
                try dynamic.encode(ids, forKey: DynamicKey(stringValue: slug))
            }
        }
    }
}
