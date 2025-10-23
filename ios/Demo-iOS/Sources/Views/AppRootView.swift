import SwiftUI
import GutenbergKit
import AuthenticationServices
import WordPressAPI

struct AppRootView: View {
    @State private var selectedConfiguration: ConfigurationItem?
    @State private var configurations: [ConfigurationItem] = [.bundledEditor]
    @State private var siteUrlInput = ""
    @State private var authenticationManager = AuthenticationManager()
    @State private var configurationStorage = ConfigurationStorage()

    @State private var editorRemoteConfiguration: EditorConfiguration? = nil
    @State private var error: Error? = nil

    @AppStorage("isNativeInserterEnabled") private var isNativeInserterEnabled = false

    var body: some View {
        EditorList(isNativeInserterEnabled: $isNativeInserterEnabled, selectedConfiguration: $selectedConfiguration)
        .overlay {
            if let error {
                Text(error.localizedDescription)
            }
        }
        .fullScreenCover(item: $selectedConfiguration) { config in
            editorOverlay
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
    var editorOverlay: some View {
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
                    .setShouldUsePlugins(canUsePlugins)
                    .setSiteUrl(config.siteUrl)
                    .setSiteApiRoot(config.siteApiRoot)
                    .setAuthHeader(config.authHeader)
                    .setNativeInserterEnabled(isNativeInserterEnabled)
//                    .setLogLevel(.debug)
                    .build()

                await MainActor.run {
                    self.editorRemoteConfiguration = updatedConfiguration
                }
            } catch {
                self.error = error
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

#Preview {
    AppRootView()
}
