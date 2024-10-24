import WebKit

/// A type that represents JavaScript messages send from and to the web view.
struct EditorJSMessage {
    let type: MessageType
    let body: Any?

    init?(message: WKScriptMessage) {
        guard let object = message.body as? [String: Any],
              let type = (object["message"] as? String).flatMap(MessageType.init) else {
            return nil
        }
        self.type = type
        self.body = object["body"]
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        guard let body else {
            throw URLError(.unknown)
        }
        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        return try JSONDecoder().decode(T.self, from: data)
    }

    enum MessageType: String {
        /// The editor was mounted (initial useEffect was called).
        case onEditorLoaded
        /// The editor content changed.
        case onEditorContentChanged
        /// The user tapped the inserter button.
        case showBlockPicker
    }

    struct DidUpdateBlocksBody: Decodable {
        let isEmpty: Bool
    }
}
