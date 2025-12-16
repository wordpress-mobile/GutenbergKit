import Foundation

public enum EditorHttpMethod: String, Sendable, Codable, CaseIterable, Hashable {
    case GET
    case POST
    case PUT
    case DELETE
    case OPTIONS
}
