import Foundation
import Testing
@testable import GutenbergKitHTTP

/// Tests that the HTTP parser correctly preserves RFC 8941 Structured Field Values.
///
/// Our parser treats field values as opaque strings — it does not parse structured
/// fields internally. These tests verify that all RFC 8941 syntax constructs pass
/// through the parser without being mangled, truncated, or misinterpreted.
@Suite("RFC 8941 Conformance")
struct RFC8941ConformanceTests {

    // MARK: - Section 3.1 (Lists)

    @Test("RFC 8941 §3.1: simple list of tokens")
    func simpleListOfTokens() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-List: sugar, tea, rum\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-List") == "sugar, tea, rum")
    }

    @Test("RFC 8941 §3.1: list with parameters on members")
    func listWithParameters() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-List: abc;a=1;b=2, cde_456\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-List") == "abc;a=1;b=2, cde_456")
    }

    @Test("RFC 8941 §3.1: empty list is represented by absent header")
    func emptyListAbsentHeader() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-List") == nil)
    }

    @Test("RFC 8941 §3.1: list with inner lists")
    func listWithInnerLists() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-List: (\"foo\" \"bar\"), (\"baz\"), (\"bat\" \"one\"), ()\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-List") == "(\"foo\" \"bar\"), (\"baz\"), (\"bat\" \"one\"), ()")
    }

    @Test("RFC 8941 §3.1: list with parameterised inner lists")
    func listWithParameterisedInnerLists() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-List: (\"foo\";a=1;b=2);lvl=5, (\"bar\" \"baz\");lvl=1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-List") == "(\"foo\";a=1;b=2);lvl=5, (\"bar\" \"baz\");lvl=1")
    }

    @Test("RFC 8941 §3.1: list spread across multiple header lines is combined")
    func listSpreadAcrossMultipleHeaderLines() throws {
        // RFC 8941 notes that list-based fields can be split across multiple lines
        // and combined per RFC 9110 §5.3
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-List: sugar, tea\r\nExample-List: rum\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-List") == "sugar, tea, rum")
    }

    // MARK: - Section 3.2 (Dictionaries)

    @Test("RFC 8941 §3.2: simple dictionary")
    func simpleDictionary() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Dict: en=\"Applepie\", da=:w4teleAA=:\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Dict") == "en=\"Applepie\", da=:w4teleAA=:")
    }

    @Test("RFC 8941 §3.2: dictionary with boolean true values (value omitted)")
    func dictionaryWithBooleanTrueOmitted() throws {
        // When a dictionary value is boolean true, the =?1 is omitted
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Dict: a=?0, b, c; foo=bar\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Dict") == "a=?0, b, c; foo=bar")
    }

    @Test("RFC 8941 §3.2: dictionary with inner list values")
    func dictionaryWithInnerListValues() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Dict: rating=1.5, feelings=(joy sadness)\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Dict") == "rating=1.5, feelings=(joy sadness)")
    }

    @Test("RFC 8941 §3.2: dictionary with parameters on members")
    func dictionaryWithParametersOnMembers() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Dict: abc=123;a=1;b=2, def=456, ghi=789;q=9;r=\"+w\"\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Dict") == "abc=123;a=1;b=2, def=456, ghi=789;q=9;r=\"+w\"")
    }

    @Test("RFC 8941 §3.2: dictionary spread across multiple header lines")
    func dictionarySpreadAcrossMultipleHeaderLines() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Dict: a=1, b=2\r\nExample-Dict: c=3\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Dict") == "a=1, b=2, c=3")
    }

    // MARK: - Section 3.3 (Items)

    @Test("RFC 8941 §3.3: item with parameters")
    func itemWithParameters() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Item: 5;foo=bar\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Item") == "5;foo=bar")
    }

    // MARK: - Section 3.3.1 (Integers)

    @Test("RFC 8941 §3.3.1: positive integer")
    func positiveInteger() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Integer: 42\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Integer") == "42")
    }

    @Test("RFC 8941 §3.3.1: negative integer")
    func negativeInteger() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Integer: -42\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Integer") == "-42")
    }

    @Test("RFC 8941 §3.3.1: zero")
    func zeroInteger() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Integer: 0\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Integer") == "0")
    }

    @Test("RFC 8941 §3.3.1: maximum 15-digit integer")
    func maximumInteger() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Integer: 999999999999999\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Integer") == "999999999999999")
    }

    @Test("RFC 8941 §3.3.1: minimum 15-digit negative integer")
    func minimumInteger() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Integer: -999999999999999\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Integer") == "-999999999999999")
    }

    // MARK: - Section 3.3.2 (Decimals)

    @Test("RFC 8941 §3.3.2: simple decimal")
    func simpleDecimal() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Decimal: 4.5\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Decimal") == "4.5")
    }

    @Test("RFC 8941 §3.3.2: negative decimal")
    func negativeDecimal() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Decimal: -3.14\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Decimal") == "-3.14")
    }

    @Test("RFC 8941 §3.3.2: decimal with three fractional digits (maximum precision)")
    func decimalMaxPrecision() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Decimal: 123456789012.123\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Decimal") == "123456789012.123")
    }

    // MARK: - Section 3.3.3 (Strings)

    @Test("RFC 8941 §3.3.3: simple string")
    func simpleString() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-String: \"hello world\"\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-String") == "\"hello world\"")
    }

    @Test("RFC 8941 §3.3.3: string with escaped backslash")
    func stringWithEscapedBackslash() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-String: \"path\\\\to\\\\file\"\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-String") == "\"path\\\\to\\\\file\"")
    }

    @Test("RFC 8941 §3.3.3: string with escaped double quote")
    func stringWithEscapedQuote() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-String: \"she said \\\"hi\\\"\"\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-String") == "\"she said \\\"hi\\\"\"")
    }

    @Test("RFC 8941 §3.3.3: empty string")
    func emptyString() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-String: \"\"\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-String") == "\"\"")
    }

    @Test("RFC 8941 §3.3.3: string with special printable ASCII characters")
    func stringWithSpecialASCII() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-String: \"!#$%&'()*+,-./:;<=>?@[]^_`{|}~\"\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-String") == "\"!#$%&'()*+,-./:;<=>?@[]^_`{|}~\"")
    }

    // MARK: - Section 3.3.4 (Tokens)

    @Test("RFC 8941 §3.3.4: simple token")
    func simpleToken() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Token: foo123\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Token") == "foo123")
    }

    @Test("RFC 8941 §3.3.4: token starting with asterisk")
    func tokenStartingWithAsterisk() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Token: *foo\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Token") == "*foo")
    }

    @Test("RFC 8941 §3.3.4: token with colon and slash")
    func tokenWithColonAndSlash() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Token: foo/bar:baz\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Token") == "foo/bar:baz")
    }

    @Test("RFC 8941 §3.3.4: token with tchar characters")
    func tokenWithTcharCharacters() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Token: application/x-www-form-urlencoded\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Token") == "application/x-www-form-urlencoded")
    }

    // MARK: - Section 3.3.5 (Byte Sequences)

    @Test("RFC 8941 §3.3.5: base64-encoded byte sequence")
    func base64ByteSequence() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-ByteSeq: :cHJldGVuZCB0aGlzIGlzIGJpbmFyeS8=:\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-ByteSeq") == ":cHJldGVuZCB0aGlzIGlzIGJpbmFyeS8=:")
    }

    @Test("RFC 8941 §3.3.5: empty byte sequence")
    func emptyByteSequence() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-ByteSeq: ::\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-ByteSeq") == "::")
    }

    @Test("RFC 8941 §3.3.5: byte sequence colon delimiters are not confused with header field syntax")
    func byteSequenceColonsNotConfusedWithFieldSyntax() throws {
        // The colons in :base64: must not be misinterpreted by the header parser
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-ByteSeq: :AQID:\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-ByteSeq") == ":AQID:")
    }

    // MARK: - Section 3.3.6 (Booleans)

    @Test("RFC 8941 §3.3.6: boolean true")
    func booleanTrue() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Boolean: ?1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Boolean") == "?1")
    }

    @Test("RFC 8941 §3.3.6: boolean false")
    func booleanFalse() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Boolean: ?0\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Boolean") == "?0")
    }

    // MARK: - Section 3.1.2 (Parameters)

    @Test("RFC 8941 §3.1.2: parameters with various value types")
    func parametersWithVariousTypes() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Param: token;str=\"val\";int=42;dec=1.5;bool=?1;bin=:AQID:\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Param") == "token;str=\"val\";int=42;dec=1.5;bool=?1;bin=:AQID:")
    }

    @Test("RFC 8941 §3.1.2: boolean true parameter with value omitted")
    func booleanTrueParameterOmitted() throws {
        // Serialised form of a boolean true parameter omits =?1
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Item: 1; a; b=?0\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Item") == "1; a; b=?0")
    }

    @Test("RFC 8941 §3.1.2: multiple parameters with same key — last wins")
    func duplicateParameterKeysLastWins() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Item: token;a=1;a=2\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        // Parser preserves the raw value — structured field parsing is application-level
        #expect(request.header("Example-Item") == "token;a=1;a=2")
    }

    @Test("RFC 8941 §3.1.2: parameter keys use lowercase and special characters")
    func parameterKeysLowercaseAndSpecial() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Item: token;*key=1;a-b=2;c.d=3;e_f=4\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Item") == "token;*key=1;a-b=2;c.d=3;e_f=4")
    }

    // MARK: - Section 3.1.1 (Inner Lists)

    @Test("RFC 8941 §3.1.1: inner list with parameters on items and list")
    func innerListWithParametersOnItemsAndList() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-List: (\"foo\";a=1 \"bar\";b=2);lvl=5\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-List") == "(\"foo\";a=1 \"bar\";b=2);lvl=5")
    }

    @Test("RFC 8941 §3.1.1: empty inner list")
    func emptyInnerList() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-List: ()\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-List") == "()")
    }

    @Test("RFC 8941 §3.1.1: inner list with mixed item types")
    func innerListWithMixedTypes() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-List: (token 42 3.14 \"string\" ?1 :AQID:)\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-List") == "(token 42 3.14 \"string\" ?1 :AQID:)")
    }

    // MARK: - Complex / Real-World Structured Headers

    @Test("RFC 8941: Priority header (RFC 9218) uses structured dictionary")
    func priorityHeader() throws {
        // Priority is a real-world structured dictionary header
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nPriority: u=3, i\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Priority") == "u=3, i")
    }

    @Test("RFC 8941: complex nested structure with all types")
    func complexNestedStructure() throws {
        let value = "a=(1 2.0 \"three\");q=0.9, b=:AQID:;flag, c=token;*key=?0"
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Complex: \(value)\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Complex") == value)
    }

    @Test("RFC 8941: value with semicolons is not split by parser")
    func semicolonsNotSplitByParser() throws {
        // Semicolons in structured field values must not be misinterpreted
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Item: token;a=1;b=2;c=3\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        // The entire value including semicolons must be preserved as one string
        #expect(request.header("Example-Item") == "token;a=1;b=2;c=3")
    }

    @Test("RFC 8941: value with parentheses is not misinterpreted")
    func parenthesesNotMisinterpreted() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-List: (a b c), (d e)\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-List") == "(a b c), (d e)")
    }

    @Test("RFC 8941: value with equals signs is not misinterpreted")
    func equalsSignsNotMisinterpreted() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Dict: a=1, b=\"hello=world\", c=:YQ==:\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        // Equals signs in strings and base64 must be preserved
        #expect(request.header("Example-Dict") == "a=1, b=\"hello=world\", c=:YQ==:")
    }

    @Test("RFC 8941: value with question marks is not misinterpreted")
    func questionMarksNotMisinterpreted() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Dict: enabled=?1, disabled=?0\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Dict") == "enabled=?1, disabled=?0")
    }
}
