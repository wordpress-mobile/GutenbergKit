import SwiftUI
import GutenbergKit
import AuthenticationServices
import WordPressAPI

struct AppRootView: View {

    @EnvironmentObject
    private var configurationStorage: ConfigurationStorage

    @EnvironmentObject
    private var authenticationManager: AuthenticationManager

    @State private var selectedConfiguration: ConfigurationItem?
    @State private var configurations: [ConfigurationItem] = [.bundledEditor]
    @State private var siteUrlInput = ""

    @State private var activeEditorConfiguration: EditorConfiguration? = nil
    @State private var activeEditorService: EditorService? = nil

    @State private var hasError: Bool = false
    @State private var error: AppError? = nil

    @AppStorage("isNativeInserterEnabled") private var isNativeInserterEnabled = false

    var body: some View {
        EditorList(isNativeInserterEnabled: $isNativeInserterEnabled, selectedConfiguration: $selectedConfiguration)
        .alert(isPresented: $hasError, error: error, actions: {
            Button {
                self.hasError = false
            } label: {
                HStack {
                    Spacer()
                    Text("Dismiss")
                    Spacer()
                }
            }.buttonStyle(.borderedProminent)
        })
        .fullScreenCover(item: $selectedConfiguration) { config in
            editor
        }
        .onChange(of: self.selectedConfiguration) { oldValue, newValue in
            switch newValue {
            case .bundledEditor:
                let (config, service) = createBundledConfiguration()
                activeEditorConfiguration = config
                activeEditorService = service
            case .editorConfiguration(let config):
                self.loadEditorConfiguration(for: config)
            case .none:
                self.activeEditorConfiguration = nil
                self.activeEditorService = nil
            }
        }
    }

    @ViewBuilder
    var editor: some View {
        NavigationView {
            if let activeEditorConfiguration, let activeEditorService {
                EditorView(service: activeEditorService, configuration: activeEditorConfiguration)
            } else {
                ProgressView("Preparing Editor")
            }
        }
    }

    private func loadEditorConfiguration(for config: ConfiguredEditor) {
        Task {
            do {
                let client = WordPressAPI(
                    urlSession: .shared,
                    apiRootUrl: try ParsedUrl.parse(input: config.siteApiRoot),
                    authentication: .authorizationHeader(token: config.authHeader)
                )

                let apiRoot = try await client.apiRoot.get().data

                let canUsePlugins = apiRoot.hasRoute(route: "/wpcom/v2/editor-assets")
                let canUseEditorStyles = apiRoot.hasRoute(route: "/wp-block-editor/v1/settings")

                var updatedConfiguration = EditorConfigurationBuilder()
                    .setShouldUseThemeStyles(canUseEditorStyles)
                    .setShouldUsePlugins(canUsePlugins)
                    .setSiteUrl(config.siteUrl)
                    .setSiteApiRoot(config.siteApiRoot)
                    .setAuthHeader(config.authHeader)
                    .setNativeInserterEnabled(isNativeInserterEnabled)
                    .setLogLevel(.debug)
                    .build()

                if let baseURL = URL(string: config.siteApiRoot) {
                    let service = EditorService(
                        siteID: config.siteUrl,
                        baseURL: baseURL,
                        authHeader: config.authHeader,
                        logLevel: .debug
                    )
                    do {
                        try await service.setup(&updatedConfiguration)
                    } catch {
                        print("Failed to setup editor environment, confinuing with the default or cached configuration:", error)
                    }
                    self.activeEditorService = service
                }

                self.activeEditorConfiguration = updatedConfiguration
            } catch {
                self.hasError = true
                self.error = AppError(errorDescription: error.localizedDescription)
            }
        }
    }

    private func deleteConfiguration(_ config: ConfigurationItem) {
        configurations.removeAll { $0.id == config.id }
        configurationStorage.saveConfigurations(configurations)
    }

    private func createBundledConfiguration() -> (EditorConfiguration, EditorService) {
        let config = EditorConfigurationBuilder()
            .setShouldUsePlugins(false)
            .setSiteUrl("")
            .setSiteApiRoot("")
            .setAuthHeader("")
            .setNativeInserterEnabled(isNativeInserterEnabled)
            .build()

        // Create a dummy EditorService for bundled editor (no network requests needed)
        let service = EditorService(
            siteID: "bundled",
            baseURL: URL(string: "https://example.com")!,
            authHeader: "",
            logLevel: .debug
        )

        return (config, service)
    }
}

struct AppError: LocalizedError {
    let errorDescription: String
}

#Preview {
    AppRootView()
}
