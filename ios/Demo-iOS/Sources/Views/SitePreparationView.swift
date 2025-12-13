import SwiftUI
import WordPressAPI
import GutenbergKit

struct SitePreparationView: View {

    @Environment(\.navigation)
    private var navigation

    @State
    private var viewModel: SitePreparationViewModel

    init(site: ConfigurationItem) {
        self.viewModel = SitePreparationViewModel(configurationItem: site)
    }

    var body: some View {
        Group {
            if let configuration = self.viewModel.editorConfiguration {
                loadedView(configuration: configuration)
            } else {
                ProgressView("Loading Site Configuration")
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if self.viewModel.editorConfiguration != nil {
                    Button("Start") {
                        self.viewModel.buildAndLoadConfiguration(navigation: navigation)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Editor Configuration")
        .onAppear {
            self.viewModel.startLoading()
        }
    }

    func loadedView(configuration: EditorConfiguration) -> some View {
        Form {

            if viewModel.editorDependencies != nil {
                Text("Editor Dependencies Loaded – the editor should load instantly")
            } else {
                Text("Editor Dependencies Missing – the editor will need to load them when it starts")
            }

            Section("Feature Configuration") {
                Toggle("Enable Native Inserter", isOn: $viewModel.enableNativeInserter)
                Toggle("Enable Network Logging", isOn: $viewModel.enableNetworkLogging)

                // TODO: Loading this from the server would allow us to validate Custom Post Type support
                Picker("Post Type", selection: $viewModel.postType) {
                    Text("Post").tag("post")
                    Text("Page").tag("page")
                }
            }

            if let editorConfiguration = viewModel.editorConfiguration {
                Section("Editor Configuration Details") {
                    KeyValueRow(key: "Site URL", value: editorConfiguration.siteURL.absoluteString)
                    KeyValueRow(key: "API Root", value: editorConfiguration.siteApiRoot.absoluteString)
                    KeyValueRow(key: "Supports Block Assets", value: editorConfiguration.shouldUsePlugins)
                    KeyValueRow(key: "Supports Theme Styles", value: editorConfiguration.shouldUseThemeStyles)
                }
            }

            self.preloadSection

            if let error = viewModel.error {
                Section("Error") {
                    Text(error.localizedDescription)
                }
            }
        }
    }

    var preloadSection: some View {
        Section {
            Button("Prepare Editor") {
                withAnimation {
                    self.viewModel.prepareEditor()
                }
            }.disabled(self.viewModel.disableButtons)

            Button("Prepare Editor Ignoring Cache") {
                withAnimation {
                    self.viewModel.prepareEditorFromScratch()
                }
            }.disabled(self.viewModel.disableButtons)

            Button("Clear Preload Cache") {
                withAnimation {
                    self.viewModel.resetEditorCaches()
                }
            }.disabled(self.viewModel.disableButtons)
        } header: {
            Text("Local Caches")
        } footer: {
            if let progress = self.viewModel.loadingProgress {
                ProgressView(value: progress.fractionCompleted)
            }
        }.task {
            await self.viewModel.countAssetBundles()
        }
    }
}

@Observable
class SitePreparationViewModel {

    var enableNativeInserter: Bool = true

    var enableNetworkLogging: Bool = false

    var postType: String = "post"

    var cacheBundleCount: Int?

    var isPreparing: Bool = false

    var isPrepared: Bool = false

    var error: Error?

    var configurationItem: ConfigurationItem

    var editorConfiguration: EditorConfiguration?

    var disableButtons: Bool = false

    var loadingProgress: EditorProgress?

    var editorDependencies: EditorDependencies?

    private var taskHandle: Task<Void, Never>?

    init(configurationItem: ConfigurationItem) {
        self.configurationItem = configurationItem
    }

    @MainActor
    func startLoading() {
        self.taskHandle = Task {
            do {
                switch configurationItem {
                case .bundledEditor:
                    self.editorConfiguration = .bundled
                case .editorConfiguration(let siteDetails):
                    let newConfiguration = try await self.loadConfiguration(for: siteDetails)
                    self.editorConfiguration = newConfiguration
                }
            } catch {
                self.error = error
            }
        }
    }

    /// Prepares the editor by caching all resources and preparing an `EditorDependencies` object to inject into the editor.
    /// Once this method is run, the editor should load instantly.
    @MainActor
    func prepareEditor() {
        guard let configuration = self.editorConfiguration else {
            preconditionFailure("Unable to prepare editor without editor configuration – the UI should prevent this")
        }

        let cacheInterval: TimeInterval = 86_400  // Cache for one day
        self.prepareEditor(with: EditorService(configuration: configuration, cachePolicy: .maxAge(cacheInterval)))
    }

    /// Prepares the editor by caching all resources and preparing an `EditorDependencies` object to inject into the editor.
    /// Once this method is run, the editor should load instantly.
    @MainActor
    func prepareEditorFromScratch() {
        guard let configuration = self.editorConfiguration else {
            preconditionFailure("Unable to prepare editor without editor configuration – the UI should prevent this")
        }

        self.prepareEditor(with: EditorService(configuration: configuration, cachePolicy: .ignore))
    }

    private func prepareEditor(with editorService: EditorService) {
        self.taskHandle = Task {
            self.disableButtons = true
            defer {
                self.loadingProgress = nil
                self.disableButtons = false
            }

            do {
                self.editorDependencies = try await editorService.prepare { @MainActor progress in
                    self.loadingProgress = progress
                }

                await self.countAssetBundles()

            } catch {
                self.error = error
            }
        }

    }

    /// Clears all local editor data, forcing the loading functions to run the next time the editor starts up. This is useful for testing the built-in
    /// editor loading code.
    func resetEditorCaches() {
        guard let configuration = self.editorConfiguration else {
            preconditionFailure("Unable to prepare editor without editor configuration – the UI should prevent this")
        }

        self.taskHandle = Task {
            do {
                self.disableButtons = true
                defer { self.disableButtons = false }

                self.editorDependencies = nil

                let editorService = EditorService(configuration: configuration)
                try await editorService.purge()

                await self.countAssetBundles()
            } catch {
                self.error = error
            }
        }
    }

    func countAssetBundles() async {
        do {
            guard let editorConfiguration else {
                self.cacheBundleCount = 0
                return
            }

            let editorService = EditorService(configuration: editorConfiguration)
            self.cacheBundleCount = try await editorService.fetchAssetBundleCount()
        } catch {
            self.error = error
        }
    }

    @MainActor
    private func loadConfiguration(for config: ConfiguredEditor) async throws -> EditorConfiguration {
        let parsedApiRoot = try ParsedUrl.parse(input: config.siteApiRoot)
        let client = WordPressAPI(
            urlSession: .shared,
            apiRootUrl: parsedApiRoot,
            authentication: .authorizationHeader(token: config.authHeader)
        )

        let apiRoot = try await client.apiRoot.get().data

        let canUsePlugins = apiRoot.hasRoute(route: "/wpcom/v2/editor-assets")
        let canUseEditorStyles = apiRoot.hasRoute(route: "/wp-block-editor/v1/settings")

        return EditorConfigurationBuilder(
            postType: "post",
            siteURL: URL(string: apiRoot.siteUrlString())!,
            siteApiRoot: parsedApiRoot.asURL()
        )
        .setShouldUseThemeStyles(canUseEditorStyles)
        .setShouldUsePlugins(canUsePlugins)
        .setAuthHeader(config.authHeader)
        .setLogLevel(.debug)
        .setEnableNetworkLogging(true)
        .build()
    }

    private func buildConfiguration() -> EditorConfiguration {
        guard let editorConfiguration = self.editorConfiguration else {
            preconditionFailure("Cannot build configuration as it is not loaded yet")
        }

        return editorConfiguration.toBuilder()
            .setEnableNetworkLogging(self.enableNetworkLogging)
            .setNativeInserterEnabled(self.enableNativeInserter)
            .setPostType(self.postType)
            .build()
    }

    func buildAndLoadConfiguration(navigation: Navigation) {
        let editor = RunnableEditor(
            configuration: buildConfiguration(),
            dependencies: self.editorDependencies
        )

        navigation.present(editor)
    }
}

struct KeyValueRow: View {

    enum Value {
        case string(String)
        case bool(Bool)
    }

    let key: String
    let value: Value

    init(key: String, value: String) {
        self.key = key
        self.value = .string(value)
    }

    init(key: String, value: Bool) {
        self.key = key
        self.value = .bool(value)
    }

    var body: some View {
        switch self.value {
        case .string(let string):
            VStack(alignment: .leading) {
                Text(key).font(.caption2).foregroundStyle(Color.secondary)
                Text(string)
            }
        case .bool(let bool):
            HStack {
                Text(key)
                Spacer()
                Image(systemName: bool ? "checkmark.circle" : "xmark.circle")
                    .foregroundStyle(bool ? Color.green : Color.red)
            }
        }
    }
}

#Preview("Bundled Editor") {
    NavigationStack {
        SitePreparationView(site: .bundledEditor)
    }
}
