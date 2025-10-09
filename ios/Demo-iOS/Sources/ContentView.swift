import SwiftUI
import GutenbergKit

let editorURL: URL? = ProcessInfo.processInfo.environment["GUTENBERG_EDITOR_URL"].flatMap(URL.init)

struct ContentView: View {

    let remoteEditorConfigurations: [EditorConfiguration] = [.template]

    var body: some View {
        List {
            Section {
                NavigationLink {
                    EditorView(configuration: .default)
                } label: {
                    Text("Bundled editor")
                }
            }

            Section {
                ForEach(remoteEditorConfigurations, id: \.siteURL) { configuration in
                    NavigationLink {
                        EditorView(configuration: configuration)
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
}

private extension EditorConfiguration {

    static var template: Self {
        #warning("1. Update the siteURL and authHeader values below")
        #warning("2. Install the Jetpack plugin to the site")
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
