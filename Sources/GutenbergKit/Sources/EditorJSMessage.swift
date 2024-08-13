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

    init(type: MessageType) {
        self.type = type
        self.body = nil
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        guard let body else {
            throw URLError(.unknown)
        }
        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        return try JSONDecoder().decode(T.self, from: data)
    }

    enum MessageType: String {
        /// The web view loaded the specified URL or file
        case onLoaded
        /// The editor was mounted (initial useEffect was called).
        case onEditorLoaded
        /// The editor content changed.
        case onBlocksChanged
        /// The user tapped the inserter button.
        case showBlockPicker
    }

    struct DidUpdateBlocksBody: Decodable {
        let isEmpty: Bool
    }
}
