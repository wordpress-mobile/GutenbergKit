import SwiftUI
import WordPressAPI
import GutenbergKit

struct PostsListView: View {

    @Environment(\.navigation)
    private var navigation

    @State
    private var viewModel: PostsListViewModel

    init(client: WordPressAPI, postTypeDetails: PostTypeDetails, editorConfiguration: EditorConfiguration, editorDependencies: EditorDependencies?) {
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
                    Label("No Entires", systemImage: "doc.text")
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
        .navigationTitle(viewModel.postTypeDetails.restBase.capitalized)
        .task {
            await viewModel.loadPosts()
        }
    }

    private func openPost(_ post: AnyPostWithEditContext) {
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

    init(client: WordPressAPI, postTypeDetails: PostTypeDetails, editorConfiguration: EditorConfiguration, editorDependencies: EditorDependencies?) {
        self.client = client
        self.postTypeDetails = postTypeDetails
        self.editorConfiguration = editorConfiguration
        self.editorDependencies = editorDependencies
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
