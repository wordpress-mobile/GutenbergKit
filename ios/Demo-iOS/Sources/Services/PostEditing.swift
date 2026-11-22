import Foundation
import GutenbergKit
import WordPressAPI
import WordPressApiCache

/// Opens a site's posts through wordpress-rs's `PostEditorService`, which reads the post, records
/// every change in its working copy on the device, and sends the editor's requests for it.
///
/// Only posts of the `post` type go through it: `PostEditorService` handles `/wp/v2/posts`.
final class PostEditing: Sendable {
    let service: PostEditorService

    /// The databases for the site at `siteURL`, kept in Application Support, so working copies
    /// and editor sessions outlive the app.
    init(client: WordPressAPI, siteURL: URL) throws {
        let directory = URL.applicationSupportDirectory
            .appending(path: "wordpress-rs", directoryHint: .isDirectory)
            .appending(path: siteURL.host(percentEncoded: false) ?? "site", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let cache = try WordPressApiCache(path: directory.appending(path: "cache.sqlite").path)
        _ = try cache.performMigrations()
        let store = try WpLocalContentStore(path: directory.appending(path: "local-content.sqlite").path)
        _ = try store.performMigrations()

        self.service = PostEditorService(
            wpService: try client.createService(cache: cache),
            localContent: LocalContentService(store: store),
            site: SiteIdentity(url: try ParsedUrl.parse(input: siteURL.absoluteString), wordpressComSiteId: nil)
        )
    }
}

/// Sends the editor's requests for the post through the post's editor session.
final class SessionPostRequestHandler: EditorPostRequestHandler {
    private let session: PostEditorSession

    init(session: PostEditorSession) {
        self.session = session
    }

    func perform(_ request: EditorPostRequest) async throws -> EditorPostResponse {
        let response = try await session.performEditorRequest(
            request: EditorRequest(method: request.method, path: request.path, body: request.body)
        )
        return EditorPostResponse(
            status: Int(response.statusCode),
            headers: response.headers,
            body: response.body
        )
    }
}

/// What the editor opens a post with: the server's version as its saved version, with the raw
/// title, content and status the editor's configuration takes, and the working copy's changes
/// as edits.
struct OpenedPost {
    let savedPost: Data
    let title: String
    let content: String
    let status: String?
    let edits: Data
}

extension PostEditorSession {
    /// The post as the editor opens it. `nil` for a post that isn't on the server yet.
    func openedPost() throws -> OpenedPost? {
        let editorPost = try editorPost()
        guard let savedPost = editorPost.savedPost else { return nil }
        let object = try JSONSerialization.jsonObject(with: savedPost) as? [String: Any] ?? [:]
        func raw(_ key: String) -> String {
            (object[key] as? [String: Any])?["raw"] as? String ?? ""
        }
        return OpenedPost(
            savedPost: savedPost,
            title: raw("title"),
            content: raw("content"),
            status: object["status"] as? String,
            edits: editorPost.edits
        )
    }
}
