import Foundation
import Testing
@testable import GutenbergKit

@Suite
final class EditorConfigurationTests {

    @Test
    func testValidJavaScriptIdentifiers() throws {
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
            _ = try WebViewGlobal(name: identifier, value: .string("test"))
        }
    }

    @Test
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
            #expect(throws: WebViewGlobalError.self, performing: {
                try WebViewGlobal(name: identifier, value: .string("test"))
            })
        }
    }

    // MARK: - WebViewGlobalValue Tests
    @Test
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
            #expect(WebViewGlobalValue.string(input).toJavaScript() == expected)
        }
    }

    @Test
    func testNumberValueConversion() {
        let testCases = [
            (42.0, "42.0"),
            (-3.14, "-3.14"),
            (0.0, "0.0"),
            (1.0, "1.0")
        ]

        for (input, expected) in testCases {
            #expect(WebViewGlobalValue.number(input).toJavaScript() == expected)
        }
    }

    @Test
    func testBooleanValueConversion() {
        #expect(WebViewGlobalValue.boolean(true).toJavaScript() == "true")
        #expect(WebViewGlobalValue.boolean(false).toJavaScript() == "false")
    }

    @Test
    func testNullValueConversion() {
        #expect(WebViewGlobalValue.null.toJavaScript() == "null")
    }

    @Test
    func testObjectValueConversion() throws {
        let object = WebViewGlobalValue.object([
            "name": .string("test"),
            "count": .number(42),
            "active": .boolean(true),
            "nested": .object([
                "value": .string("nested")
            ])
        ])

        let actual = object.toJavaScript()
        let expected = "{\"active\": true,\"count\": 42.0,\"name\": \"test\",\"nested\": {\"value\": \"nested\"}}"
        #expect(actual == expected)
    }

    @Test
    func testArrayValueConversion() {
        let array = WebViewGlobalValue.array([
            .string("test"),
            .number(42),
            .boolean(true),
            .null
        ])

        let expected = "[\"test\",42.0,true,null]"
        #expect(array.toJavaScript() == expected)
    }
}
