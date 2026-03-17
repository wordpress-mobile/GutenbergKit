import Foundation
import Testing
@testable import GutenbergKitHTTP

@Suite("HeaderValue")
struct HeaderValueTests {

    // MARK: - Unquoted Values

    @Test("Extracts unquoted parameter value")
    func unquotedValue() {
        let result = HeaderValue.extractParameter("boundary", from: "multipart/form-data; boundary=AaB03x")
        #expect(result == "AaB03x")
    }

    @Test("Unquoted value terminated by semicolon")
    func unquotedValueTerminatedBySemicolon() {
        let result = HeaderValue.extractParameter("boundary", from: "multipart/form-data; boundary=AaB03x; charset=utf-8")
        #expect(result == "AaB03x")
    }

    @Test("Unquoted value at end of string")
    func unquotedValueAtEnd() {
        let result = HeaderValue.extractParameter("charset", from: "text/plain; charset=utf-8")
        #expect(result == "utf-8")
    }

    // MARK: - Quoted Values

    @Test("Extracts quoted parameter value")
    func quotedValue() {
        let result = HeaderValue.extractParameter("name", from: "form-data; name=\"field1\"")
        #expect(result == "field1")
    }

    @Test("Empty quoted value")
    func emptyQuotedValue() {
        let result = HeaderValue.extractParameter("name", from: "form-data; name=\"\"")
        #expect(result == "")
    }

    @Test("Quoted value with spaces")
    func quotedValueWithSpaces() {
        let result = HeaderValue.extractParameter("name", from: "form-data; name=\"my field\"")
        #expect(result == "my field")
    }

    // MARK: - Backslash Escapes

    @Test("Quoted value with escaped quote")
    func escapedQuote() {
        let result = HeaderValue.extractParameter("name", from: #"form-data; name="field\"name""#)
        #expect(result == "field\"name")
    }

    @Test("Quoted value with escaped backslash")
    func escapedBackslash() {
        let result = HeaderValue.extractParameter("filename", from: #"form-data; filename="C:\\path\\file.txt""#)
        #expect(result == "C:\\path\\file.txt")
    }

    @Test("Quoted value with escaped single-quote")
    func escapedSingleQuote() {
        let result = HeaderValue.extractParameter("boundary", from: #"multipart/form-data; boundary="abc\'def""#)
        #expect(result == "abc'def")
    }

    // MARK: - Case Insensitivity

    @Test("Parameter name matching is case-insensitive")
    func caseInsensitive() {
        let result = HeaderValue.extractParameter("Boundary", from: "multipart/form-data; boundary=AaB03x")
        #expect(result == "AaB03x")
    }

    // MARK: - Skipping Quoted Strings

    @Test("Parameter inside another quoted value is not matched")
    func paramInsideQuotedValueSkipped() {
        let result = HeaderValue.extractParameter("name", from: #"form-data; dummy="name=evil"; name="real""#)
        #expect(result == "real")
    }

    @Test("boundary= inside quoted value is skipped")
    func boundaryInsideQuotedValueSkipped() {
        let result = HeaderValue.extractParameter("boundary", from: #"multipart/form-data; charset="boundary=fake"; boundary=RealBoundary"#)
        #expect(result == "RealBoundary")
    }

    // MARK: - Missing Parameters

    @Test("Missing parameter returns nil")
    func missingParameter() {
        let result = HeaderValue.extractParameter("filename", from: "form-data; name=\"field1\"")
        #expect(result == nil)
    }

    @Test("Empty header value returns nil")
    func emptyHeaderValue() {
        let result = HeaderValue.extractParameter("name", from: "")
        #expect(result == nil)
    }

    // MARK: - Multiple Parameters

    @Test("Extracts correct parameter when multiple are present")
    func multipleParameters() {
        let result = HeaderValue.extractParameter("filename", from: "form-data; name=\"file\"; filename=\"photo.jpg\"")
        #expect(result == "photo.jpg")
    }

    // MARK: - Substring Matching

    @Test("Does not match parameter name as substring of another parameter name")
    func noSubstringMatch() {
        // "name=" appears inside "filename=" — should not match it.
        let result = HeaderValue.extractParameter("name", from: #"form-data; filename="test.jpg"; name="real""#)
        #expect(result == "real")
    }

    // MARK: - Edge Cases

    @Test("Unterminated quoted value returns accumulated content")
    func unterminatedQuotedValue() {
        let result = HeaderValue.extractParameter("name", from: "form-data; name=\"unclosed")
        #expect(result == "unclosed")
    }

    @Test("Quoted value containing semicolons")
    func quotedValueWithSemicolons() {
        let result = HeaderValue.extractParameter("name", from: "form-data; name=\"a;b;c\"")
        #expect(result == "a;b;c")
    }

    @Test("No space after semicolon")
    func noSpaceAfterSemicolon() {
        let result = HeaderValue.extractParameter("name", from: "form-data;name=\"field1\"")
        #expect(result == "field1")
    }

    @Test("Backslash at end of quoted value")
    func backslashAtEndOfQuotedValue() {
        // Backslash with nothing after it — should stop extraction.
        let result = HeaderValue.extractParameter("name", from: #"form-data; name="trailing\"#)
        #expect(result == "trailing")
    }
}
