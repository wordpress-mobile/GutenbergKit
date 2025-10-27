import Foundation

public enum LogLevel: String, Decodable, Sendable {
    case error
    case warn
    case info
    case debug
}
