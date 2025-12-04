import SwiftUI
import OSLog
import GutenbergKit

final class Navigation: ObservableObject {
    @Published var path = NavigationPath()

    func push(_ path: any Hashable) {
        self.path.append(path)
    }
}

extension EnvironmentValues {
    private struct NavigationKey: EnvironmentKey {
        static let defaultValue = Navigation()
    }

    var navigation: Navigation {
        get { self[NavigationKey.self] }
        set { self[NavigationKey.self] = newValue }
    }
}

@main
struct GutenbergApp: App {
    @StateObject
    private var navigation = Navigation()

    private let configurationStorage = ConfigurationStorage()
    private let authenticationManager = AuthenticationManager()

    init() {
        // Configure logger for GutenbergKit
        EditorLogger.shared = OSLogEditorLogger()
        EditorLogger.logLevel = .debug
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $navigation.path) {
                AppRootView()
                .navigationDestination(for: RunnableEditor.self) { editor in
                    EditorView(configuration: editor.configuration, dependencies: editor.dependencies)
                }
                .navigationDestination(for: ConfigurationItem.self) { item in
                    SitePreparationView(site: item)
                }
            }
        }
        .environment(\.navigation, navigation)
        .environmentObject(configurationStorage)
        .environmentObject(authenticationManager)
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
