import Foundation

/// Protocol for logging editor-related messages.
public protocol EditorLogging: Sendable {
    /// Logs a message at the specified level.
    func log(_ level: EditorLogLevel, _ message: String)
}

/// Global logger for GutenbergKit.
///
/// - warning: The shared properties are nonisolated and should be set once
/// during the program lifetime before other editor APIs are used.
public enum EditorLogger {
    /// The shared logger instance used throughout GutenbergKit.
    public nonisolated(unsafe) static var shared: EditorLogging?

    /// The log level. Messages below this level are ignored.
    public nonisolated(unsafe) static var logLevel: EditorLogLevel = .error
}

func log(_ level: EditorLogLevel, _ message: @autoclosure () -> String) {
    guard level.priority >= EditorLogger.logLevel.priority,
          let logger = EditorLogger.shared else {
        return
    }
    logger.log(level, message())
}

public enum EditorLogLevel: String, Decodable, Sendable {
    case error
    case warn
    case info
    case debug

    public static let all: EditorLogLevel = .debug

    public var priority: Int {
        switch self {
        case .error: return 3
        case .warn: return 2
        case .info: return 1
        case .debug: return 0
        }
    }
}
