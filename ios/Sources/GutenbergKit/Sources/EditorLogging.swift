import Foundation
import OSLog

/// Protocol for logging editor-related messages.
public protocol EditorLogging: Sendable {
    /// Logs a message at the specified level.
    func log(_ level: EditorLogLevel, _ message: String)
}

extension Logger {

    public static let performance = OSSignposter(subsystem: "GutenbergKit", category: "performance")

    /// Logs timings for performance optimization
    public static let timing = Logger(subsystem: "GutenbergKit", category: "timing")
    
    /// Logs editor asset library activity
    public static let assetLibrary = Logger(subsystem: "GutenbergKit", category: "asset-library")
    
    /// Logs editor HTTP activity
    public static let http = Logger(subsystem: "GutenbergKit", category: "http")

    /// Logs editor navigation activity
    public static let navigation = Logger(subsystem: "GutenbergKit", category: "navigation")
}

public struct SignpostMonitor: Sendable {
    private let id: OSSignpostID
    private let logger: OSSignposter

    private var subtasks: [String: OSSignpostIntervalState] = [:]

    public init(for logger: OSSignposter) {

        self.logger = logger
        self.id = logger.makeSignpostID()
    }

    public mutating func startTask(_ event: StaticString = #function) {
        self.subtasks["\(event)"] = self.logger.beginInterval(event, id: id)
    }

    public mutating func endTask(_ event: StaticString = #function) {
        precondition(self.subtasks["\(event)"] != nil)
        self.logger.endInterval(event, self.subtasks["\(event)"]!)
    }

    public func measure<T>(_ name: StaticString = #function, _ work: () throws -> T) rethrows -> T {
        try self.logger.withIntervalSignpost(name, id: self.id, around: work)
    }

    public func measure<T>(_ name: StaticString = #function, _ work: @Sendable () async throws -> T) async rethrows -> T {
        let handle = self.logger.beginInterval(name)
        defer { self.logger.endInterval(name, handle) }
        return try await work()
    }
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
          let logger = EditorLogger.shared
    else {
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
