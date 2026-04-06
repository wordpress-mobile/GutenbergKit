import SwiftUI
import GutenbergKit
import WordPressAPI

struct EditorView: View {
    private let configuration: EditorConfiguration
    private let dependencies: EditorDependencies?
    private let apiClient: WordPressAPI?

    @State private var viewModel = EditorViewModel()

    @Environment(\.dismiss) var dismiss

    init(configuration: EditorConfiguration, dependencies: EditorDependencies? = nil, apiClient: WordPressAPI? = nil) {
        self.configuration = configuration
        self.dependencies = dependencies
        self.apiClient = apiClient
    }

    var body: some View {
        _EditorView(
            configuration: configuration,
            dependencies: dependencies,
            apiClient: apiClient,
            viewModel: viewModel
        )
            .toolbar { toolbar }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                self.dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Close")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Group {
                Button {
                    viewModel.perform(.undo)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!viewModel.hasUndo)
                .accessibilityLabel("Undo")

                Button {
                    viewModel.perform(.redo)
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!viewModel.hasRedo)
                .accessibilityLabel("Redo")
            }
            .disabled(viewModel.isModalDialogOpen)
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            moreMenu
                .disabled(viewModel.isModalDialogOpen)
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                viewModel.save()
            } label: {
                Text("Save")
                    .fontWeight(.semibold)
            }
            .disabled(!viewModel.canSave)
            .accessibilityLabel("Save")
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
        .accessibilityLabel("More")
    }
}

private struct _EditorView: UIViewControllerRepresentable {
    private let configuration: EditorConfiguration
    private let dependencies: EditorDependencies?
    private let apiClient: WordPressAPI?
    private let viewModel: EditorViewModel

    init(
        configuration: EditorConfiguration,
        dependencies: EditorDependencies? = nil,
        apiClient: WordPressAPI? = nil,
        viewModel: EditorViewModel
    ) {
        self.configuration = configuration
        self.dependencies = dependencies
        self.apiClient = apiClient
        self.viewModel = viewModel
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIViewController(context: Context) -> EditorViewController {
        let viewController = EditorViewController(configuration: configuration, dependencies: dependencies)
        viewController.delegate = context.coordinator
        viewController.webView.isInspectable = true

        viewModel.perform = { [weak viewController] in
            switch $0 {
            case .redo: viewController?.redo()
            case .undo: viewController?.undo()
            }
        }

        viewModel.hasPostID = configuration.postID != nil

        viewModel.saveHandler = { [weak viewController, configuration, apiClient] in
            guard let viewController else { return }
            do {
                // 1. Trigger the editor store save lifecycle so plugins fire side-effects
                try await viewController.savePost()
                print("savePost() completed — editor store save lifecycle fired")

                // 2. Persist post content via REST API
                if let apiClient, let postID = configuration.postID {
                    let titleAndContent = try await viewController.getTitleAndContent()
                    let params = PostUpdateParams(title: .some(titleAndContent.title), content: .some(titleAndContent.content), meta: nil)
                    let endpointType: PostEndpointType = configuration.postType.postType == "page" ? .pages : .posts
                    _ = try await apiClient.posts.updateCancellation(
                        postEndpointType: endpointType,
                        postId: Int64(postID),
                        params: params,
                        context: nil
                    )
                    print("Post \(postID) persisted via REST API")
                }
            } catch {
                print("Save failed: \(error)")
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
            viewModel.isEditorReady = true
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

        func editor(_ viewController: EditorViewController, didLogNetworkRequest request: RecordedNetworkRequest) {
            print("🌐 Network Request: \(request.method) \(request.url)")
            print("   Status: \(request.status) \(request.statusText), Duration: \(request.duration)ms")

            // Log request headers
            if !request.requestHeaders.isEmpty {
                print("   Request Headers:")
                for (key, value) in request.requestHeaders.sorted(by: { $0.key < $1.key }) {
                    print("      \(key): \(value)")
                }
            }

            if let requestBody = request.requestBody {
                print("   Request Body: \(requestBody.prefix(200))...")
            }

            // Log response headers
            if !request.responseHeaders.isEmpty {
                print("   Response Headers:")
                for (key, value) in request.responseHeaders.sorted(by: { $0.key < $1.key }) {
                    print("      \(key): \(value)")
                }
            }

            if let responseBody = request.responseBody {
                print("   Response Body: \(responseBody.prefix(200))...")
            }
        }

        func editorDidRequestLatestContent(_ controller: EditorViewController) -> (title: String, content: String)? {
            // Demo app has no persistence layer, so return nil.
            // In a real app, return the persisted title and content from autosave.
            return nil
        }
    }
}

@Observable
private final class EditorViewModel {
    var isModalDialogOpen = false
    var hasUndo = false
    var hasRedo = false
    var isCodeEditorEnabled = false
    var isSaving = false
    var isEditorReady = false

    var hasPostID = false

    var canSave: Bool {
        isEditorReady && !isSaving && hasPostID
    }

    enum Action {
        case undo
        case redo
    }

    var perform: (_ action: Action) -> Void = { _ in assertionFailure() }
    var saveHandler: () async -> Void = {}

    func save() {
        guard canSave else { return }
        isSaving = true
        Task {
            await saveHandler()
            isSaving = false
        }
    }
}

#Preview {
    NavigationStack {
        EditorView(configuration: .bundled)
    }
}

extension EditorConfiguration {
    static let bundled = EditorConfigurationBuilder(
        postType: .post,
        siteURL: URL(string: "https://example.com")!,
        siteApiRoot: URL(string: "https://example.com/wp-json")!
    )
    .setShouldUsePlugins(false)
    .setAuthHeader("")
    .setIsOfflineModeEnabled(true)
    .build()
}
