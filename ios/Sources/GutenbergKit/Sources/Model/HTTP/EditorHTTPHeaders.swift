import Foundation

/// A case-insensitive collection of HTTP headers.
///
/// This struct provides a type-safe way to work with HTTP headers, with case-insensitive
/// key lookups as required by the HTTP specification. Headers can be created using
/// dictionary literal syntax and are `Codable` for serialization.
///
/// Example usage:
/// ```swift
/// var headers: EditorHTTPHeaders = ["Content-Type": "application/json"]
/// headers["accept"] = "text/html"  // Case-insensitive
/// print(headers["CONTENT-TYPE"])   // "application/json"
/// ```
public struct EditorHTTPHeaders: Sendable, Codable, Equatable, Hashable, ExpressibleByDictionaryLiteral {
    private var elements: [String: String]

    /// Creates headers from a string dictionary.
    ///
    /// - Parameter elements: A dictionary of header names to values.
    init(_ elements: [String: String] = [:]) {
        self.elements = elements
    }

    /// Creates headers from an `HTTPURLResponse`'s `allHeaderFields` dictionary.
    ///
    /// Non-string keys and values are skipped.
    ///
    /// - Parameter elements: A dictionary typically from `HTTPURLResponse.allHeaderFields`.
    init(_ elements: [AnyHashable: Any]) {
        self.elements = [:]

        for (key, value) in elements {
            guard let keyString = key as? String, let valueString = value as? String else {
                continue
            }

            self.elements[keyString] = valueString
        }
    }

    /// Creates headers from a dictionary literal.
    ///
    /// - Parameter elements: Key-value pairs of header names and values.
    public init(dictionaryLiteral elements: (String, String)...) {
        self.elements = elements.reduce(into: [String: String](), { $0[$1.0] = $1.1 })
    }

    /// Accesses the header value for the given key using case-insensitive matching.
    ///
    /// When getting a value, the key is matched case-insensitively against stored headers.
    /// When setting a value, the new key will replace the old key case-insensitively.
    ///
    /// - Parameter key: The header name to look up or set.
    /// - Returns: The header value, or `nil` if no matching header exists.
    subscript(key: String) -> String? {
        get {
            let lowercasedKey = key.lowercased()
            return elements.first { $0.key.lowercased() == lowercasedKey }?.value
        }
        set {
            let lowercasedKey = key.lowercased()
            // Remove any existing key with same case-insensitive match
            if let existingKey = elements.keys.first(where: { $0.lowercased() == lowercasedKey }) {
                elements.removeValue(forKey: existingKey)
            }
            if let newValue {
                elements[key] = newValue
            }
        }
    }

    /// Compares two header collections for equality using case-insensitive key matching.
    public static func == (lhs: EditorHTTPHeaders, rhs: EditorHTTPHeaders) -> Bool {
        guard lhs.elements.count == rhs.elements.count else { return false }
        for (key, value) in lhs.elements {
            guard rhs[key] == value else { return false }
        }
        return true
    }

    /// Returns the headers as a standard string dictionary.
    ///
    /// Useful for passing headers to `URLRequest` or `HTTPURLResponse` APIs.
    public var dictionaryValue: [String: String] {
        self.elements
    }

    func toJSON() throws -> JSON {
        .object(elements.reduce(into: [String: JSON]()) { $0[$1.key] = .string($1.value) })
    }

    /// Returns a new headers collection containing only the specified keys.
    ///
    /// Key matching is case-insensitive for filtering.
    ///
    /// - Parameter keys: The header names to include.
    /// - Returns: A new `EditorHTTPHeaders` containing only the matching headers.
    public func filtering(keys: String...) -> EditorHTTPHeaders {
        let lowercasedKeys = keys.map { $0.lowercased() }
        return EditorHTTPHeaders(self.elements.filter { lowercasedKeys.contains($0.key.lowercased()) })
    }
}
