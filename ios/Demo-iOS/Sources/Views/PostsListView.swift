import SwiftUI
import WordPressAPI
import GutenbergKit

struct PostsListView: View {

    @Environment(\.navigation)
    private var navigation

    @State
    private var viewModel: PostsListViewModel

    private let title: String

    init(
        client: WordPressAPI,
        postTypeDetails: PostTypeDetails,
        title: String,
        editorConfiguration: EditorConfiguration,
        editorDependencies: EditorDependencies?
    ) {
        self.title = title
        self.viewModel = PostsListViewModel(
            client: client,
            postTypeDetails: postTypeDetails,
            editorConfiguration: editorConfiguration,
            editorDependencies: editorDependencies
        )
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.posts.isEmpty {
                ProgressView("Loading entries...")
            } else if let error = viewModel.error {
                ContentUnavailableView {
                    Label("Error Loading Entries", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("Retry") {
                        Task {
                            await viewModel.loadPosts()
                        }
                    }
                }
            } else if viewModel.posts.isEmpty {
                ContentUnavailableView {
                    Label("No Entries", systemImage: "doc.text")
                } description: {
                    Text("No entries found for this post type.")
                }
            } else {
                List(viewModel.posts, id: \.id) { post in
                    Button {
                        openPost(post)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            // Prefer the raw title (database value) over rendered, which is
                            // HTML-encoded for insertion into a page (e.g. spaces become `&nbsp;`).
                            Text(post.title?.raw ?? post.title?.rendered ?? "")
                                .font(.headline)
                            if let excerpt = post.excerpt?.rendered, !excerpt.isEmpty {
                                Text(excerpt.strippingHTML())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(title)
        .toolbar {
            if viewModel.postEditing != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Post", systemImage: "square.and.pencil") {
                        openNewPost()
                    }
                }
            }
        }
        .alert(
            "Couldn't open the post",
            isPresented: Binding(get: { viewModel.openError != nil }, set: { if !$0 { viewModel.openError = nil } }),
            presenting: viewModel.openError
        ) { _ in
        } message: { error in
            Text(error.localizedDescription)
        }
        .task {
            await viewModel.loadPosts()
        }
    }

    private func openPost(_ post: AnyPostWithEditContext) {
        if let postEditing = viewModel.postEditing {
            Task { await openPost(post.id, through: postEditing) }
            return
        }

        let configuration = viewModel.editorConfiguration.toBuilder()
            .setPostType(viewModel.postTypeDetails)
            .setPostID(Int(post.id))
            .setTitle(post.title?.raw ?? "")
            .setContent(post.content.raw ?? "")
            .build()

        let editor = RunnableEditor(
            configuration: configuration,
            dependencies: viewModel.editorDependencies,
            apiClient: viewModel.client
        )

        navigation.present(editor)
    }

    /// Opens a post in an editor session: wordpress-rs reads it, and the editor opens with its
    /// working copy, which can hold changes the server doesn't have.
    @MainActor
    private func openPost(_ postID: Int64, through postEditing: PostEditing) async {
        do {
            let session = try await postEditing.service.openPost(postId: postID)
            let editorPost = try session.editorPostWithFields()
            let configuration = viewModel.editorConfiguration.toBuilder()
                .setPostType(viewModel.postTypeDetails)
                .setPostID(Int(postID))
                .setTitle(editorPost.title)
                .setContent(editorPost.content)
                .apply(editorPost.status) { $0.setPostStatus($1) }
                .build()

            navigation.present(RunnableEditor(
                configuration: configuration,
                dependencies: viewModel.editorDependencies?.withPost(id: Int(postID), post: editorPost.post),
                apiClient: viewModel.client,
                postEditorSession: session
            ))
        } catch {
            viewModel.openError = error
        }
    }

    /// Opens a new post in an editor session. The post is created on the server on its first
    /// save.
    private func openNewPost() {
        guard let postEditing = viewModel.postEditing else { return }
        do {
            let session = try postEditing.service.openNewPost()
            let configuration = viewModel.editorConfiguration.toBuilder()
                .setPostType(viewModel.postTypeDetails)
                .setPostID(nil)
                .setTitle("")
                .setContent("")
                .build()

            navigation.present(RunnableEditor(
                configuration: configuration,
                dependencies: viewModel.editorDependencies,
                apiClient: viewModel.client,
                postEditorSession: session
            ))
        } catch {
            viewModel.openError = error
        }
    }
}

@Observable
class PostsListViewModel {
    var posts: [AnyPostWithEditContext] = []
    var isLoading = false
    var error: Error?

    let client: WordPressAPI
    let postTypeDetails: PostTypeDetails
    let editorConfiguration: EditorConfiguration
    let editorDependencies: EditorDependencies?
    /// Opens posts through wordpress-rs, for the `post` type only.
    let postEditing: PostEditing?
    var openError: Error?

    init(client: WordPressAPI, postTypeDetails: PostTypeDetails, editorConfiguration: EditorConfiguration, editorDependencies: EditorDependencies?) {
        self.client = client
        self.postTypeDetails = postTypeDetails
        self.editorConfiguration = editorConfiguration
        self.editorDependencies = editorDependencies
        if postTypeDetails.postType == "post" {
            do {
                self.postEditing = try PostEditing(client: client, siteURL: editorConfiguration.siteURL)
            } catch {
                print("Failed to set up wordpress-rs post editing: \(error)")
                self.postEditing = nil
            }
        } else {
            self.postEditing = nil
        }
    }

    @MainActor
    func loadPosts() async {
        guard !isLoading else { return }

        isLoading = true
        error = nil
        posts = []

        defer { isLoading = false }

        do {
            let endpointType: PostEndpointType
            if postTypeDetails.postType == "post" {
                endpointType = .posts
            } else if postTypeDetails.postType == "page" {
                endpointType = .pages
            } else {
                endpointType = .custom(postTypeDetails.restBase)
            }

            var currentPage: UInt32 = 1
            let perPage: UInt32 = 20
            while true {
                let params = PostListParams(page: currentPage, perPage: perPage, status: [.custom("any")])
                let fetched = try await client.posts.listWithEditContext(type: endpointType, params: params).data
                self.posts.append(contentsOf: fetched)

                if fetched.count < perPage {
                    break
                }
                currentPage += 1
            }
        } catch {
            self.error = error
        }
    }
}

private extension String {
    func strippingHTML() -> String {
        self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}
