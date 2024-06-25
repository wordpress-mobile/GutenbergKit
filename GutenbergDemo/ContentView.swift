import SwiftUI
import GutenbergKit

struct ContentView: View {
    var body: some View {
        NavigationView {
            EditorView()
        }
        .navigationTitle("Editor Demo")
    }
}

struct EditorView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> EditorViewController {
        let viewController = EditorViewController(service: .init(client: Client()))
        viewController.webView.isInspectable = true
        return viewController

    }

    func updateUIViewController(_ uiViewController: EditorViewController, context: Context) {
        // Do nothing
    }
}

struct Client: EditorNetworkingClient {
    func send(_ request: EditorNetworkRequest) async throws -> EditorNetworkResponse {
        throw URLError(.unknown)
    }
}

#Preview {
    ContentView()
}
