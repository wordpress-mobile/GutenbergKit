import WebKit

struct JSEditorMessage {
    let type: JSEditorMessageType
    let body: Any?

    init?(message: WKScriptMessage) {
        guard let object = message.body as? [String: Any],
              let type = (object["message"] as? String).flatMap(JSEditorMessageType.init) else {
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
}

enum JSEditorMessageType: String {
    case onEditorLoaded
}
