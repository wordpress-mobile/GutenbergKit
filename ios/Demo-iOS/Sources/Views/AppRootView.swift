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

    @State private var editorRemoteConfiguration: EditorConfiguration? = nil

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
            case .bundledEditor: editorRemoteConfiguration = createBundledConfiguration()
            case .remoteEditor(let config): self.loadRemoteEditor(for: config)
            case .none: self.editorRemoteConfiguration = nil
            }
        }
    }

    @ViewBuilder
    var editor: some View {
        NavigationView {
            if let editorRemoteConfiguration {
                EditorView(configuration: editorRemoteConfiguration)
            } else {
                ProgressView("Preparing Editor")
            }
        }
    }

    private func loadRemoteEditor(for config: RemoteEditorConfiguration) {
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

                let updatedConfiguration = EditorConfigurationBuilder()
                    .setShouldUseThemeStyles(canUseEditorStyles)
                    .setShouldUsePlugins(false )
                    .setSiteUrl(config.siteUrl)
                    .setSiteApiRoot(config.siteApiRoot)
                    .setAuthHeader(config.authHeader)
                    .setNativeInserterEnabled(isNativeInserterEnabled)
                    .setLogLevel(.debug)
                    .build()

                self.editorRemoteConfiguration = updatedConfiguration
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

    private func createBundledConfiguration() -> EditorConfiguration {
        EditorConfigurationBuilder()
            .setShouldUsePlugins(false)
            .setSiteUrl("")
            .setSiteApiRoot("")
            .setAuthHeader("")
            .setNativeInserterEnabled(isNativeInserterEnabled)
            .build()
    }
}

struct AppError: LocalizedError {
    let errorDescription: String
}

#Preview {
    AppRootView()
}
