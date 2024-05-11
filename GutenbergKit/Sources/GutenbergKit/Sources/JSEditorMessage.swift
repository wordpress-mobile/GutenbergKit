import WebKit

struct JSEditorMessage {
    let type: JSEditorMessageType
    private let body: Any

    init?(message: WKScriptMessage) {
        guard let object = message.body as? [String: Any],
              let type = (object["message"] as? String).flatMap(JSEditorMessageType.init),
              let body = object["body"] else {
            return nil
        }
        self.type = type
        self.body = body
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum JSEditorMessageType: String {
    case onBlocksChanged
}
