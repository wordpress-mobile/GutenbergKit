import SwiftUI
import GutenbergKit

private struct DialogVisible: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var dialogVisible: Bool {
        get { self[DialogVisible.self] }
        set { self[DialogVisible.self] = newValue }
    }
}

struct EditorView: View {
    var editorURL: URL?
    @State private var dialogVisible = false

    var body: some View {
        _EditorView(editorURL: editorURL, dialogVisible: $dialogVisible)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button(action: {}, label: {
                        Image(systemName: "xmark")
                    }).accessibilityHidden(dialogVisible)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: {}, label: {
                        Image(systemName: "arrow.uturn.backward")
                    }).accessibilityHidden(dialogVisible)
                    Button(action: {}, label: {
                        Image(systemName: "arrow.uturn.forward")
                    }).disabled(true).accessibilityHidden(dialogVisible)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: {}, label: {
                        Image(systemName: "safari")
                    }).accessibilityHidden(dialogVisible)

                    moreMenu.environment(\.dialogVisible, dialogVisible)
                }
            }
    }

    private var moreMenu: some View {
        Menu {
            Section {
                Button(action: {}, label: {
                    Label("Code Editor", systemImage: "curlybraces")
                })
                Button(action: {}, label: {
                    Label("Outline", systemImage: "list.bullet.indent")
                })
                Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                    Label("Preview", systemImage: "safari")
                })
            }
            Section {
                Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                    Label("Revisions (42)", systemImage: "clock.arrow.circlepath")
                })
                Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                    Label("Post Settings", systemImage: "gearshape")
                })

                Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                    Label("Help", systemImage: "questionmark.circle")
                })
            }
            Section {
                Text("Blocks: 4, Words: 8, Characters: 15")
            } header: {

            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .tint(Color.primary)
        .accessibilityHidden(dialogVisible)
    }
}

private struct _EditorView: UIViewControllerRepresentable {
    var editorURL: URL?
    @Binding var dialogVisible: Bool

    func makeUIViewController(context: Context) -> EditorViewController {
        let viewController = EditorViewController(service: .init(client: Client()))
        viewController.editorURL = editorURL
        viewController.dialogVisible = $dialogVisible
        if #available(iOS 16.4, *) {
            viewController.webView.isInspectable = true
        }
        return viewController
    }

    func updateUIViewController(_ uiViewController: EditorViewController, context: Context) {
        uiViewController.dialogVisible = $dialogVisible
    }
}

struct Client: EditorNetworkingClient {
    func send(_ request: EditorNetworkRequest) async throws -> EditorNetworkResponse {
        throw URLError(.unknown)
    }
}

#Preview {
    NavigationStack {
        EditorView()
//        EditorView(editorURL: URL(string: "http://localhost:5173/")!)
    }
}
