import SwiftUI
import GutenbergKit

struct EditorView: View {
    private let configuration: EditorConfiguration
    @State private var isModalDialogOpen = false
    @State private var hasUndo = false
    @State private var hasRedo = false
    @State private var editorViewController: EditorViewController?
    @Environment(\.dismiss) private var dismiss

    init(configuration: EditorConfiguration) {
        self.configuration = configuration
    }

    var body: some View {
        _EditorView(
            configuration: configuration,
            isModalDialogOpen: $isModalDialogOpen,
            hasUndo: $hasUndo,
            hasRedo: $hasRedo,
            editorViewController: $editorViewController
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
                    Button(action: {
                        editorViewController?.undo()
                    }, label: {
                        Image(systemName: "arrow.uturn.backward")
                    })
                    .disabled(!hasUndo || isModalDialogOpen)

                    Button(action: {
                        editorViewController?.redo()
                    }, label: {
                        Image(systemName: "arrow.uturn.forward")
                    })
                    .disabled(!hasRedo || isModalDialogOpen)
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
    @Binding var hasUndo: Bool
    @Binding var hasRedo: Bool
    @Binding var editorViewController: EditorViewController?

    init(
        configuration: EditorConfiguration,
        isModalDialogOpen: Binding<Bool>,
        hasUndo: Binding<Bool>,
        hasRedo: Binding<Bool>,
        editorViewController: Binding<EditorViewController?>
    ) {
        self.configuration = configuration
        self._isModalDialogOpen = isModalDialogOpen
        self._hasUndo = hasUndo
        self._hasRedo = hasRedo
        self._editorViewController = editorViewController
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isModalDialogOpen: $isModalDialogOpen,
            hasUndo: $hasUndo,
            hasRedo: $hasRedo
        )
    }

    func makeUIViewController(context: Context) -> EditorViewController {
        let viewController = EditorViewController(configuration: configuration)
        viewController.delegate = context.coordinator

        if #available(iOS 16.4, *) {
            viewController.webView.isInspectable = true
        }
        viewController.startEditorSetup()

        // Store reference to view controller
        DispatchQueue.main.async {
            self.editorViewController = viewController
        }

        return viewController
    }

    func updateUIViewController(_ uiViewController: EditorViewController, context: Context) {
        // Do nothing
    }

    @MainActor
    class Coordinator: NSObject, EditorViewControllerDelegate {
        @Binding var isModalDialogOpen: Bool
        @Binding var hasUndo: Bool
        @Binding var hasRedo: Bool

        init(
            isModalDialogOpen: Binding<Bool>,
            hasUndo: Binding<Bool>,
            hasRedo: Binding<Bool>
        ) {
            self._isModalDialogOpen = isModalDialogOpen
            self._hasUndo = hasUndo
            self._hasRedo = hasRedo
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
            hasUndo = state.hasUndo
            hasRedo = state.hasRedo
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
        }

        func editor(_ viewController: EditorViewController, didCloseModalDialog dialogType: String) {
            isModalDialogOpen = false
        }
    }
}

#Preview {
    NavigationStack {
        EditorView(configuration: .default)
    }
}
