import SwiftUI
import GutenbergKit

struct EditorView: View {
    private let configuration: EditorConfiguration
    @State private var isModalDialogOpen = false
    @State private var currentDialogType: String?
    @Environment(\.dismiss) private var dismiss

    init(configuration: EditorConfiguration) {
        self.configuration = configuration
    }

    var body: some View {
        _EditorView(
            configuration: configuration,
            isModalDialogOpen: $isModalDialogOpen,
            currentDialogType: $currentDialogType
        )
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        dismiss()
                    }, label: {
                        Image(systemName: "xmark")
                    })
                    .disabled(isModalDialogOpen)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: {}, label: {
                        Image(systemName: "arrow.uturn.backward")
                    }).disabled(true)
                    Button(action: {}, label: {
                        Image(systemName: "arrow.uturn.forward")
                    }).disabled(true)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    moreMenu
                        .disabled(isModalDialogOpen)
                }
            }
    }

    private var moreMenu: some View {
        Menu {
            Section {
                Button(action: {}, label: {
                    Label("Code Editor", systemImage: "curlybraces")
                }).disabled(true)
                Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                    Label("Preview", systemImage: "safari")
                }).disabled(true)
                Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                    Label("Revisions (42)", systemImage: "clock.arrow.circlepath")
                }).disabled(true)
                Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                    Label("Post Settings", systemImage: "gearshape")
                }).disabled(true)
                Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                    Label("Help", systemImage: "questionmark.circle")
                }).disabled(true)
            }
            Section {
                Text("Blocks: 4, Words: 8, Characters: 15")
            } header: {

            }
        } label: {
            Image(systemName: "ellipsis")
        }
    }
}

private struct _EditorView: UIViewControllerRepresentable {
    private let configuration: EditorConfiguration
    @Binding var isModalDialogOpen: Bool
    @Binding var currentDialogType: String?

    init(
        configuration: EditorConfiguration,
        isModalDialogOpen: Binding<Bool>,
        currentDialogType: Binding<String?>
    ) {
        self.configuration = configuration
        self._isModalDialogOpen = isModalDialogOpen
        self._currentDialogType = currentDialogType
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isModalDialogOpen: $isModalDialogOpen,
            currentDialogType: $currentDialogType
        )
    }

    func makeUIViewController(context: Context) -> EditorViewController {
        let viewController = EditorViewController(configuration: configuration)
        viewController.delegate = context.coordinator

        if #available(iOS 16.4, *) {
            viewController.webView.isInspectable = true
        }
        viewController.startEditorSetup()
        return viewController
    }

    func updateUIViewController(_ uiViewController: EditorViewController, context: Context) {
        // Do nothing
    }

    @MainActor
    class Coordinator: NSObject, EditorViewControllerDelegate {
        @Binding var isModalDialogOpen: Bool
        @Binding var currentDialogType: String?

        init(
            isModalDialogOpen: Binding<Bool>,
            currentDialogType: Binding<String?>
        ) {
            self._isModalDialogOpen = isModalDialogOpen
            self._currentDialogType = currentDialogType
        }

        // MARK: - EditorViewControllerDelegate

        func editorDidLoad(_ viewContoller: EditorViewController) {
            // No-op for demo
        }

        func editor(_ viewContoller: EditorViewController, didDisplayInitialContent content: String) {
            // No-op for demo
        }

        func editor(_ viewContoller: EditorViewController, didEncounterCriticalError error: Error) {
            // No-op for demo
        }

        func editor(_ viewController: EditorViewController, didUpdateContentWithState state: EditorState) {
            // No-op for demo
        }

        func editor(_ viewController: EditorViewController, didUpdateHistoryState state: EditorState) {
            // No-op for demo
        }

        func editor(_ viewController: EditorViewController, didUpdateFeaturedImage mediaID: Int) {
            // No-op for demo
        }

        func editor(_ viewController: EditorViewController, didLogException error: GutenbergJSException) {
            // No-op for demo
        }

        func editor(_ viewController: EditorViewController, didRequestMediaFromSiteMediaLibrary config: OpenMediaLibraryAction) {
            // No-op for demo
        }

        func editor(_ viewController: EditorViewController, didTriggerAutocompleter type: String) {
            // No-op for demo
        }

        func editor(_ viewController: EditorViewController, didOpenModalDialog dialogType: String) {
            isModalDialogOpen = true
            currentDialogType = dialogType
        }

        func editor(_ viewController: EditorViewController, didCloseModalDialog dialogType: String) {
            isModalDialogOpen = false
            currentDialogType = nil
        }
    }
}

#Preview {
    NavigationStack {
        EditorView(configuration: .default)
    }
}
