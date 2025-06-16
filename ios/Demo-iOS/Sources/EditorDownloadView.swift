import SwiftUI
import GutenbergKit

struct EditorDownloadView: View {

    class ViewModel: ObservableObject {
        @Published
        var downloadProgress: Progress? = nil

        @Published
        var siteUrl: String = "http://localhost"

        @Published
        var username: String = ""

        @Published
        var applicationPassword: String = ""

        @Published
        var error: Error? = nil

        func download() {
            Task { @MainActor in

                let url = URL(string: siteUrl)!
                    .appendingPathComponent("wp-json")
                    .appendingPathComponent("__experimental")
                    .appendingPathComponent("wp-block-editor")
                    .appendingPathComponent("v1")
                    .appendingPathComponent( "editor-assets" )

                print("Downloading from \(url)")

                do {
                    self.error = nil

                    var request = URLRequest(url: url)
                    request.setValue(
                        "Basic " + "\(username):\(applicationPassword)"
                            .data(using: .utf8)!.base64EncodedString(),
                        forHTTPHeaderField: "Authorization"
                    )
                    try await EditorLibrary.shared.downloadManifest(from: request) { [weak self] progress in
                        DispatchQueue.main.async {
                            self?.downloadProgress = progress
                        }
                    }
                } catch {
                    self.error = error
                }
            }
        }
    }

    @StateObject
    var viewModel = ViewModel()

    var body: some View {
        Form {
            if let error = viewModel.error {
                Text("Error: \(error.localizedDescription)")
            }

            TextField(text: $viewModel.siteUrl, prompt: Text("Site URL")) {
                Text("Site URL")
            }
            .keyboardType(.URL)
            .autocapitalization(.none)

            TextField(text: $viewModel.username, prompt: Text("Username")) {
                Text("Username")
            }
            .keyboardType(.alphabet)
            .autocapitalization(.none)

            TextField(text: $viewModel.applicationPassword, prompt: Text("Application password")) {
                Text("Application password")
            }
            .keyboardType(.alphabet)
            .autocapitalization(.none)

            Button("Download") {
                self.viewModel.download()
            }

            if let progress = viewModel.downloadProgress {
                ProgressView(progress).progressViewStyle(.linear)
            }

        }
    }
}

#Preview {
    EditorDownloadView()
}
