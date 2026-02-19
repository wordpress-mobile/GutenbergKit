import SwiftUI

struct EditorList: View {

    @EnvironmentObject
    private var configurationStorage: ConfigurationStorage

    @State private var showAddDialog = false
    @State private var showDebugSettings = false

    @State var configurationToDelete: ConfigurationItem?

    var body: some View {
        List {
            Section {
                NavigationLink("Default Editor") {
                    SitePreparationView(site: .bundledEditor)

                }
            } header: {
                if ProcessInfo.processInfo.environment["GUTENBERG_EDITOR_URL"] != nil
                    {
                    Text("Note: Editors are using the dev server started with `make dev-server`.")
                        .textCase(nil)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Note: Editors are using the compiled web app built with `make build`.")
                        .textCase(nil)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } footer: {
            Text("Default editor without site configuration.")
            }

            Section {
                NavigationLink("Local WordPress") {
                    SitePreparationView(site: .localWordPress)
                }
            } header: {
                Text("Local Development")
            } footer: {
                Text("Requires wp-env at localhost:8888. Run `make wp-env-start` to set up.")
            }

            Section {
                configuredEditors

                Button("Add Editor Configuration") {
                    showAddDialog = true
                }
            } header: {
                Text("Editor Configurations")
            } footer: {
                Text("Editors with site configuration; enabling media uploads, plugin support, etc.")
            }
        }
        .alert(
            "Delete Editor Configuration?",
            isPresented: Binding(
                get: { configurationToDelete != nil },
                set: { if !$0 { configurationToDelete = nil } }
            ),
            presenting: configurationToDelete
        ) { config in
            Button("Delete", role: .destructive) {
                self.configurationStorage.deleteConfiguration(config)
                configurationToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                configurationToDelete = nil
            }
        } message: { config in
            Text("Are you sure you want to delete \"\(config.displayName)\"?")
        }
        .sheet(isPresented: $showAddDialog) {
            AddSiteView()
        }
        .sheet(isPresented: $showDebugSettings) {
            NavigationStack {
                DebugSettingsView()
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

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showDebugSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }.onAppear {
            configurationStorage.loadConfigurations()
        }
    }

    var configuredEditors: some View {
        ForEach(configurationStorage.editorConfigurations.filter {
            if case .editorConfiguration = $0 { return true }
            return false
        }) { config in
            NavigationLink(config.displayName, value: config)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    configurationToDelete = config
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}
