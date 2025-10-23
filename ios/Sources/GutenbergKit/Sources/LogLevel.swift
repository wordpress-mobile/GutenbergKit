import Foundation

public enum LogLevel: String, Decodable, Sendable, Comparable {
    case error
    case warn
    case info
    case debug

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.intValue < rhs.intValue
    }

    private var intValue: UInt8 {
        switch self {
        case .error: 4
        case .warn: 3
        case .info: 2
        case .debug: 1
        }
    }
}
