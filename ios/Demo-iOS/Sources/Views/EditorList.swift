import SwiftUI

struct EditorList: View {

    @EnvironmentObject
    private var configurationStorage: ConfigurationStorage

    @State private var showAddDialog = false
    @State private var showDebugSettings = false
    @State private var showMediaProxyServer = false

    @State var configurationToDelete: ConfigurationItem?

    var body: some View {
        List {
            Section {
                NavigationLink("Standalone Editor") {
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
                Text("Editor without a WordPress site. No theme styles, media uploads, or plugins.")
            }

            Section {
                NavigationLink("Local WordPress (wp-env)") {
                    SitePreparationView(site: .localWordPress)
                }

                configuredEditors

                Button("Add WordPress Site") {
                    showAddDialog = true
                }
            } header: {
                Text("WordPress Sites")
            } footer: {
                Text("Editors connected to a WordPress site, enabling theme styles, media uploads, plugin support, etc.")
            }
        }
        .alert(
            "Delete WordPress Site?",
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
        .navigationDestination(isPresented: $showMediaProxyServer) {
            MediaProxyServerView()
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
                Menu {
                    Button {
                        showMediaProxyServer = true
                    } label: {
                        Label("Media Proxy Server", systemImage: "server.rack")
                    }

                    Button {
                        showDebugSettings = true
                    } label: {
                        Label("Debug Settings", systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
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
