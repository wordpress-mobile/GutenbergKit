import Foundation
import Testing
@testable import GutenbergKitHTTP

/// Tests multipart/form-data parsing per RFC 7578.
@Suite("RFC 7578 Conformance")
struct RFC7578ConformanceTests {

    // MARK: - Content-Type / Boundary Extraction

    @Test("RFC 7578 §4.1: Content-Type with boundary parameter is preserved")
    func contentTypeWithBoundary() throws {
        let request = try parse(fields: [("field1", nil, nil, "value1")], boundary: "AaB03x")

        #expect(request.header("Content-Type") == "multipart/form-data; boundary=AaB03x")
    }

    @Test("RFC 7578 §4.1: Content-Type with quoted boundary extracts correctly")
    func contentTypeWithQuotedBoundary() throws {
        let boundary = "----WebKitFormBoundary7MA4YWxk"
        let body = "--\(boundary)\r\nContent-Disposition: form-data; name=\"field1\"\r\n\r\nvalue1\r\n--\(boundary)--\r\n"
        let raw = "POST /wp/v2/media HTTP/1.1\r\nHost: localhost\r\nContent-Type: multipart/form-data; boundary=\"\(boundary)\"\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let parser = HTTPRequestParser(raw)
        let request = try #require(try parser.parseRequest())
        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        #expect(parts[0].name == "field1")
    }

    @Test("RFC 7578 §4.1: non-multipart Content-Type throws notMultipartFormData")
    func nonMultipartContentTypeThrows() throws {
        let body = #"{"title":"Test"}"#
        let raw = "POST /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let parser = HTTPRequestParser(raw)
        let request = try #require(try parser.parseRequest())

        #expect(throws: MultipartParseError.notMultipartFormData) {
            try request.multipartParts()
        }
    }

    @Test("RFC 7578 §4.1: missing boundary parameter throws notMultipartFormData")
    func missingBoundaryThrows() throws {
        let body = "some data"
        let raw = "POST /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\nContent-Type: multipart/form-data\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let parser = HTTPRequestParser(raw)
        let request = try #require(try parser.parseRequest())

        #expect(throws: MultipartParseError.notMultipartFormData) {
            try request.multipartParts()
        }
    }

    // MARK: - Single Text Field

    @Test("RFC 7578 §4.2: single text field parsed correctly")
    func singleTextField() throws {
        let request = try parse(fields: [("title", nil, nil, "My Blog Post")], boundary: "AaB03x")
        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        #expect(parts[0].name == "title")
        #expect(parts[0].filename == nil)
        #expect(parts[0].contentType == "text/plain")
        #expect(try readAll(parts[0].body) == Data("My Blog Post".utf8))
    }

    @Test("RFC 7578 §4.2: field with empty value")
    func fieldWithEmptyValue() throws {
        let request = try parse(fields: [("excerpt", nil, nil, "")], boundary: "AaB03x")
        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        #expect(parts[0].name == "excerpt")
        #expect(try readAll(parts[0].body) == Data())
    }

    // MARK: - Multiple Fields

    @Test("RFC 7578 §4.2: multiple text fields in order")
    func multipleTextFields() throws {
        let request = try parse(fields: [
            ("title", nil, nil, "My Post"),
            ("status", nil, nil, "publish"),
            ("content", nil, nil, "<p>Hello world</p>"),
        ], boundary: "AaB03x")
        let parts = try request.multipartParts()

        #expect(parts.count == 3)
        #expect(parts[0].name == "title")
        #expect(try readAll(parts[0].body) == Data("My Post".utf8))
        #expect(parts[1].name == "status")
        #expect(try readAll(parts[1].body) == Data("publish".utf8))
        #expect(parts[2].name == "content")
        #expect(try readAll(parts[2].body) == Data("<p>Hello world</p>".utf8))
    }

    // MARK: - File Upload

    @Test("RFC 7578 §4.2: file upload with filename and content-type")
    func fileUploadWithFilename() throws {
        let fileContent = "Hello, this is a test file."
        let request = try parse(fields: [
            ("file", "test.txt", "text/plain", fileContent),
        ], boundary: "AaB03x")
        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        #expect(parts[0].name == "file")
        #expect(parts[0].filename == "test.txt")
        #expect(parts[0].contentType == "text/plain")
        #expect(try readAll(parts[0].body) == Data(fileContent.utf8))
    }

    @Test("RFC 7578 §4.2: file upload with application/octet-stream")
    func fileUploadOctetStream() throws {
        let request = try parse(fields: [
            ("upload", "data.bin", "application/octet-stream", "binary-content"),
        ], boundary: "boundary42")
        let parts = try request.multipartParts()

        #expect(parts[0].filename == "data.bin")
        #expect(parts[0].contentType == "application/octet-stream")
    }

    @Test("RFC 7578 §4.4: part without Content-Type defaults to text/plain")
    func partWithoutContentTypeDefaultsToTextPlain() throws {
        let request = try parse(fields: [("field", nil, nil, "value")], boundary: "AaB03x")
        let parts = try request.multipartParts()

        #expect(parts[0].contentType == "text/plain")
    }

    // MARK: - Mixed Fields and Files

    @Test("RFC 7578 §4.2: form with text fields and file upload")
    func formWithTextAndFile() throws {
        let request = try parse(fields: [
            ("title", nil, nil, "My Image Post"),
            ("file", "image.jpg", "image/jpeg", "JFIF-binary-data"),
        ], boundary: "AaB03x")
        let parts = try request.multipartParts()

        #expect(parts.count == 2)
        #expect(parts[0].name == "title")
        #expect(parts[0].filename == nil)
        #expect(parts[1].name == "file")
        #expect(parts[1].filename == "image.jpg")
        #expect(parts[1].contentType == "image/jpeg")
    }

    // MARK: - Section 5.1 (Multiple Files for One Field)

    @Test("RFC 7578 §5.1: multiple files with same field name in separate parts")
    func multipleFilesWithSameFieldName() throws {
        let request = try parse(fields: [
            ("documents", "file1.txt", "text/plain", "First file"),
            ("documents", "file2.txt", "text/plain", "Second file"),
        ], boundary: "AaB03x")
        let parts = try request.multipartParts()

        #expect(parts.count == 2)
        #expect(parts[0].name == "documents")
        #expect(parts[0].filename == "file1.txt")
        #expect(try readAll(parts[0].body) == Data("First file".utf8))
        #expect(parts[1].name == "documents")
        #expect(parts[1].filename == "file2.txt")
        #expect(try readAll(parts[1].body) == Data("Second file".utf8))
    }

    // MARK: - Section 5.1.2 (Filenames with Special Characters)

    @Test("RFC 7578 §5.1.2: filename with spaces")
    func filenameWithSpaces() throws {
        let request = try parse(fields: [
            ("file", "my document.pdf", "application/pdf", "pdf-data"),
        ], boundary: "AaB03x")
        let parts = try request.multipartParts()

        #expect(parts[0].filename == "my document.pdf")
    }

    @Test("RFC 7578 §5.1.2: filename with percent-encoded UTF-8")
    func filenameWithPercentEncodedUTF8() throws {
        let request = try parse(fields: [
            ("file", "caf%C3%A9.txt", "text/plain", "data"),
        ], boundary: "AaB03x")
        let parts = try request.multipartParts()

        // The parser preserves the raw filename — percent-decoding is the caller's concern
        #expect(parts[0].filename == "caf%C3%A9.txt")
    }

    @Test("RFC 7578 §5.1.2: filename with direct UTF-8 encoding")
    func filenameWithDirectUTF8() throws {
        let request = try parse(fields: [
            ("file", "café.txt", "text/plain", "data"),
        ], boundary: "AaB03x")
        let parts = try request.multipartParts()

        #expect(parts[0].filename == "café.txt")
    }

    // MARK: - Section 5.1.3 (_charset_ Field)

    @Test("RFC 7578 §5.1.3: _charset_ field is parsed as a normal field")
    func charsetFieldParsed() throws {
        let request = try parse(fields: [
            ("_charset_", nil, nil, "UTF-8"),
            ("title", nil, nil, "My Post"),
        ], boundary: "AaB03x")
        let parts = try request.multipartParts()

        #expect(parts.count == 2)
        #expect(parts[0].name == "_charset_")
        #expect(try readAll(parts[0].body) == Data("UTF-8".utf8))
    }

    // MARK: - Part Content-Type Variations

    @Test("RFC 7578 §4.4: part with charset parameter in Content-Type")
    func partWithCharsetParameter() throws {
        let boundary = "AaB03x"
        let body = "--\(boundary)\r\nContent-Disposition: form-data; name=\"bio\"\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nHello world\r\n--\(boundary)--\r\n"
        let request = try parseRaw(body: body, boundary: boundary)
        let parts = try request.multipartParts()

        #expect(parts[0].contentType == "text/plain; charset=UTF-8")
    }

    // MARK: - Boundary Edge Cases

    @Test("RFC 7578: boundary with hyphens (common browser format)")
    func boundaryWithHyphens() throws {
        let request = try parse(
            fields: [("title", nil, nil, "test")],
            boundary: "----WebKitFormBoundary7MA4YWxkTrZu0gW"
        )
        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        #expect(parts[0].name == "title")
    }

    @Test("RFC 7578: long boundary (70 characters)")
    func longBoundary() throws {
        let request = try parse(
            fields: [("f", nil, nil, "v")],
            boundary: String(repeating: "x", count: 70)
        )
        let parts = try request.multipartParts()

        #expect(parts.count == 1)
    }

    @Test("RFC 7578: body content resembling boundary is not split")
    func bodyContentResemblingBoundary() throws {
        let boundary = "AaB03x"
        let body = "--\(boundary)\r\nContent-Disposition: form-data; name=\"data\"\r\n\r\n--AaB03 not a boundary\r\n--\(boundary)--\r\n"
        let request = try parseRaw(body: body, boundary: boundary)
        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        #expect(try readAll(parts[0].body) == Data("--AaB03 not a boundary".utf8))
    }

    // MARK: - Error Cases

    @Test("RFC 7578: part missing Content-Disposition throws error")
    func missingContentDisposition() throws {
        let boundary = "AaB03x"
        let body = "--\(boundary)\r\nContent-Type: text/plain\r\n\r\nvalue\r\n--\(boundary)--\r\n"
        let request = try parseRaw(body: body, boundary: boundary)

        #expect(throws: MultipartParseError.missingContentDisposition) {
            try request.multipartParts()
        }
    }

    @Test("RFC 7578: part missing name parameter throws error")
    func missingNameParameter() throws {
        let boundary = "AaB03x"
        let body = "--\(boundary)\r\nContent-Disposition: form-data\r\n\r\nvalue\r\n--\(boundary)--\r\n"
        let request = try parseRaw(body: body, boundary: boundary)

        #expect(throws: MultipartParseError.missingNameParameter) {
            try request.multipartParts()
        }
    }

    @Test("RFC 7578: malformed body throws error")
    func malformedBody() throws {
        let boundary = "AaB03x"
        let body = "this is not multipart at all"
        let request = try parseRaw(body: body, boundary: boundary)

        #expect(throws: MultipartParseError.malformedBody) {
            try request.multipartParts()
        }
    }

    @Test("RFC 7578: incomplete request throws missingBody")
    func incompleteRequestThrowsMissingBody() throws {
        let parser = HTTPRequestParser("POST /wp/v2/media HTTP/1.1\r\nHost: localhost\r\nContent-Type: multipart/form-data; boundary=AaB03x\r\nContent-Length: 1000\r\n\r\npartial")
        let request = try #require(try parser.parseRequest())

        // Request is partial — body not fully received
        #expect(!request.isComplete)
        #expect(throws: MultipartParseError.missingBody) {
            try request.multipartParts()
        }
    }

    // MARK: - Incremental Arrival

    @Test("RFC 7578: multipart body arriving incrementally parses correctly")
    func multipartBodyArrivingIncrementally() throws {
        let boundary = "AaB03x"
        let body = "--\(boundary)\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\nMy Post\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"content\"\r\n\r\n<p>Hello</p>\r\n--\(boundary)--\r\n"
        let headers = "POST /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\nContent-Type: multipart/form-data; boundary=\(boundary)\r\nContent-Length: \(body.utf8.count)\r\n\r\n"

        let parser = HTTPRequestParser()
        parser.append(Data(headers.utf8))

        let bodyData = Data(body.utf8)
        let midpoint = bodyData.count / 2
        parser.append(bodyData[0..<midpoint])
        parser.append(bodyData[midpoint...])

        let request = try #require(try parser.parseRequest())
        let parts = try request.multipartParts()

        #expect(parts.count == 2)
        #expect(parts[0].name == "title")
        #expect(try readAll(parts[0].body) == Data("My Post".utf8))
        #expect(parts[1].name == "content")
        #expect(try readAll(parts[1].body) == Data("<p>Hello</p>".utf8))
    }

    // MARK: - Large Bodies

    @Test("RFC 7578: large part body is captured completely")
    func largePartBody() throws {
        let largeContent = String(repeating: "x", count: 10000)
        let request = try parse(fields: [("content", nil, nil, largeContent)], boundary: "AaB03x")
        let parts = try request.multipartParts()

        #expect(try readAll(parts[0].body) == Data(largeContent.utf8))
    }

    // MARK: - Body Content Edge Cases

    @Test("RFC 7578: binary data (non-UTF-8 bytes) in part body")
    func binaryDataInPartBody() throws {
        // PNG file signature bytes (includes 0x0D 0x0A which is CRLF)
        let binaryBytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let binaryData = Data(binaryBytes)
        let boundary = "AaB03x"

        var bodyData = Data()
        bodyData.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"image.png\"\r\nContent-Type: image/png\r\n\r\n".utf8))
        bodyData.append(binaryData)
        bodyData.append(Data("\r\n--\(boundary)--\r\n".utf8))

        let raw = "POST /wp/v2/media HTTP/1.1\r\nHost: localhost\r\nContent-Type: multipart/form-data; boundary=\(boundary)\r\nContent-Length: \(bodyData.count)\r\n\r\n"

        let parser = HTTPRequestParser()
        parser.append(Data(raw.utf8))
        parser.append(bodyData)

        let request = try #require(try parser.parseRequest())
        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        #expect(parts[0].name == "file")
        #expect(parts[0].filename == "image.png")
        #expect(try readAll(parts[0].body) == binaryData)
    }

    @Test("RFC 7578: part body containing CRLF sequences")
    func partBodyContainingCRLF() throws {
        let boundary = "AaB03x"
        let body = "--\(boundary)\r\nContent-Disposition: form-data; name=\"content\"\r\n\r\nline1\r\nline2\r\nline3\r\n--\(boundary)--\r\n"
        let request = try parseRaw(body: body, boundary: boundary)
        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        #expect(try readAll(parts[0].body) == Data("line1\r\nline2\r\nline3".utf8))
    }

    @Test("RFC 7578: part body containing text resembling a different closing delimiter")
    func partBodyResemblingOtherClosingDelimiter() throws {
        let boundary = "AaB03x"
        let body = "--\(boundary)\r\nContent-Disposition: form-data; name=\"data\"\r\n\r\nsome --other-- text\r\n--\(boundary)--\r\n"
        let request = try parseRaw(body: body, boundary: boundary)
        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        #expect(try readAll(parts[0].body) == Data("some --other-- text".utf8))
    }

    @Test("RFC 2046: empty multipart body with only close delimiter throws malformedBody")
    func emptyMultipartBodyThrows() throws {
        let boundary = "AaB03x"
        // RFC 2046 requires at least one body part
        let body = "--\(boundary)--\r\n"
        let request = try parseRaw(body: body, boundary: boundary)

        #expect(throws: MultipartParseError.malformedBody) {
            try request.multipartParts()
        }
    }

    // MARK: - Header Edge Cases

    @Test("RFC 7578: Content-Disposition with extra whitespace around parameters")
    func contentDispositionExtraWhitespace() throws {
        let boundary = "AaB03x"
        let body = "--\(boundary)\r\nContent-Disposition: form-data;  name=\"field1\"\r\n\r\nvalue1\r\n--\(boundary)--\r\n"
        let request = try parseRaw(body: body, boundary: boundary)
        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        #expect(parts[0].name == "field1")
    }

    @Test("RFC 7578: Content-Disposition name with escaped quotes")
    func contentDispositionEscapedQuotes() throws {
        let boundary = "AaB03x"
        let body = "--\(boundary)\r\nContent-Disposition: form-data; name=\"field\\\"name\"\r\n\r\nvalue\r\n--\(boundary)--\r\n"
        let request = try parseRaw(body: body, boundary: boundary)
        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        #expect(parts[0].name == "field\"name")
    }

    @Test("RFC 7578: additional part headers beyond Content-Disposition and Content-Type are ignored")
    func additionalPartHeadersIgnored() throws {
        let boundary = "AaB03x"
        let body = "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"test.txt\"\r\nContent-Type: text/plain\r\nContent-Transfer-Encoding: binary\r\nX-Custom-Header: custom-value\r\n\r\nfile content\r\n--\(boundary)--\r\n"
        let request = try parseRaw(body: body, boundary: boundary)
        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        #expect(parts[0].name == "file")
        #expect(parts[0].contentType == "text/plain")
        #expect(try readAll(parts[0].body) == Data("file content".utf8))
    }

    @Test("RFC 7578: case-insensitive Content-Disposition header name")
    func caseInsensitiveContentDisposition() throws {
        let boundary = "AaB03x"
        let body = "--\(boundary)\r\ncontent-disposition: form-data; name=\"field1\"\r\n\r\nvalue1\r\n--\(boundary)--\r\n"
        let request = try parseRaw(body: body, boundary: boundary)
        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        #expect(parts[0].name == "field1")
    }

    @Test("RFC 7578: case-insensitive form-data token in Content-Disposition")
    func caseInsensitiveFormData() throws {
        let boundary = "AaB03x"
        let body = "--\(boundary)\r\nContent-Disposition: FORM-DATA; name=\"field1\"\r\n\r\nvalue1\r\n--\(boundary)--\r\n"
        let request = try parseRaw(body: body, boundary: boundary)
        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        #expect(parts[0].name == "field1")
    }

    // MARK: - Boundary Edge Cases

    @Test("RFC 7578 §4.2: name= inside another parameter's quoted value is not matched")
    func nameInsideQuotedValueNotMatched() throws {
        let boundary = "AaB03x"
        let body = "--\(boundary)\r\nContent-Disposition: form-data; dummy=\"name=evil\"; name=\"real\"\r\n\r\nvalue\r\n--\(boundary)--\r\n"
        let raw = "POST /upload HTTP/1.1\r\nHost: localhost\r\nContent-Type: multipart/form-data; boundary=\(boundary)\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let parser = HTTPRequestParser(raw)
        let request = try #require(try parser.parseRequest())
        let parts = try request.multipartParts()

        #expect(parts[0].name == "real")
    }

    @Test("RFC 2045 §5.1: quoted boundary with backslash-escaped single-quote")
    func quotedBoundaryWithEscapedSingleQuote() throws {
        let unescapedBoundary = "abc'def"
        let body = "--\(unescapedBoundary)\r\nContent-Disposition: form-data; name=\"field\"\r\n\r\nvalue\r\n--\(unescapedBoundary)--\r\n"
        let raw = "POST /upload HTTP/1.1\r\nHost: localhost\r\nContent-Type: multipart/form-data; boundary=\"abc\\'def\"\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let parser = HTTPRequestParser(raw)
        let request = try #require(try parser.parseRequest())
        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        #expect(parts[0].name == "field")
    }

    @Test("RFC 2045 §5.1: boundary= inside another parameter's quoted value is not matched")
    func boundaryInsideQuotedParameterNotMatched() throws {
        let realBoundary = "RealBoundary123"
        let body = "--\(realBoundary)\r\nContent-Disposition: form-data; name=\"field\"\r\n\r\nvalue\r\n--\(realBoundary)--\r\n"
        let raw = "POST /upload HTTP/1.1\r\nHost: localhost\r\nContent-Type: multipart/form-data; charset=\"boundary=fake\"; boundary=\(realBoundary)\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let parser = HTTPRequestParser(raw)
        let request = try #require(try parser.parseRequest())
        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        #expect(parts[0].name == "field")
    }

    @Test("RFC 7578: boundary with special characters (plus, equals, slash)")
    func boundaryWithSpecialCharacters() throws {
        let boundary = "abc+def/ghi=123"
        let request = try parse(fields: [("field", nil, nil, "value")], boundary: boundary)
        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        #expect(parts[0].name == "field")
    }

    @Test("RFC 2046: preamble before first boundary is ignored")
    func preambleBeforeFirstBoundaryIgnored() throws {
        let boundary = "AaB03x"
        let body = "This is the preamble. It should be ignored.\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"field1\"\r\n\r\nvalue1\r\n--\(boundary)--\r\n"
        let request = try parseRaw(body: body, boundary: boundary)
        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        #expect(parts[0].name == "field1")
        #expect(try readAll(parts[0].body) == Data("value1".utf8))
    }

    @Test("RFC 2046: epilogue after closing boundary is ignored")
    func epilogueAfterClosingBoundaryIgnored() throws {
        let boundary = "AaB03x"
        let body = "--\(boundary)\r\nContent-Disposition: form-data; name=\"field1\"\r\n\r\nvalue1\r\n--\(boundary)--\r\nThis is the epilogue. It should be ignored.\r\n"
        let request = try parseRaw(body: body, boundary: boundary)
        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        #expect(parts[0].name == "field1")
        #expect(try readAll(parts[0].body) == Data("value1".utf8))
    }

    @Test("RFC 2046 §5.1.1: transport padding between parts does not corrupt body data")
    func transportPaddingBetweenPartsDoesNotCorruptBody() throws {
        let boundary = "AaB03x"
        // Transport padding (spaces) after the boundary delimiter, between two parts.
        // RFC 2046 §5.1.1: delimiter = CRLF "--" boundary *( SP / HTAB ) CRLF
        // The parser should strip the padding so it doesn't end up in part bodies.
        let body = "--\(boundary)  \r\nContent-Disposition: form-data; name=\"field1\"\r\n\r\nvalue1\r\n--\(boundary)  \r\nContent-Disposition: form-data; name=\"field2\"\r\n\r\nvalue2\r\n--\(boundary)--\r\n"
        let request = try parseRaw(body: body, boundary: boundary)
        let parts = try request.multipartParts()

        #expect(parts.count == 2)
        #expect(parts[0].name == "field1")
        // The body should be exactly "value1", not "value1" with trailing padding artifacts.
        #expect(try readAll(parts[0].body) == Data("value1".utf8))
        #expect(parts[1].name == "field2")
        #expect(try readAll(parts[1].body) == Data("value2".utf8))
    }

    @Test("RFC 2046 §5.1.1: transport padding (tabs) after boundary does not corrupt headers")
    func transportPaddingTabsDoNotCorruptHeaders() throws {
        let boundary = "AaB03x"
        // Tabs after the boundary delimiter before the CRLF
        let body = "--\(boundary)\t\t\r\nContent-Disposition: form-data; name=\"field1\"\r\n\r\nvalue1\r\n--\(boundary)--\r\n"
        let request = try parseRaw(body: body, boundary: boundary)
        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        // The name should be "field1" — padding should not cause header parsing to break.
        #expect(parts[0].name == "field1")
        #expect(try readAll(parts[0].body) == Data("value1".utf8))
    }

    // MARK: - WordPress / Real-World Scenarios

    @Test("WordPress: media upload with file and metadata fields")
    func wordPressMediaUpload() throws {
        let request = try parse(fields: [
            ("title", nil, nil, "My Featured Image"),
            ("alt_text", nil, nil, "A beautiful sunset over the mountains"),
            ("caption", nil, nil, "Photo taken at Yosemite National Park"),
            ("description", nil, nil, "Full resolution sunset photo"),
            ("file", "sunset.jpg", "image/jpeg", "JFIF-binary-data-here"),
        ], boundary: "----WebKitFormBoundary7MA4YWxk")
        let parts = try request.multipartParts()

        #expect(parts.count == 5)
        #expect(parts[0].name == "title")
        #expect(try readAll(parts[0].body) == Data("My Featured Image".utf8))
        #expect(parts[1].name == "alt_text")
        #expect(try readAll(parts[1].body) == Data("A beautiful sunset over the mountains".utf8))
        #expect(parts[2].name == "caption")
        #expect(parts[3].name == "description")
        #expect(parts[4].name == "file")
        #expect(parts[4].filename == "sunset.jpg")
        #expect(parts[4].contentType == "image/jpeg")
    }

    @Test("WordPress: multiple image uploads in a single request")
    func multipleImageUploads() throws {
        let request = try parse(fields: [
            ("files", "photo1.jpg", "image/jpeg", "jpeg-data-1"),
            ("files", "photo2.png", "image/png", "png-data-2"),
            ("files", "photo3.gif", "image/gif", "gif-data-3"),
        ], boundary: "----WebKitFormBoundary9876")
        let parts = try request.multipartParts()

        #expect(parts.count == 3)
        #expect(parts[0].filename == "photo1.jpg")
        #expect(parts[0].contentType == "image/jpeg")
        #expect(parts[1].filename == "photo2.png")
        #expect(parts[1].contentType == "image/png")
        #expect(parts[2].filename == "photo3.gif")
        #expect(parts[2].contentType == "image/gif")
        #expect(try readAll(parts[0].body) == Data("jpeg-data-1".utf8))
        #expect(try readAll(parts[1].body) == Data("png-data-2".utf8))
        #expect(try readAll(parts[2].body) == Data("gif-data-3".utf8))
    }

    @Test("WordPress: file upload with zero-byte body (empty file)")
    func emptyFileUpload() throws {
        let request = try parse(fields: [
            ("file", "empty.txt", "text/plain", ""),
        ], boundary: "AaB03x")
        let parts = try request.multipartParts()

        #expect(parts.count == 1)
        #expect(parts[0].name == "file")
        #expect(parts[0].filename == "empty.txt")
        #expect(try readAll(parts[0].body) == Data())
    }

    // MARK: - Part Count Limit

    @Test("rejects multipart body with more than 100 parts")
    func tooManyParts() throws {
        var fields: [(name: String, filename: String?, contentType: String?, value: String)] = []
        for i in 0..<101 {
            fields.append(("field\(i)", nil, nil, "value\(i)"))
        }
        let request = try parse(fields: fields, boundary: "AaB03x")

        #expect(throws: MultipartParseError.tooManyParts) {
            try request.multipartParts()
        }
    }

    @Test("accepts multipart body with exactly 100 parts")
    func maxPartsAccepted() throws {
        var fields: [(name: String, filename: String?, contentType: String?, value: String)] = []
        for i in 0..<100 {
            fields.append(("field\(i)", nil, nil, "value\(i)"))
        }
        let request = try parse(fields: fields, boundary: "AaB03x")
        let parts = try request.multipartParts()

        #expect(parts.count == 100)
    }

    // MARK: - Helpers

    /// Builds a multipart/form-data request from field descriptors and parses it.
    private func parse(
        fields: [(name: String, filename: String?, contentType: String?, value: String)],
        boundary: String
    ) throws -> ParsedHTTPRequest {
        var bodyParts: [String] = []
        for field in fields {
            var partHeaders = "Content-Disposition: form-data; name=\"\(field.name)\""
            if let filename = field.filename {
                partHeaders += "; filename=\"\(filename)\""
            }
            if let ct = field.contentType {
                partHeaders += "\r\nContent-Type: \(ct)"
            }
            bodyParts.append("--\(boundary)\r\n\(partHeaders)\r\n\r\n\(field.value)")
        }
        let body = bodyParts.joined(separator: "\r\n") + "\r\n--\(boundary)--\r\n"

        return try parseRaw(body: body, boundary: boundary)
    }

    private func parseRaw(body: String, boundary: String) throws -> ParsedHTTPRequest {
        let raw = "POST /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\nContent-Type: multipart/form-data; boundary=\(boundary)\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let parser = HTTPRequestParser(raw)
        return try #require(try parser.parseRequest())
    }
}
