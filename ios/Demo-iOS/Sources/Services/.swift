import Foundation
import OSLog
import GutenbergKit

/// An OSLog-based implementation of EditorLogging.
struct OSLogEditorLogger: EditorLogging {
    private let logger: Logger

    init(subsystem: String = "com.gutenbergkit.demo", category: String = "GutenbergKit") {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    func log(_ level: EditorLogLevel, _ message: String) {
        switch level {
        case .debug: logger.debug("\(message)")
        case .info: logger.info("\(message)")
        case .warn: logger.warning("\(message)")
        case .error: logger.error("\(message)")
        }
    }
}
