import SwiftUI
import OSLog
import GutenbergKit

final class Navigation: ObservableObject {
    @Published var path = NavigationPath()

    @Published var hasEditor: Bool = false

    @Published var editor: RunnableEditor?

    func push(_ path: any Hashable) {
        self.path.append(path)
    }

    func present(_ editor: RunnableEditor) {
        self.hasEditor = true
        self.editor = editor
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

    // swiftlint:disable:next force_try
    // ConfigurationStorage uses SecureEnclave, which is available on all supported devices and Simulator.
    private let configurationStorage = try! ConfigurationStorage()

    init() {
        // Configure logger for GutenbergKit
        EditorLogger.shared = OSLogEditorLogger()
        EditorLogger.logLevel = .debug

        // The demo app renders the editor's own strings on purpose, so every
        // lookup falls back and the reports carry no signal here.
        EditorLocalization.reportsMissingTranslations = false
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $navigation.path) {
                AppRootView()
                .navigationDestination(for: ConfigurationItem.self) { item in
                    SitePreparationView(site: item)
                }
                .fullScreenCover(isPresented: $navigation.hasEditor) {
                    let editor = navigation.editor!

                    NavigationStack {
                        EditorView(
                            configuration: editor.configuration,
                            dependencies: editor.dependencies,
                            apiClient: editor.apiClient
                        )
                    }
                }

            }
        }
        .environment(\.navigation, navigation)
        .environmentObject(configurationStorage)
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
