import Foundation

public struct EditorConfiguration {
    /// The initial title to initialize the editor with.
    public var title = ""
    /// The initial content to initialize the editor with.
    public var content = ""

    public var postID: Int?
    public var postType: String?
    public var themeStyles = false
    public var plugins = false
    public var hideTitle = false
    public var siteURL = ""
    public var siteApiRoot = ""
    public var siteApiNamespace: [String] = []
    public var namespaceExcludedPaths: [String] = []
    public var authHeader = ""
    public var webViewGlobals: [WebViewGlobal] = []
    /// Raw block editor settings from the WordPress REST API
    public var editorSettings: [String: Any]?
    /// The locale to use for translations
    public var locale = "en"

    public init(title: String = "", content: String = "") {
        self.title = title
        self.content = content
    }

    public mutating func updateEditorSettings(_ settings: [String: Any]?) {
        self.editorSettings = settings
    }

    public static let `default` = EditorConfiguration()
}

public struct WebViewGlobal {
    let name: String
    let value: WebViewGlobalValue

    public init(name: String, value: WebViewGlobalValue) throws {
        // Validate name is a valid JavaScript identifier
        guard Self.isValidJavaScriptIdentifier(name) else {
            throw WebViewGlobalError.invalidIdentifier(name)
        }
        self.name = name
        self.value = value
    }

    private static func isValidJavaScriptIdentifier(_ name: String) -> Bool {
        // Add validation logic for JavaScript identifiers
        return name.range(of: "^[a-zA-Z_$][a-zA-Z0-9_$]*$", options: .regularExpression) != nil
    }
}

public enum WebViewGlobalError: Error {
    case invalidIdentifier(String)
}

public enum WebViewGlobalValue {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case object([String: WebViewGlobalValue])
    case array([WebViewGlobalValue])
    case null

    func toJavaScript() -> String {
        switch self {
        case .string(let str):
            return "\"\(str.escaped)\""
        case .number(let num):
            return "\(num)"
        case .boolean(let bool):
            return "\(bool)"
        case .object(let dict):
            let pairs = dict.map { key, value in
                "\"\(key.escaped)\": \(value.toJavaScript())"
            }
            return "{\(pairs.joined(separator: ","))}"
        case .array(let array):
            return "[\(array.map { $0.toJavaScript() }.joined(separator: ","))]"
        case .null:
            return "null"
        }
    }
}

// String escaping extension
private extension String {
    var escaped: String {
        return self.replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\u{8}", with: "\\b")
            .replacingOccurrences(of: "\u{12}", with: "\\f")
    }
}
