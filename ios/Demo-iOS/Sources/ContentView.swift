import SwiftUI
import GutenbergKit

let editorURL: URL? = ProcessInfo.processInfo.environment["GUTENBERG_EDITOR_URL"].flatMap(URL.init)

struct ContentView: View {

    let remoteEditorConfigurations: [EditorConfiguration] = [.template]

    @State private var isShowingDefaultEditor = false
    
    // Configuration settings
    @AppStorage("enableNativeBlockInserter") private var enableNativeBlockInserter = true
    @AppStorage("enablePlugins") private var enablePlugins = false
    @AppStorage("hideTitle") private var hideTitle = false
    @AppStorage("autoFocusOnLoad") private var autoFocusOnLoad = true
    @AppStorage("themeStyles") private var themeStyles = true

    var body: some View {
        List {
            Section {
                Button {
                    isShowingDefaultEditor = true
                } label: {
                    Text("Bundled Editor")
                }
            }
            
            Section {
                Toggle("Native Block Inserter", isOn: $enableNativeBlockInserter)
                Toggle("Enable Plugins", isOn: $enablePlugins)
                Toggle("Hide Title", isOn: $hideTitle)
                Toggle("Auto Focus on Load", isOn: $autoFocusOnLoad)
                Toggle("Theme Styles", isOn: $themeStyles)
            } header: {
                Text("Configuration")
            } footer: {
                Button("Reset") {
                    enableNativeBlockInserter = true
                    enablePlugins = false
                    hideTitle = false
                    autoFocusOnLoad = true
                    themeStyles = true
                }
            }

            Section {
                ForEach(remoteEditorConfigurations, id: \.siteURL) { configuration in
                    NavigationLink {
                        EditorView(configuration: configureWithSettings(configuration))
                    } label: {
                        Text(URL(string: configuration.siteURL)?.host ?? configuration.siteURL)
                    }
                }

                if remoteEditorConfigurations.isEmpty {
                    Text("Add `EditorConfiguration` instances to the `remoteEditorConfigurations` array to launch remote editors here.")
                }
            } header: {
                Text("Remote Editors")
            } footer: {
                if ProcessInfo.processInfo.environment["GUTENBERG_EDITOR_REMOTE_URL"] != nil {
                    Text("Note: The editor is backed by the dev server created by `make dev-server-remote`.")
                } else {
                    Text("Note: The editor is backed by the compiled web app created by `make build`.")
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingDefaultEditor) {
            NavigationView {
                EditorView(configuration: configureWithSettings(.default))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        NSLog("Start to fetch assets")
                        for configuration in remoteEditorConfigurations {
                            let library = EditorAssetsLibrary(configuration: configuration)
                            do {
                                try await library.fetchAssets()
                            } catch {
                                NSLog("Failed to fetch assets for \(configuration.siteURL): \(error)")
                            }
                        }
                        NSLog("Done fetching assets")
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }
    
    // Helper function to apply settings to configuration
    private func configureWithSettings(_ configuration: EditorConfiguration) -> EditorConfiguration {
        var config = configuration
        config.enableNativeBlockInserter = enableNativeBlockInserter
        config.plugins = enablePlugins
        config.hideTitle = hideTitle
        config.autoFocusOnLoad = autoFocusOnLoad
        config.themeStyles = themeStyles
        return config
    }
}

private extension EditorConfiguration {

    static var template: Self {
        var configuration = EditorConfiguration.default

        configuration.siteURL = "https://modify-me.com"
        configuration.authHeader = "Insert the Authorization header value here"

        // DO NOT CHANGE the properties below
        configuration.siteApiRoot = "\(configuration.siteURL)/wp-json/"
        configuration.editorAssetsEndpoint = URL(string: configuration.siteApiRoot)!.appendingPathComponent("wpcom/v2/editor-assets")
        // The `plugins: true` is necessary for the editor to use 'remote.html'
        configuration.plugins = true

        return configuration
    }

}

#Preview {
    ContentView()
}
