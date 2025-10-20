import SwiftUI
import GutenbergKit

struct ContentView: View {
    private let remoteEditors: [RemoteEditorRow] = [
        .init(id: "template", configuration: .template)
    ]

    @State private var isDefaultEditorShown = false
    @State private var selectedRemoteEditor: RemoteEditorRow?

    @AppStorage("isNativeInserterEnabled") private var isNativeInserterEnabled = false

    var body: some View {
        List {
            Section {
                Button("Bundled Editor") {
                    isDefaultEditorShown = true
                }
            }

            Section {
                ForEach(remoteEditors) { editor in
                    Button(editor.title) {
                        selectedRemoteEditor = editor
                    }
                }

                if remoteEditors.isEmpty {
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

            Section("Configuration") {
                Toggle("Native Inserter", isOn: $isNativeInserterEnabled)
            }
        }
        .fullScreenCover(isPresented: $isDefaultEditorShown) {
            NavigationView {
                EditorView(configuration: preconfigure(.default))
            }
        }
        .fullScreenCover(item: $selectedRemoteEditor) { editor in
            NavigationView {
                EditorView(configuration: preconfigure(editor.configuration))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        NSLog("Start to fetch assets")
                        for editor in remoteEditors {
                            let library = EditorAssetsLibrary(configuration: editor.configuration)
                            do {
                                try await library.fetchAssets()
                            } catch {
                                NSLog("Failed to fetch assets for \(editor.configuration.siteURL): \(error)")
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

    private func preconfigure(_ configuration: EditorConfiguration) -> EditorConfiguration {
        configuration
            .toBuilder()
            .setNativeInserterEnabled(isNativeInserterEnabled)
            .build()
    }
}

private struct RemoteEditorRow: Identifiable {
    let id: String
    let configuration: EditorConfiguration

    var title: String {
        URL(string: configuration.siteURL)?.host ?? configuration.siteURL
    }
}

private extension EditorConfiguration {

    static var template: Self {
        // Steps:
        // 1. Update the siteURL and authHeader values below
        // 2. Install the Jetpack plugin to the site
        let siteUrl: String = "https://modify-me.com"
        let authHeader: String = "Insert the Authorization header value here"
        let siteApiRoot: String = "\(siteUrl)/wp-json/"

        let configuration = EditorConfigurationBuilder()
            .setSiteUrl(siteUrl)
            .setAuthHeader(authHeader)
            .setSiteApiRoot(siteApiRoot)
            .setEditorAssetsEndpoint(URL(string: siteApiRoot)!.appendingPathComponent("wpcom/v2/editor-assets"))
            .setShouldUsePlugins(true)

        return configuration.build()
    }

}

#Preview {
    ContentView()
}
