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
            } else if let error = viewModel.error {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                }
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

                if viewModel.postTypes.isEmpty {
                    HStack {
                        Text("Post Type")
                        Spacer()
                        ProgressView()
                    }
                } else {
                    Picker("Post Type", selection: $viewModel.selectedPostTypeDetails) {
                        ForEach(viewModel.postTypes, id: \.self) { postType in
                            Text(postType.name).tag(postType)
                        }
                    }

                    NavigationLink {
                        if let client = viewModel.client,
                           let configuration = viewModel.editorConfiguration {
                            PostsListView(
                                client: client,
                                postTypeDetails: viewModel.selectedPostTypeDetails,
                                editorConfiguration: configuration,
                                editorDependencies: viewModel.editorDependencies
                            )
                        }
                    } label: {
                        Text("Browse")
                    }
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

    var enableNativeInserter: Bool {
        get { editorConfiguration?.isNativeInserterEnabled ?? true }
        set {
            guard let config = editorConfiguration else { return }
            editorConfiguration = config.toBuilder()
                .setNativeInserterEnabled(newValue)
                .build()
        }
    }

    var enableNetworkLogging: Bool {
        get { editorConfiguration?.enableNetworkLogging ?? false }
        set {
            guard let config = editorConfiguration else { return }
            editorConfiguration = config.toBuilder()
                .setEnableNetworkLogging(newValue)
                .build()
        }
    }

    var postTypes: [PostTypeDetails] = []

    var selectedPostTypeDetails: PostTypeDetails {
        get { editorConfiguration?.postType ?? .post }
        set {
            guard let config = editorConfiguration else { return }
            editorConfiguration = config.toBuilder()
                .setPostType(newValue)
                .build()
            editorDependencies = nil
        }
    }

    var cacheBundleCount: Int?


    var error: Error?

    var configurationItem: ConfigurationItem

    var editorConfiguration: EditorConfiguration?

    var disableButtons: Bool = false

    var loadingProgress: EditorProgress?

    var editorDependencies: EditorDependencies?

    var client: WordPressAPI?

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
                    self.editorConfiguration = Self.applyDemoAppDefaults(to: .bundled)
                    self.postTypes = [.post, .page]
                case .localWordPress:
                    guard let credentials = LocalWordPressCredentials.load() else {
                        throw AppError(errorDescription: "Local WordPress not configured.\n\nRun 'make wp-env-start' from the project root to set up a local WordPress environment.")
                    }
                    let siteDetails = ConfiguredEditor(
                        name: "Local WordPress",
                        siteUrl: credentials.siteUrl,
                        siteApiRoot: credentials.siteApiRoot,
                        authHeader: credentials.authHeader
                    )
                    do {
                        let parsedApiRoot = try ParsedUrl.parse(input: siteDetails.siteApiRoot)
                        let configuration = URLSessionConfiguration.ephemeral
                        configuration.httpAdditionalHeaders = ["Authorization": siteDetails.authHeader]
                        let client = WordPressAPI(
                            urlSession: .init(configuration: configuration),
                            apiRootUrl: parsedApiRoot,
                            authentication: .none,
                        )
                        self.client = client

                        try await self.loadPostTypes()
                        let newConfiguration = try await self.loadConfiguration(for: siteDetails)
                        self.editorConfiguration = Self.applyDemoAppDefaults(to: newConfiguration)
                    } catch let urlError as URLError where urlError.code == .cannotConnectToHost || urlError.code == .networkConnectionLost || urlError.code == .timedOut {
                        throw AppError(errorDescription: "Could not connect to Local WordPress at localhost:8888.\n\nThe wp-env server may not be running. Start it with 'make wp-env-start'.")
                    }
                case .editorConfiguration(let siteDetails):
                    let parsedApiRoot = try ParsedUrl.parse(input: siteDetails.siteApiRoot)
                    let configuration = URLSessionConfiguration.ephemeral
                    configuration.httpAdditionalHeaders = ["Authorization": siteDetails.authHeader]
                    let client = WordPressAPI(
                        urlSession: .init(configuration: configuration),
                        apiRootUrl: parsedApiRoot,
                        authentication: .none,
                    )
                    self.client = client

                    try await self.loadPostTypes()
                    let newConfiguration = try await self.loadConfiguration(for: siteDetails)
                    self.editorConfiguration = Self.applyDemoAppDefaults(to: newConfiguration)
                }
            } catch {
                self.error = error
            }
        }
    }

    private static func applyDemoAppDefaults(to configuration: EditorConfiguration) -> EditorConfiguration {
        configuration.toBuilder()
            .setNativeInserterEnabled(true)
            .build()
    }

    /// Prepares the editor by caching all resources and preparing an `EditorDependencies` object to inject into the editor.
    /// Once this method is run, the editor should load instantly.
    @MainActor
    func prepareEditor() {
        guard let configuration = self.editorConfiguration else {
            preconditionFailure("Unable to prepare editor without editor configuration – the UI should prevent this")
        }

        let cacheInterval: TimeInterval = 86_400 // Cache for one day
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

        let apiRoot = try await client!.apiRoot.get().data

        let canUsePlugins = apiRoot.hasRoute(route: "/wpcom/v2/editor-assets")
        let canUseEditorStyles = apiRoot.hasRoute(route: "/wp-block-editor/v1/settings")

        return EditorConfigurationBuilder(
            postType: selectedPostTypeDetails,
            siteURL: URL(string: apiRoot.siteUrlString())!,
            siteApiRoot: URL(string: config.siteApiRoot)!
        )
        .setShouldUseThemeStyles(canUseEditorStyles)
        .setShouldUsePlugins(canUsePlugins)
        .setAuthHeader(config.authHeader)
        .setLogLevel(.debug)
        .build()
    }

    @MainActor
    private func loadPostTypes() async throws {
        guard let client = self.client else {
            self.postTypes = [.post, .page]
            return
        }

        guard self.postTypes.isEmpty else { return }

        let response = try await client.postTypes.listWithEditContext().data

        self.postTypes = response.postTypes
            .filter { (type, details) in
                switch type {
                case .post, .page:
                    return true
                case .custom:
                    break
                default:
                    return false
                }

                return details.viewable && details.visibility.showUi
            }
            .values
            .map { postType in
                PostTypeDetails(
                    postType: postType.slug,
                    restBase: postType.restBase,
                    restNamespace: postType.restNamespace
                )
            }
            .sorted(using: KeyPathComparator(\.postType))

        if let firstType = postTypes.first {
            self.selectedPostTypeDetails = firstType
        }
    }

    func buildAndLoadConfiguration(navigation: Navigation) {
        guard let configuration = self.editorConfiguration else {
            preconditionFailure("Unable to build configuration without editor configuration – the UI should prevent this")
        }

        let editor = RunnableEditor(
            configuration: configuration,
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

extension PostTypeDetails {
    var name: String {
        postType.capitalized
    }
}

#Preview("Bundled Editor") {
    NavigationStack {
        SitePreparationView(site: .bundledEditor)
    }
}
