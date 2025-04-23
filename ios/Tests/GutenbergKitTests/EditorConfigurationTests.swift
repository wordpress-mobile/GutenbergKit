import XCTest
@testable import GutenbergKit

final class EditorConfigurationTests: XCTestCase {

    // MARK: - WebViewGlobal Tests

    func testValidJavaScriptIdentifiers() {
        let validIdentifiers = [
            "myVar",
            "_privateVar",
            "$jQuery",
            "myVar123",
            "MY_CONSTANT",
            "a",
            "A"
        ]

        for identifier in validIdentifiers {
            XCTAssertNoThrow(try WebViewGlobal(name: identifier, value: .string("test")))
        }
    }

    func testInvalidJavaScriptIdentifiers() {
        let invalidIdentifiers = [
            "123invalid",
            "my-var",
            "my.var",
            "my var",
            "",
            "my@var",
            "my#var"
        ]

        for identifier in invalidIdentifiers {
            XCTAssertThrowsError(try WebViewGlobal(name: identifier, value: .string("test")))
        }
    }

    // MARK: - WebViewGlobalValue Tests

    func testStringValueConversion() {
        let testCases = [
            ("simple", "\"simple\""),
            ("with \"quotes\"", "\"with \\\"quotes\\\"\""),
            ("with\nnewline", "\"with\\nnewline\""),
            ("with\ttab", "\"with\\ttab\""),
            ("with\rreturn", "\"with\\rreturn\""),
            ("with\u{8}backspace", "\"with\\bbackspace\""),
            ("with\u{12}formfeed", "\"with\\fformfeed\"")
        ]

        for (input, expected) in testCases {
            let value = WebViewGlobalValue.string(input)
            XCTAssertEqual(value.toJavaScript(), expected)
        }
    }

    func testNumberValueConversion() {
        let testCases = [
            (42.0, "42.0"),
            (-3.14, "-3.14"),
            (0.0, "0.0"),
            (1.0, "1.0")
        ]

        for (input, expected) in testCases {
            let value = WebViewGlobalValue.number(input)
            XCTAssertEqual(value.toJavaScript(), expected)
        }
    }

    func testBooleanValueConversion() {
        XCTAssertEqual(WebViewGlobalValue.boolean(true).toJavaScript(), "true")
        XCTAssertEqual(WebViewGlobalValue.boolean(false).toJavaScript(), "false")
    }

    func testNullValueConversion() {
        XCTAssertEqual(WebViewGlobalValue.null.toJavaScript(), "null")
    }

    func testObjectValueConversion() {
        let object = WebViewGlobalValue.object([
            "name": .string("test"),
            "count": .number(42),
            "active": .boolean(true),
            "nested": .object([
                "value": .string("nested")
            ])
        ])

        let actual = object.toJavaScript()
        let expected = "{\"name\": \"test\",\"active\": true,\"count\": 42.0,\"nested\": {\"value\": \"nested\"}}"

        guard let actualData = actual.data(using: .utf8),
              let expectedData = expected.data(using: .utf8),
              let actualJSON = try? JSONSerialization.jsonObject(with: actualData) as? [String: Any],
              let expectedJSON = try? JSONSerialization.jsonObject(with: expectedData) as? [String: Any] else {
            XCTFail("Failed to parse JSON")
            return
        }

        XCTAssertEqual(actualJSON as NSDictionary, expectedJSON as NSDictionary)
    }

    func testArrayValueConversion() {
        let array = WebViewGlobalValue.array([
            .string("test"),
            .number(42),
            .boolean(true),
            .null
        ])

        let expected = "[\"test\",42.0,true,null]"
        XCTAssertEqual(array.toJavaScript(), expected)
    }
}
