import SwiftUI
import GutenbergKit
import WebKit

#if os(iOS) || os(visionOS)
typealias ViewControllerRepresentable = UIViewControllerRepresentable
#elseif os(macOS)
typealias ViewControllerRepresentable = NSViewControllerRepresentable
#endif

struct EditorView: View {
    let viewModel = EditorViewModel(
        initialTitle: "",
        initialContent: "",
        siteURL: "",
        siteApiRoot: "",
        siteApiNamespace: "",
        authHeader: "",
        type: ""
    )

    var body: some View {
        EditorViewWrapper(viewModel: viewModel)
            .toolbar {
                #if canImport(UIKit)
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button(action: {}, label: {
                        Image(systemName: "xmark")
                    })
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: {}, label: {
                        Image(systemName: "arrow.uturn.backward")
                    })
                    Button(action: {}, label: {
                        Image(systemName: "arrow.uturn.forward")
                    }).disabled(true)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: {}, label: {
                        Image(systemName: "safari")
                    })

                    moreMenu
                }
                #endif
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
    }
}

private struct EditorViewWrapper: ViewControllerRepresentable {
    let viewModel: EditorViewModel

    private func makeViewController() -> EditorViewController {
        let viewController = EditorViewController(
            viewModel: viewModel,
            service: .init(client: Client())
        )
//        viewController.developmentEnvironmentUrl = URL(string:  "http://localhost:5173/")!
        viewController.isDebuggingEnabled = true

        return viewController
    }

    #if canImport(UIKit)
    func makeUIViewController(context: Context) -> EditorViewController {
        makeViewController()
    }

    func updateUIViewController(_ uiViewController: EditorViewController, context: Context) {
        // Do nothing
    }
    #endif

    #if canImport(AppKit)
    func makeNSViewController(context: Context) -> EditorViewController {
        makeViewController()
    }

    func updateNSViewController(_ nsViewController: EditorViewController, context: Context) {
        // Do nothing
    }
    #endif
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
