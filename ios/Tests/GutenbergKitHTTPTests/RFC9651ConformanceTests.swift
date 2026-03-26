import Foundation
import Testing
@testable import GutenbergKitHTTP

/// Tests that the HTTP parser correctly preserves RFC 9651 Structured Field Values.
///
/// RFC 9651 obsoletes RFC 8941 and adds two new bare item types: Date (`@timestamp`)
/// and Display String (`%"encoded"`). Our parser treats field values as opaque strings,
/// so these tests verify that the new syntax passes through without being mangled.
@Suite("RFC 9651 Conformance")
struct RFC9651ConformanceTests {

    // MARK: - Section 3.3.7 (Dates)

    @Test("RFC 9651 §3.3.7: date as positive Unix timestamp")
    func datePositiveTimestamp() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Date: @1659578233\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Date") == "@1659578233")
    }

    @Test("RFC 9651 §3.3.7: date as negative Unix timestamp (before epoch)")
    func dateNegativeTimestamp() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Date: @-62135596800\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Date") == "@-62135596800")
    }

    @Test("RFC 9651 §3.3.7: date at Unix epoch (zero)")
    func dateAtEpoch() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Date: @0\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Date") == "@0")
    }

    @Test("RFC 9651 §3.3.7: date with parameters")
    func dateWithParameters() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Date: @1659578233;source=server\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Date") == "@1659578233;source=server")
    }

    @Test("RFC 9651 §3.3.7: date in a list with other types")
    func dateInListWithOtherTypes() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-List: @1659578233, \"label\", 42\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-List") == "@1659578233, \"label\", 42")
    }

    @Test("RFC 9651 §3.3.7: date in a dictionary")
    func dateInDictionary() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Dict: created=@1659578233, modified=@1659600000\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Dict") == "created=@1659578233, modified=@1659600000")
    }

    @Test("RFC 9651 §3.3.7: date as parameter value")
    func dateAsParameterValue() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Item: token;expires=@1700000000\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Item") == "token;expires=@1700000000")
    }

    @Test("RFC 9651 §3.3.7: @ sign in date is not confused with other syntax")
    func atSignNotConfused() throws {
        // The @ prefix must not be misinterpreted by the parser
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Date: @253402214400\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Date") == "@253402214400")
    }

    // MARK: - Section 3.3.8 (Display Strings)

    @Test("RFC 9651 §3.3.8: display string with ASCII-only content")
    func displayStringASCIIOnly() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-DisplayStr: %\"hello world\"\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-DisplayStr") == "%\"hello world\"")
    }

    @Test("RFC 9651 §3.3.8: display string with percent-encoded Unicode")
    func displayStringWithPercentEncodedUnicode() throws {
        // ü = U+00FC = UTF-8 bytes C3 BC → %c3%bc
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-DisplayStr: %\"This is intended for display to %c3%bcsers.\"\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-DisplayStr") == "%\"This is intended for display to %c3%bcsers.\"")
    }

    @Test("RFC 9651 §3.3.8: display string with escaped percent sign")
    func displayStringWithEscapedPercent() throws {
        // Literal % in content is encoded as %25
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-DisplayStr: %\"100%25 complete\"\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-DisplayStr") == "%\"100%25 complete\"")
    }

    @Test("RFC 9651 §3.3.8: display string with encoded double quote")
    func displayStringWithEncodedQuote() throws {
        // " in content is encoded as %22
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-DisplayStr: %\"she said %22hi%22\"\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-DisplayStr") == "%\"she said %22hi%22\"")
    }

    @Test("RFC 9651 §3.3.8: empty display string")
    func emptyDisplayString() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-DisplayStr: %\"\"\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-DisplayStr") == "%\"\"")
    }

    @Test("RFC 9651 §3.3.8: display string with CJK characters encoded")
    func displayStringWithCJK() throws {
        // 日 = U+65E5 = UTF-8 bytes E6 97 A5 → %e6%97%a5
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-DisplayStr: %\"%e6%97%a5%e6%9c%ac%e8%aa%9e\"\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-DisplayStr") == "%\"%e6%97%a5%e6%9c%ac%e8%aa%9e\"")
    }

    @Test("RFC 9651 §3.3.8: display string with parameters")
    func displayStringWithParameters() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Item: %\"Caf%c3%a9\";lang=fr\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Item") == "%\"Caf%c3%a9\";lang=fr")
    }

    @Test("RFC 9651 §3.3.8: display string in a list")
    func displayStringInList() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-List: %\"Hello\", %\"Caf%c3%a9\", %\"%e4%b8%96%e7%95%8c\"\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-List") == "%\"Hello\", %\"Caf%c3%a9\", %\"%e4%b8%96%e7%95%8c\"")
    }

    @Test("RFC 9651 §3.3.8: display string in a dictionary")
    func displayStringInDictionary() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Dict: en=%\"English\", fr=%\"Fran%c3%a7ais\"\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Dict") == "en=%\"English\", fr=%\"Fran%c3%a7ais\"")
    }

    @Test("RFC 9651 §3.3.8: %\" prefix is not confused with percent-encoding in URLs")
    func percentQuotePrefixNotConfused() throws {
        // The %"..." syntax must be preserved as-is
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-DisplayStr: %\"test\"\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        let value = request.header("Example-DisplayStr")
        #expect(value == "%\"test\"")
        #expect(value?.hasPrefix("%\"") == true)
        #expect(value?.hasSuffix("\"") == true)
    }

    // MARK: - Mixed Types (RFC 9651 + RFC 8941)

    @Test("RFC 9651: all eight bare item types in a single list")
    func allEightTypesInList() throws {
        // Integer, Decimal, String, Token, Byte Sequence, Boolean, Date, Display String
        let value = "42, 3.14, \"hello\", token, :AQID:, ?1, @1659578233, %\"Caf%c3%a9\""
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-List: \(value)\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-List") == value)
    }

    @Test("RFC 9651: all eight types as dictionary values")
    func allEightTypesAsDictValues() throws {
        let value = "int=42, dec=3.14, str=\"hi\", tok=token, bin=:AA==:, bool=?0, date=@0, disp=%\"ok\""
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Dict: \(value)\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Dict") == value)
    }

    @Test("RFC 9651: all eight types as parameter values")
    func allEightTypesAsParamValues() throws {
        let value = "item;i=42;d=3.14;s=\"hi\";t=tok;b=:AA==:;f=?1;dt=@0;ds=%\"ok\""
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-Item: \(value)\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-Item") == value)
    }

    @Test("RFC 9651: new types in inner lists")
    func newTypesInInnerLists() throws {
        let value = "(@1659578233 %\"label\");priority=1, (@1700000000 %\"other\")"
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-List: \(value)\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-List") == value)
    }

    @Test("RFC 9651: date and display string spread across multiple header lines")
    func newTypesAcrossMultipleLines() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-List: @1659578233\r\nExample-List: %\"Caf%c3%a9\"\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-List") == "@1659578233, %\"Caf%c3%a9\"")
    }

    @Test("RFC 9651: display string with control character encoding")
    func displayStringWithControlCharEncoding() throws {
        // Control characters (0x00-0x1F) must be percent-encoded in display strings
        // Tab (0x09) → %09, Newline (0x0A) → %0a
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-DisplayStr: %\"line1%0aline2%09tabbed\"\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-DisplayStr") == "%\"line1%0aline2%09tabbed\"")
    }

    @Test("RFC 9651: display string with DEL character encoding")
    func displayStringWithDELEncoding() throws {
        // DEL (0x7F) must be percent-encoded → %7f
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-DisplayStr: %\"before%7fafter\"\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-DisplayStr") == "%\"before%7fafter\"")
    }

    @Test("RFC 9651: display string percent-encoding uses lowercase hex")
    func displayStringLowercaseHex() throws {
        // RFC 9651 specifies lowercase hex digits in percent-encoding
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nExample-DisplayStr: %\"%c3%bc%c3%a9%c3%b1\"\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Example-DisplayStr") == "%\"%c3%bc%c3%a9%c3%b1\"")
    }
}
