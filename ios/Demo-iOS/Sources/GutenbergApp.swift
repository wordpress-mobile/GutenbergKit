import SwiftUI
import OSLog
import GutenbergKit

@main
struct GutenbergApp: App {
    init() {
        // Configure logger for GutenbergKit
        EditorLogger.shared = OSLogEditorLogger()
        EditorLogger.logLevel = .debug
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                AppRootView()
            }
        }
        .environmentObject(ConfigurationStorage())
        .environmentObject(AuthenticationManager())
    }
}

struct OSLogEditorLogger: GutenbergKit.EditorLogging {
    private let logger: Logger

    init(subsystem: String = "com.gutenbergkit.demo", category: String = "GutenbergKit") {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    func log(_ level: GutenbergKit.EditorLogLevel, _ message: String) {
        switch level {
        case .debug: logger.debug("\(message)")
        case .info: logger.info("\(message)")
        case .warn: logger.warning("\(message)")
        case .error: logger.error("\(message)")
        }
    }
}
