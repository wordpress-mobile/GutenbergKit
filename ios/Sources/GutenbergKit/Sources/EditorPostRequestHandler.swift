import Foundation

/// Sends the editor's requests for the post being edited, and for the paths below it, such as
/// its autosaves, in place of the editor.
///
/// With a handler, the editor sends none of these requests itself, saves included: a save from
/// the editor, such as the user's or a plugin's call to Gutenberg's `savePost()`, comes here as
/// a write to the post. The editor parses the response as if it had sent the request itself.
///
/// Pass one to ``EditorViewController/init(configuration:dependencies:mediaPicker:mediaProcessor:mediaUploader:postRequestHandler:httpClient:isWarmupMode:)``.
/// The editor holds it strongly for its lifetime, so don't conform the object that owns the
/// editor.
public protocol EditorPostRequestHandler: AnyObject, Sendable {
    /// Sends `request` and returns the server's response as it arrived, error statuses included.
    ///
    /// Throw only when no response came, such as when the server couldn't be reached. The editor
    /// then fails the request as a failed `fetch` does.
    func perform(_ request: EditorPostRequest) async throws -> EditorPostResponse
}

/// A request the editor sends for the post it's editing.
public struct EditorPostRequest: Sendable, Equatable {
    /// The HTTP method, uppercased: `GET`, `PUT` and so on.
    public let method: String

    /// The REST API path with its query, such as `/wp/v2/posts/1?context=edit`.
    public let path: String

    /// The JSON body, if the request has one.
    public let body: Data?

    public init(method: String, path: String, body: Data?) {
        self.method = method
        self.path = path
        self.body = body
    }

    /// The request in a `performPostRequest` message from the editor's page.
    init?(scriptMessageBody: Any) {
        guard let object = scriptMessageBody as? [String: Any],
              let method = object["method"] as? String,
              let path = object["path"] as? String else {
            return nil
        }
        self.init(method: method, path: path, body: (object["body"] as? String).map { Data($0.utf8) })
    }
}

/// The server's response to an ``EditorPostRequest``.
public struct EditorPostResponse: Sendable, Equatable {
    /// The HTTP status.
    public let status: Int

    /// The response's headers.
    public let headers: [String: String]

    /// The response's body, as the server sent it.
    public let body: Data

    public init(status: Int, headers: [String: String], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    /// The response as the editor's page takes it, with the body as text.
    var scriptMessageReply: [String: Any] {
        [
            "status": status,
            "headers": headers,
            "body": String(decoding: body, as: UTF8.self)
        ]
    }
}
