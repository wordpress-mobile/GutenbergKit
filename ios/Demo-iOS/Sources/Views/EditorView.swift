import SwiftUI
import GutenbergKit

struct EditorView: View {
    private let configuration: EditorConfiguration

    @State private var viewModel = EditorViewModel()

    @Environment(\.dismiss) private var dismiss

    init(configuration: EditorConfiguration) {
        self.configuration = configuration
    }

    var body: some View {
        _EditorView(configuration: configuration, viewModel: viewModel)
            .toolbar { toolbar }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .disabled(viewModel.isModalDialogOpen)
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Group {
                Button {
                    viewModel.perform(.undo)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!viewModel.hasUndo)

                Button {
                    viewModel.perform(.redo)
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!viewModel.hasRedo)
            }
            .disabled(viewModel.isModalDialogOpen)
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            moreMenu
                .disabled(viewModel.isModalDialogOpen)
        }
    }

    private var moreMenu: some View {
        Menu {
            Section {
                Button(action: {
                    viewModel.isCodeEditorEnabled.toggle()
                }, label: {
                    Label(
                        viewModel.isCodeEditorEnabled ? "Visual Editor" : "Code Editor",
                        systemImage: viewModel.isCodeEditorEnabled ? "doc.richtext" : "curlybraces"
                    )
                })
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
    private let viewModel: EditorViewModel

    init(
        configuration: EditorConfiguration,
        viewModel: EditorViewModel,
    ) {
        self.configuration = configuration
        self.viewModel = viewModel
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIViewController(context: Context) -> EditorViewController {
        let viewController = EditorViewController(configuration: configuration)
        viewController.delegate = context.coordinator
        viewController.webView.isInspectable = true
        viewController.startEditorSetup()

        viewModel.perform = { [weak viewController] in
            switch $0 {
            case .redo: viewController?.redo()
            case .undo: viewController?.undo()
            }
        }

        return viewController
    }

    func updateUIViewController(_ viewController: EditorViewController, context: Context) {
        viewController.isCodeEditorEnabled = viewModel.isCodeEditorEnabled
    }

    @MainActor
    class Coordinator: NSObject, EditorViewControllerDelegate {
        let viewModel: EditorViewModel

        init(viewModel: EditorViewModel) {
            self.viewModel = viewModel
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
            viewModel.hasUndo = state.hasUndo
            viewModel.hasRedo = state.hasRedo
        }

        func editor(_ viewController: EditorViewController, didUpdateFeaturedImage mediaID: Int) {
            // No-op for demo
        }

        func editor(_ viewController: EditorViewController, didLogMessage message: String, level: LogLevel) {
            print("[\(level)]: \(message)")
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
            viewModel.isModalDialogOpen = true
        }

        func editor(_ viewController: EditorViewController, didCloseModalDialog dialogType: String) {
            viewModel.isModalDialogOpen = false
        }

        func editor(_ viewController: EditorViewController, didLogNetworkRequest request: NetworkRequest) {
            print("🌐 Network Request: \(request.method) \(request.url)")
            print("   Status: \(request.status), Duration: \(request.duration)ms")
            if let requestBody = request.requestBody {
                print("   Request Body: \(requestBody.prefix(200))...")
            }
            if let responseBody = request.responseBody {
                print("   Response Body: \(responseBody.prefix(200))...")
            }
        }
    }
}

@Observable
private final class EditorViewModel {
    var isModalDialogOpen = false
    var hasUndo = false
    var hasRedo = false
    var isCodeEditorEnabled = false

    enum Action {
        case undo
        case redo
    }

    var perform: (_ action: Action) -> Void = { _ in assertionFailure() }
}

#Preview {
    NavigationStack {
        EditorView(configuration: .default)
    }
}
