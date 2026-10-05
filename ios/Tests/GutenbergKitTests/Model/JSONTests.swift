import Foundation
import Testing

@testable import GutenbergKit

@Suite
struct JSONTests {

  // MARK: - ExpressibleByDictionaryLiteral Tests
  @Test("Dictionary literal creates object")
  func dictionaryLiteralCreatesObject() {
    let json: JSON = ["name": "John", "age": 30]
    #expect(json.isObject)
    #expect(json.objectValue?["name"] == .string("John"))
    #expect(json.objectValue?["age"] == .number(30))
  }

  @Test("Empty dictionary literal creates empty object")
  func emptyDictionaryLiteralCreatesEmptyObject() {
    let json: JSON = [:]
    #expect(json.isObject)
    #expect(json.objectValue?.isEmpty == true)
  }

  @Test("Nested dictionary literal creates nested object")
  func nestedDictionaryLiteralCreatesNestedObject() {
    let json: JSON = [
      "person": [
        "name": "Jane",
        "address": [
          "city": "New York"
        ]
      ]
    ]
    #expect(json.isObject)
    let person = json.objectValue?["person"]
    #expect(person?.isObject == true)
    let address = person?.objectValue?["address"]
    #expect(address?.isObject == true)
    #expect(address?.objectValue?["city"]?.stringValue == "New York")
  }

  // MARK: - ExpressibleByArrayLiteral Tests

  @Test("Array literal creates array")
  func arrayLiteralCreatesArray() {
    let json: JSON = [1, 2, 3]
    #expect(json.isArray)
    #expect(json.arrayValue?.count == 3)
    #expect(json.arrayValue?[0] == .number(1))
    #expect(json.arrayValue?[1] == .number(2))
    #expect(json.arrayValue?[2] == .number(3))
  }

  @Test("Empty array literal creates empty array")
  func emptyArrayLiteralCreatesEmptyArray() {
    let json: JSON = []
    #expect(json.isArray)
    #expect(json.arrayValue?.isEmpty == true)
  }

  @Test("Mixed type array literal creates array")
  func mixedTypeArrayLiteralCreatesArray() {
    let json: JSON = ["string", 42, true, nil]
    #expect(json.isArray)
    #expect(json.arrayValue?.count == 4)
    #expect(json.arrayValue?[0].stringValue == "string")
    #expect(json.arrayValue?[1].numberValue == 42)
    #expect(json.arrayValue?[2].booleanValue == true)
    #expect(json.arrayValue?[3].isNull == true)
  }

  @Test("Nested array literal creates nested array")
  func nestedArrayLiteralCreatesNestedArray() {
    let json: JSON = [[1, 2], [3, 4]]
    #expect(json.isArray)
    #expect(json.arrayValue?.count == 2)
    #expect(json.arrayValue?[0].isArray == true)
    #expect(json.arrayValue?[0].arrayValue == [.number(1), .number(2)])
  }

  // MARK: - ExpressibleByFloatLiteral Tests

  @Test("Float literal creates number")
  func floatLiteralCreatesNumber() {
    let json: JSON = 3.14159
    #expect(json.isNumber)
    #expect(json.numberValue == 3.14159)
  }

  @Test("Negative float literal creates number")
  func negativeFloatLiteralCreatesNumber() {
    let json: JSON = -2.5
    #expect(json.isNumber)
    #expect(json.numberValue == -2.5)
  }

  @Test("Zero float literal creates number")
  func zeroFloatLiteralCreatesNumber() {
    let json: JSON = 0.0
    #expect(json.isNumber)
    #expect(json.numberValue == 0.0)
  }

  // MARK: - ExpressibleByIntegerLiteral Tests

  @Test("Integer literal creates number")
  func integerLiteralCreatesNumber() {
    let json: JSON = 42
    #expect(json.isNumber)
    #expect(json.numberValue == 42.0)
  }

  @Test("Negative integer literal creates number")
  func negativeIntegerLiteralCreatesNumber() {
    let json: JSON = -100
    #expect(json.isNumber)
    #expect(json.numberValue == -100.0)
  }

  @Test("Zero integer literal creates number")
  func zeroIntegerLiteralCreatesNumber() {
    let json: JSON = 0
    #expect(json.isNumber)
    #expect(json.numberValue == 0.0)
  }

  @Test("Large integer literal creates number")
  func largeIntegerLiteralCreatesNumber() {
    let json: JSON = 1_000_000
    #expect(json.isNumber)
    #expect(json.numberValue == 1_000_000.0)
  }

  // MARK: - ExpressibleByStringLiteral Tests

  @Test("String literal creates string")
  func stringLiteralCreatesString() {
    let json: JSON = "hello world"
    #expect(json.isString)
    #expect(json.stringValue == "hello world")
  }

  @Test("Empty string literal creates string")
  func emptyStringLiteralCreatesString() {
    let json: JSON = ""
    #expect(json.isString)
    // Optional `String?`: `== ""` asserts present-and-empty, which `isEmpty` cannot express.
    // swiftlint:disable:next empty_string
    #expect(json.stringValue == "")
  }

  @Test("String with special characters creates string")
  func stringWithSpecialCharactersCreatesString() {
    let json: JSON = "line1\nline2\ttab\"quote\\"
    #expect(json.isString)
    #expect(json.stringValue == "line1\nline2\ttab\"quote\\")
  }

  @Test("Unicode string literal creates string")
  func unicodeStringLiteralCreatesString() {
    let json: JSON = "こんにちは 🌍"
    #expect(json.isString)
    #expect(json.stringValue == "こんにちは 🌍")
  }

  // MARK: - ExpressibleByBooleanLiteral Tests

  @Test("True literal creates boolean")
  func trueLiteralCreatesBoolean() {
    let json: JSON = true
    #expect(json.isBoolean)
    #expect(json.booleanValue == true)
  }

  @Test("False literal creates boolean")
  func falseLiteralCreatesBoolean() {
    let json: JSON = false
    #expect(json.isBoolean)
    #expect(json.booleanValue == false)
  }

  // MARK: - ExpressibleByNilLiteral Tests

  @Test("Nil literal creates null")
  func nilLiteralCreatesNull() {
    let json: JSON = nil
    #expect(json.isNull)
  }

  // MARK: - Complex Structure Tests

  @Test("Complex nested structure is created correctly")
  func complexNestedStructureCreatedCorrectly() {
    let json: JSON = [
      "users": [
        [
          "id": 1,
          "name": "Alice",
          "active": true,
          "score": 95.5,
          "metadata": nil
        ],
        [
          "id": 2,
          "name": "Bob",
          "active": false,
          "score": 87.0,
          "metadata": ["role": "admin"]
        ]
      ],
      "count": 2,
      "hasMore": false
    ]

    #expect(json.isObject)
    #expect(json.objectValue?["count"] == .number(2))
    #expect(json.objectValue?["hasMore"] == .boolean(false))

    let users = json.objectValue?["users"]
    #expect(users?.isArray == true)
    #expect(users?.arrayValue?.count == 2)

    // Check first user
    let alice = users?.arrayValue?[0]
    #expect(alice?.isObject == true)
    #expect(alice?.objectValue?["id"] == .number(1))
    #expect(alice?.objectValue?["name"] == .string("Alice"))
    #expect(alice?.objectValue?["active"] == .boolean(true))
    #expect(alice?.objectValue?["score"] == .number(95.5))
    #expect(alice?.objectValue?["metadata"] == .null)

    // Check second user with nested metadata
    let bob = users?.arrayValue?[1]
    #expect(bob?.isObject == true)
    let metadata = bob?.objectValue?["metadata"]
    #expect(metadata?.isObject == true)
    #expect(metadata?.objectValue?["role"] == .string("admin"))
  }

  @Test("Array of objects is created correctly")
  func arrayOfObjectsCreatedCorrectly() {
    let json: JSON = [
      ["x": 0, "y": 0],
      ["x": 10, "y": 20],
      ["x": -5, "y": 15]
    ]

    #expect(json.isArray)
    #expect(json.arrayValue?.count == 3)

    let first = json.arrayValue?[0]
    #expect(first?.isObject == true)
    #expect(first?.objectValue?["x"] == .number(0))
    #expect(first?.objectValue?["y"] == .number(0))
  }

  // MARK: - Type Checking Accessor Tests

  @Test("isObject returns true for objects")
  func isObjectReturnsTrueForObjects() {
    let json: JSON = ["key": "value"]
    #expect(json.isObject)
  }

  @Test("isObject returns false for non-objects")
  func isObjectReturnsFalseForNonObjects() {
    #expect(!JSON.array([]).isObject)
    #expect(!JSON.number(42).isObject)
    #expect(!JSON.string("test").isObject)
    #expect(!JSON.boolean(true).isObject)
    #expect(!JSON.null.isObject)
  }

  @Test("isArray returns true for arrays")
  func isArrayReturnsTrueForArrays() {
    let json: JSON = [1, 2, 3]
    #expect(json.isArray)
  }

  @Test("isArray returns false for non-arrays")
  func isArrayReturnsFalseForNonArrays() {
    #expect(!JSON.object([:]).isArray)
    #expect(!JSON.number(42).isArray)
    #expect(!JSON.string("test").isArray)
    #expect(!JSON.boolean(true).isArray)
    #expect(!JSON.null.isArray)
  }

  @Test("isNumber returns true for numbers")
  func isNumberReturnsTrueForNumbers() {
    let json: JSON = 42.5
    #expect(json.isNumber)
  }

  @Test("isNumber returns false for non-numbers")
  func isNumberReturnsFalseForNonNumbers() {
    #expect(!JSON.object([:]).isNumber)
    #expect(!JSON.array([]).isNumber)
    #expect(!JSON.string("42").isNumber)
    #expect(!JSON.boolean(true).isNumber)
    #expect(!JSON.null.isNumber)
  }

  @Test("isString returns true for strings")
  func isStringReturnsTrueForStrings() {
    let json: JSON = "hello"
    #expect(json.isString)
  }

  @Test("isString returns false for non-strings")
  func isStringReturnsFalseForNonStrings() {
    #expect(!JSON.object([:]).isString)
    #expect(!JSON.array([]).isString)
    #expect(!JSON.number(42).isString)
    #expect(!JSON.boolean(true).isString)
    #expect(!JSON.null.isString)
  }

  @Test("isBoolean returns true for booleans")
  func isBooleanReturnsTrueForBooleans() {
    #expect(JSON.boolean(true).isBoolean)
    #expect(JSON.boolean(false).isBoolean)
  }

  @Test("isBoolean returns false for non-booleans")
  func isBooleanReturnsFalseForNonBooleans() {
    #expect(!JSON.object([:]).isBoolean)
    #expect(!JSON.array([]).isBoolean)
    #expect(!JSON.number(1).isBoolean)
    #expect(!JSON.string("true").isBoolean)
    #expect(!JSON.null.isBoolean)
  }

  @Test("isNull returns true for null")
  func isNullReturnsTrueForNull() {
    let json: JSON = nil
    #expect(json.isNull)
  }

  @Test("isNull returns false for non-null values")
  func isNullReturnsFalseForNonNullValues() {
    #expect(!JSON.object([:]).isNull)
    #expect(!JSON.array([]).isNull)
    #expect(!JSON.number(0).isNull)
    #expect(!JSON.string("").isNull)
    #expect(!JSON.boolean(false).isNull)
  }

  // MARK: - Value Accessor Tests

  @Test("objectValue returns dictionary for objects")
  func objectValueReturnsDictionaryForObjects() {
    let json: JSON = ["key": "value"]
    #expect(json.objectValue != nil)
    #expect(json.objectValue?["key"] == .string("value"))
  }

  @Test("objectValue returns nil for non-objects")
  func objectValueReturnsNilForNonObjects() {
    #expect(JSON.array([]).objectValue == nil)
    #expect(JSON.number(42).objectValue == nil)
    #expect(JSON.string("test").objectValue == nil)
    #expect(JSON.boolean(true).objectValue == nil)
    #expect(JSON.null.objectValue == nil)
  }

  @Test("arrayValue returns array for arrays")
  func arrayValueReturnsArrayForArrays() {
    let json: JSON = [1, 2, 3]
    #expect(json.arrayValue != nil)
    #expect(json.arrayValue?.count == 3)
  }

  @Test("arrayValue returns nil for non-arrays")
  func arrayValueReturnsNilForNonArrays() {
    #expect(JSON.object([:]).arrayValue == nil)
    #expect(JSON.number(42).arrayValue == nil)
    #expect(JSON.string("test").arrayValue == nil)
    #expect(JSON.boolean(true).arrayValue == nil)
    #expect(JSON.null.arrayValue == nil)
  }

  @Test("numberValue returns double for numbers")
  func numberValueReturnsDoubleForNumbers() {
    let json: JSON = 42.5
    #expect(json.numberValue == 42.5)
  }

  @Test("numberValue returns nil for non-numbers")
  func numberValueReturnsNilForNonNumbers() {
    #expect(JSON.object([:]).numberValue == nil)
    #expect(JSON.array([]).numberValue == nil)
    #expect(JSON.string("42").numberValue == nil)
    #expect(JSON.boolean(true).numberValue == nil)
    #expect(JSON.null.numberValue == nil)
  }

  @Test("stringValue returns string for strings")
  func stringValueReturnsStringForStrings() {
    let json: JSON = "hello"
    #expect(json.stringValue == "hello")
  }

  @Test("stringValue returns nil for non-strings")
  func stringValueReturnsNilForNonStrings() {
    #expect(JSON.object([:]).stringValue == nil)
    #expect(JSON.array([]).stringValue == nil)
    #expect(JSON.number(42).stringValue == nil)
    #expect(JSON.boolean(true).stringValue == nil)
    #expect(JSON.null.stringValue == nil)
  }

  @Test("booleanValue returns bool for booleans")
  func booleanValueReturnsBoolForBooleans() {
    #expect(JSON.boolean(true).booleanValue == true)
    #expect(JSON.boolean(false).booleanValue == false)
  }

  @Test("booleanValue returns nil for non-booleans")
  func booleanValueReturnsNilForNonBooleans() {
    #expect(JSON.object([:]).booleanValue == nil)
    #expect(JSON.array([]).booleanValue == nil)
    #expect(JSON.number(1).booleanValue == nil)
    #expect(JSON.string("true").booleanValue == nil)
    #expect(JSON.null.booleanValue == nil)
  }

  // MARK: - Data Initializer Tests

  @Test("Initializer parses JSON object from data")
  func initializerParsesObjectFromData() throws {
    let data = Data(#"{"name": "John", "age": 30}"#.utf8)
    let json = try JSON(data)
    #expect(json.isObject)
    #expect(json.objectValue?["name"]?.stringValue == "John")
    #expect(json.objectValue?["age"]?.numberValue == 30)
  }

  @Test("Initializer parses empty JSON object from data")
  func initializerParsesEmptyObjectFromData() throws {
    let data = Data("{}".utf8)
    let json = try JSON(data)
    #expect(json.isObject)
    #expect(json.objectValue?.isEmpty == true)
  }

  @Test("Initializer parses JSON array from data")
  func initializerParsesArrayFromData() throws {
    let data = Data("[1, 2, 3]".utf8)
    let json = try JSON(data)
    #expect(json.isArray)
    #expect(json.arrayValue?.count == 3)
    #expect(json.arrayValue?[0].numberValue == 1)
    #expect(json.arrayValue?[1].numberValue == 2)
    #expect(json.arrayValue?[2].numberValue == 3)
  }

  @Test("Initializer parses empty JSON array from data")
  func initializerParsesEmptyArrayFromData() throws {
    let data = Data("[]".utf8)
    let json = try JSON(data)
    #expect(json.isArray)
    #expect(json.arrayValue?.isEmpty == true)
  }

  @Test("Initializer parses JSON string from data")
  func initializerParsesStringFromData() throws {
    let data = Data(#""hello world""#.utf8)
    let json = try JSON(data)
    #expect(json.isString)
    #expect(json.stringValue == "hello world")
  }

  @Test("Initializer parses empty JSON string from data")
  func initializerParsesEmptyStringFromData() throws {
    let data = Data(#""""#.utf8)
    let json = try JSON(data)
    #expect(json.isString)
    // Optional `String?`: `== ""` asserts present-and-empty, which `isEmpty` cannot express.
    // swiftlint:disable:next empty_string
    #expect(json.stringValue == "")
  }

  @Test("Initializer parses JSON number from data")
  func initializerParsesNumberFromData() throws {
    let data = Data("42.5".utf8)
    let json = try JSON(data)
    #expect(json.isNumber)
    #expect(json.numberValue == 42.5)
  }

  @Test("Initializer parses negative JSON number from data")
  func initializerParsesNegativeNumberFromData() throws {
    let data = Data("-123.456".utf8)
    let json = try JSON(data)
    #expect(json.isNumber)
    #expect(json.numberValue == -123.456)
  }

  @Test("Initializer parses integer JSON number from data")
  func initializerParsesIntegerFromData() throws {
    let data = Data("42".utf8)
    let json = try JSON(data)
    #expect(json.isNumber)
    #expect(json.numberValue == 42)
  }

  @Test("Initializer parses JSON true from data")
  func initializerParsesTrueFromData() throws {
    let data = Data("true".utf8)
    let json = try JSON(data)
    #expect(json.isBoolean)
    #expect(json.booleanValue == true)
  }

  @Test("Initializer parses JSON false from data")
  func initializerParsesFalseFromData() throws {
    let data = Data("false".utf8)
    let json = try JSON(data)
    #expect(json.isBoolean)
    #expect(json.booleanValue == false)
  }

  @Test("Initializer parses JSON null from data")
  func initializerParsesNullFromData() throws {
    let data = Data("null".utf8)
    let json = try JSON(data)
    #expect(json.isNull)
  }

  @Test("Initializer parses nested JSON structure from data")
  func initializerParsesNestedStructureFromData() throws {
    let jsonString = """
      {
          "users": [
              {"id": 1, "name": "Alice", "active": true},
              {"id": 2, "name": "Bob", "active": false}
          ],
          "metadata": {
              "count": 2,
              "version": "1.0"
          }
      }
      """
    let data = Data(jsonString.utf8)
    let json = try JSON(data)

    #expect(json.isObject)

    let users = json.objectValue?["users"]
    #expect(users?.isArray == true)
    #expect(users?.arrayValue?.count == 2)

    let alice = users?.arrayValue?[0]
    #expect(alice?.objectValue?["id"]?.numberValue == 1)
    #expect(alice?.objectValue?["name"]?.stringValue == "Alice")
    #expect(alice?.objectValue?["active"]?.booleanValue == true)

    let metadata = json.objectValue?["metadata"]
    #expect(metadata?.isObject == true)
    #expect(metadata?.objectValue?["count"]?.numberValue == 2)
    #expect(metadata?.objectValue?["version"]?.stringValue == "1.0")
  }

  @Test("Initializer parses mixed type array from data")
  func initializerParsesMixedTypeArrayFromData() throws {
    let data = Data(#"["string", 42, true, null, {"key": "value"}]"#.utf8)
    let json = try JSON(data)

    #expect(json.isArray)
    #expect(json.arrayValue?.count == 5)
    #expect(json.arrayValue?[0].stringValue == "string")
    #expect(json.arrayValue?[1].numberValue == 42)
    #expect(json.arrayValue?[2].booleanValue == true)
    #expect(json.arrayValue?[3].isNull == true)
    #expect(json.arrayValue?[4].isObject == true)
    #expect(json.arrayValue?[4].objectValue?["key"]?.stringValue == "value")
  }

  @Test("Initializer parses string with escape sequences from data")
  func initializerParsesStringWithEscapeSequencesFromData() throws {
    let data = Data(#""line1\nline2\ttab\"quote\\backslash""#.utf8)
    let json = try JSON(data)
    #expect(json.isString)
    #expect(json.stringValue == "line1\nline2\ttab\"quote\\backslash")
  }

  @Test("Initializer parses unicode string from data")
  func initializerParsesUnicodeStringFromData() throws {
    let data = Data(#""こんにちは 🌍""#.utf8)
    let json = try JSON(data)
    #expect(json.isString)
    #expect(json.stringValue == "こんにちは 🌍")
  }

  @Test("Initializer parses scientific notation number from data")
  func initializerParsesScientificNotationFromData() throws {
    let data = Data("1.5e10".utf8)
    let json = try JSON(data)
    #expect(json.isNumber)
    #expect(json.numberValue == 1.5e10)
  }

  @Test("Initializer throws for invalid JSON")
  func initializerThrowsForInvalidJSON() {
    let data = Data("not valid json".utf8)
    #expect(throws: DecodingError.self) {
      _ = try JSON(data)
    }
  }

  @Test("Initializer throws for truncated JSON")
  func initializerThrowsForTruncatedJSON() {
    let data = Data(#"{"key": "value"#.utf8)
    #expect(throws: DecodingError.self) {
      _ = try JSON(data)
    }
  }

  @Test("Initializer returns nil for empty data")
  func initializerReturnsNilForEmptyData() throws {
    #expect(try JSON(Data()) == nil)
  }

  @Test("Initializer parses zero from data")
  func initializerParsesZeroFromData() throws {
    let data = Data("0".utf8)
    let json = try JSON(data)
    #expect(json.isNumber)
    #expect(json.numberValue == 0)
  }

  @Test("Initializer parses negative zero from data")
  func initializerParsesNegativeZeroFromData() throws {
    let data = Data("-0".utf8)
    let json = try JSON(data)
    #expect(json.isNumber)
    #expect(json.numberValue == 0)
  }

  @Test("Initializer parses deeply nested structure from data")
  func initializerParsesDeeplyNestedStructureFromData() throws {
    let data = Data(#"{"a": {"b": {"c": {"d": {"e": "deep"}}}}}"#.utf8)
    let json = try JSON(data)
    #expect(json.isObject)
    let deep = json.objectValue?["a"]?.objectValue?["b"]?.objectValue?["c"]?.objectValue?["d"]?
      .objectValue?["e"]
    #expect(deep?.stringValue == "deep")
  }

  @Test("Initializer parses deeply nested array from data")
  func initializerParsesDeeplyNestedArrayFromData() throws {
    let data = Data("[[[[[1]]]]]".utf8)
    let json = try JSON(data)
    #expect(json.isArray)
    let deep = json.arrayValue?[0].arrayValue?[0].arrayValue?[0].arrayValue?[0].arrayValue?[0]
    #expect(deep?.numberValue == 1)
  }

  @Test("Initializer parses JSON with whitespace from data")
  func initializerParsesJSONWithWhitespaceFromData() throws {
    let data = Data("  {  \"key\"  :  \"value\"  }  ".utf8)
    let json = try JSON(data)
    #expect(json.isObject)
    #expect(json.objectValue?["key"]?.stringValue == "value")
  }

  @Test("Initializer parses JSON with newlines from data")
  func initializerParsesJSONWithNewlinesFromData() throws {
    let jsonString = """
      {
          "key": "value"
      }
      """
    let data = Data(jsonString.utf8)
    let json = try JSON(data)
    #expect(json.isObject)
    #expect(json.objectValue?["key"]?.stringValue == "value")
  }

  @Test("Initializer parses unicode escape sequence from data")
  func initializerParsesUnicodeEscapeSequenceFromData() throws {
    let data = Data(#""\u0048\u0065\u006c\u006c\u006f""#.utf8)
    let json = try JSON(data)
    #expect(json.isString)
    #expect(json.stringValue == "Hello")
  }

  @Test("Initializer parses large integer from data")
  func initializerParsesLargeIntegerFromData() throws {
    let data = Data("9007199254740992".utf8)
    let json = try JSON(data)
    #expect(json.isNumber)
    #expect(json.numberValue == 9_007_199_254_740_992)
  }

  @Test("Initializer parses very small number from data")
  func initializerParsesVerySmallNumberFromData() throws {
    let data = Data("0.000000001".utf8)
    let json = try JSON(data)
    #expect(json.isNumber)
    #expect(json.numberValue == 0.000000001)
  }

  @Test("Initializer parses negative exponent from data")
  func initializerParsesNegativeExponentFromData() throws {
    let data = Data("1e-10".utf8)
    let json = try JSON(data)
    #expect(json.isNumber)
    #expect(json.numberValue == 1e-10)
  }

  @Test("Initializer parses object with special key names from data")
  func initializerParsesObjectWithSpecialKeyNamesFromData() throws {
    let data = Data(#"{"": "empty", "with space": "value", "with\nnewline": "value2"}"#.utf8)
    let json = try JSON(data)
    #expect(json.isObject)
    #expect(json.objectValue?[""]?.stringValue == "empty")
    #expect(json.objectValue?["with space"]?.stringValue == "value")
    #expect(json.objectValue?["with\nnewline"]?.stringValue == "value2")
  }

  @Test("Initializer parses array with all null values from data")
  func initializerParsesArrayWithAllNullValuesFromData() throws {
    let data = Data("[null, null, null]".utf8)
    let json = try JSON(data)
    #expect(json.isArray)
    #expect(json.arrayValue?.count == 3)
    #expect(json.arrayValue?.allSatisfy { $0.isNull } == true)
  }

  @Test("Initializer throws for single quotes")
  func initializerThrowsForSingleQuotes() {
    let data = Data("{'key': 'value'}".utf8)
    #expect(throws: DecodingError.self) {
      _ = try JSON(data)
    }
  }

  @Test("Initializer throws for unquoted keys")
  func initializerThrowsForUnquotedKeys() {
    let data = Data("{key: \"value\"}".utf8)
    #expect(throws: DecodingError.self) {
      _ = try JSON(data)
    }
  }

  // MARK: - Round-trip Encoding Tests

  @Test("JSON object survives encode/decode round-trip")
  func objectSurvivesRoundTrip() throws {
    let original: JSON = ["name": "John", "age": 30, "active": true]
    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSON(encoded)
    #expect(decoded == original)
  }

  @Test("JSON array survives encode/decode round-trip")
  func arraySurvivesRoundTrip() throws {
    let original: JSON = [1, "two", true, nil]
    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSON(encoded)
    #expect(decoded == original)
  }

  @Test("Complex JSON survives encode/decode round-trip")
  func complexJSONSurvivesRoundTrip() throws {
    let original: JSON = [
      "users": [
        ["id": 1, "name": "Alice"],
        ["id": 2, "name": "Bob"]
      ],
      "count": 2,
      "active": true,
      "metadata": nil
    ]
    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSON(encoded)
    #expect(decoded == original)
  }

  @Test("JSON null survives encode/decode round-trip")
  func nullSurvivesRoundTrip() throws {
    let original: JSON = nil
    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSON(encoded)
    #expect(decoded == original)
  }

  @Test("JSON string survives encode/decode round-trip")
  func stringSurvivesRoundTrip() throws {
    let original: JSON = "hello world"
    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSON(encoded)
    #expect(decoded == original)
  }

  @Test("JSON number survives encode/decode round-trip")
  func numberSurvivesRoundTrip() throws {
    let original: JSON = 42.5
    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSON(encoded)
    #expect(decoded == original)
  }

  @Test("JSON boolean survives encode/decode round-trip")
  func booleanSurvivesRoundTrip() throws {
    let originalTrue: JSON = true
    let originalFalse: JSON = false

    let encodedTrue = try JSONEncoder().encode(originalTrue)
    let encodedFalse = try JSONEncoder().encode(originalFalse)

    let decodedTrue = try JSON(encodedTrue)
    let decodedFalse = try JSON(encodedFalse)

    #expect(decodedTrue == originalTrue)
    #expect(decodedFalse == originalFalse)
  }

  // MARK: - Resource File Validation Tests

  static let objectResourceFiles = [
    "editor-asset-manifest-test-case-1",
    "editor-settings-test-case-1",
    "post-test-case-1",
    "post-test-case-163",
    "post-types-test-case-page",
    "post-types-test-case-post",
    "preload-list-custom-post-type",
    "preload-list-empty-body",
    "preload-list-page-type",
    "preload-list-post-type",
    "preload-list-with-accept-header",
    "preload-list-with-link-header",
    "preload-list-with-multiple-headers",
    "preload-list-with-post-data",
    "settings-test-case-1"
  ]

  static let arrayResourceFiles = [
    "theme-test-case-1"
  ]

  @Test("Parses JSON object resource file", arguments: objectResourceFiles)
  func parsesJSONObjectResourceFile(name: String) throws {
    let url = Bundle.module.url(forResource: name, withExtension: "json")!
    let data = try Data(contentsOf: url)
    let json = try JSON(data)
    #expect(json.isObject)
  }

  @Test("Parses JSON array resource file", arguments: arrayResourceFiles)
  func parsesJSONArrayResourceFile(name: String) throws {
    let url = Bundle.module.url(forResource: name, withExtension: "json")!
    let data = try Data(contentsOf: url)
    let json = try JSON(data)
    #expect(json.isArray)
  }
}
