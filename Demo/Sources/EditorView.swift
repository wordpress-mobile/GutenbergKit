import SwiftUI
import GutenbergKit

struct EditorView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> EditorViewController {
        EditorViewController(service: .init(client: Client()))
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
    EditorView()
}
