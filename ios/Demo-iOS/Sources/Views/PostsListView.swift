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
                ProgressView("Loading Posts...")
            } else if let error = viewModel.error {
                ContentUnavailableView {
                    Label("Error Loading Posts", systemImage: "exclamationmark.triangle")
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
                    Label("No Posts", systemImage: "doc.text")
                } description: {
                    Text("No posts found for this post type.")
                }
            } else {
                List(viewModel.posts, id: \.id) { post in
                    Button {
                        openPost(post)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(post.title?.rendered ?? "")
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
            dependencies: viewModel.editorDependencies
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

            let sequence = client.posts.sequenceWithEditContext(
                type: endpointType,
                params: PostListParams(perPage: 20, status: [.custom("any")])
            )

            var loadedPosts: [AnyPostWithEditContext] = []
            for try await page in sequence {
                loadedPosts.append(contentsOf: page)
            }
            self.posts = loadedPosts
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
