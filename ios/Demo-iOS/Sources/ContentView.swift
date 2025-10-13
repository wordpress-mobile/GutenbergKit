import SwiftUI
import GutenbergKit
import AuthenticationServices

struct ContentView: View {
    @State private var selectedConfiguration: ConfigurationItem?
    @State private var configurations: [ConfigurationItem] = [.bundledEditor]
    @State private var showAddDialog = false
    @State private var siteUrlInput = ""
    @State private var authenticationManager = AuthenticationManager()
    @State private var configurationStorage = ConfigurationStorage()
    @State private var configurationToDelete: ConfigurationItem?

    @AppStorage("isNativeInserterEnabled") private var isNativeInserterEnabled = false

    var body: some View {
        List {
            Section {
                ForEach(configurations) { config in
                    Button(config.displayName) {
                        selectedConfiguration = config
                    }
                    .swipeActions(edge: .trailing) {
                        if case .remoteEditor = config {
                            Button(role: .destructive) {
                                configurationToDelete = config
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("Editors")
            } footer: {
                if ProcessInfo.processInfo.environment["GUTENBERG_EDITOR_REMOTE_URL"] != nil {
                    Text("Note: The editor is backed by the dev server created by `make dev-server` and `make dev-server-remote`.")
                } else {
                    Text("Note: The editor is backed by the compiled web app created by `make build`.")
                }
            }

            Section("Configuration") {
                Toggle("Native Inserter", isOn: $isNativeInserterEnabled)
            }
        }
        .fullScreenCover(item: $selectedConfiguration) { config in
            NavigationView {
                EditorView(configuration: preconfigure(createEditorConfiguration(for: config)))
            }
        }
        .navigationTitle("GutenbergKit")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddDialog = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddDialog) {
            AddSiteView(
                siteUrl: $siteUrlInput,
                authenticationManager: authenticationManager,
                onAdd: { config in
                    configurations.append(.remoteEditor(config))
                    configurationStorage.saveConfigurations(configurations)
                    showAddDialog = false
                    siteUrlInput = ""
                },
                onCancel: {
                    showAddDialog = false
                    siteUrlInput = ""
                }
            )
        }
        .onAppear {
            loadConfigurations()
        }
        .alert(
            "Delete Remote Editor?",
            isPresented: Binding(
                get: { configurationToDelete != nil },
                set: { if !$0 { configurationToDelete = nil } }
            ),
            presenting: configurationToDelete
        ) { config in
            Button("Delete", role: .destructive) {
                deleteConfiguration(config)
                configurationToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                configurationToDelete = nil
            }
        } message: { config in
            Text("Are you sure you want to delete \"\(config.displayName)\"?")
        }
    }

    private func preconfigure(_ configuration: EditorConfiguration) -> EditorConfiguration {
        configuration
            .toBuilder()
            .setNativeInserterEnabled(isNativeInserterEnabled)
            .build()
    }

    private func loadConfigurations() {
        let saved = configurationStorage.loadConfigurations()
        configurations = [.bundledEditor] + saved
    }

    private func deleteConfiguration(_ config: ConfigurationItem) {
        configurations.removeAll { $0.id == config.id }
        configurationStorage.saveConfigurations(configurations)
    }

    private func createEditorConfiguration(for item: ConfigurationItem) -> EditorConfiguration {
        switch item {
        case .bundledEditor:
            return createBundledConfiguration()
        case .remoteEditor(let config):
            return createRemoteConfiguration(config)
        }
    }

    private func createBundledConfiguration() -> EditorConfiguration {
        EditorConfigurationBuilder()
            .setShouldUsePlugins(false)
            .setSiteUrl("")
            .setSiteApiRoot("")
            .setAuthHeader("")
            .build()
    }

    private func createRemoteConfiguration(_ config: RemoteEditorConfiguration) -> EditorConfiguration {
        EditorConfigurationBuilder()
            .setShouldUsePlugins(true)
            .setSiteUrl(config.siteUrl)
            .setSiteApiRoot(config.siteApiRoot)
            .setAuthHeader(config.authHeader)
            .build()
    }
}

#Preview {
    ContentView()
}
