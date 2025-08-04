import Foundation

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

    public init(id: Int32? = nil, url: String?, type: String?, caption: String? = nil, title: String? = nil, alt: String? = nil, metadata: [String: String] = [:]) {
        self.id = id
        self.url = url
        self.type = type
        self.caption = caption
        self.title = title
        self.alt = alt
        self.metadata = metadata
    }
}
