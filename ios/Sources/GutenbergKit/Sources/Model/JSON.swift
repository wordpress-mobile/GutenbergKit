import Foundation

// Originally found at https://forums.swift.org/t/support-embedding-json-like-objects-in-swift-code/38329/13

public enum JSON: Sendable, Equatable, Hashable, CustomStringConvertible {
    indirect case object([String: JSON])
    indirect case array([JSON])
    case number(Double)
    case string(String)
    case boolean(Bool)
    case null

    /// Creates a JSON value by parsing the given data.
    ///
    /// - Parameter data: The JSON data to parse.
    /// - Throws: A `DecodingError` if the data is not valid JSON.
    init(_ data: Data) throws {
        if data == Data() {
            self = .null
            return
        }

        self = try JSONDecoder().decode(JSON.self, from: data)
    }

    public var description: String {
        let data = try! JSONSerialization.data(withJSONObject: self, options: [.prettyPrinted, .withoutEscapingSlashes])
        return String(data: data, encoding: .utf8)!
    }
}

extension JSON: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .boolean(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .number(Double(int))
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let object = try? container.decode([String: JSON].self) {
            self = .object(object)
        } else if let array = try? container.decode([JSON].self) {
            self = .array(array)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .object(let dict):
            try container.encode(dict)
        case .array(let array):
            try container.encode(array)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    /// Returns `true` if this JSON value is an object.
    var isObject: Bool {
        guard case .object = self else {
            return false
        }
        return true
    }

    /// Returns `true` if this JSON value is an array.
    var isArray: Bool {
        guard case .array = self else {
            return false
        }
        return true
    }

    /// Returns `true` if this JSON value is a number.
    var isNumber: Bool {
        guard case .number = self else {
            return false
        }
        return true
    }

    /// Returns `true` if this JSON value is a string.
    var isString: Bool {
        guard case .string = self else {
            return false
        }
        return true
    }

    /// Returns `true` if this JSON value is a boolean.
    var isBoolean: Bool {
        guard case .boolean = self else {
            return false
        }
        return true
    }

    /// Returns `true` if this JSON value is null.
    var isNull: Bool {
        guard case .null = self else {
            return false
        }
        return true
    }

    /// Returns the dictionary value if this is an object, or `nil` otherwise.
    var objectValue: [String: JSON]? {
        guard case .object(let dict) = self else {
            return nil
        }
        return dict
    }

    /// Returns the array value if this is an array, or `nil` otherwise.
    var arrayValue: [JSON]? {
        guard case .array(let arr) = self else {
            return nil
        }
        return arr
    }

    /// Returns the number if this is a number, or `nil` otherwise.
    var numberValue: Double? {
        guard case .number(let value) = self else {
            return nil
        }
        return value
    }

    /// Returns the string value if this is a string, or `nil` otherwise.
    var stringValue: String? {
        guard case .string(let value) = self else {
            return nil
        }
        return value
    }

    /// Returns the boolean value if this is a boolean, or `nil` otherwise.
    var booleanValue: Bool? {
        guard case .boolean(let value) = self else {
            return nil
        }
        return value
    }
}

extension JSON: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSON)...) {
        self = .object(.init(uniqueKeysWithValues: elements))
    }
}

extension JSON: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSON...) {
        self = .array(elements)
    }
}

extension JSON: ExpressibleByFloatLiteral {
    public init(floatLiteral value: FloatLiteralType) {
        self = .number(value)
    }
}

extension JSON: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: IntegerLiteralType) {
        self = .number(.init(value))
    }
}

extension JSON: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        self = .string(value)
    }
}

extension JSON: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: BooleanLiteralType) {
        self = .boolean(value)
    }
}

extension JSON: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}
