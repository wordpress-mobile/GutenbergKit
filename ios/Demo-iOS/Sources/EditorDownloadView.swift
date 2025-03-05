import SwiftUI
import GutenbergKit

struct EditorDownloadView: View {

    class ViewModel: ObservableObject {
        @Published
        var downloadProgress: Double = 0

        @Published
        var siteUrl: String = "http://localhost"

        @Published
        var error: Error? = nil

        func download() {
            Task {

                let url = URL(string: siteUrl)!
                    .appendingPathComponent("wp-json")
                    .appendingPathComponent("__experimental")
                    .appendingPathComponent("wp-block-editor")
                    .appendingPathComponent("v1")
                    .appendingPathComponent( "editor-assets" )

                print("Downloading from \(url)")

                do {
                    self.error = nil

                    try await EditorLibrary.shared.downloadManifest(from: url) { progress in
                        self.downloadProgress = Double(progress.fractionCompleted)
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

            Button("Download") {
                self.viewModel.download()
            }

            ProgressView(value: viewModel.downloadProgress).progressViewStyle(.linear)
        }
    }
}

#Preview {
    EditorDownloadView()
}
