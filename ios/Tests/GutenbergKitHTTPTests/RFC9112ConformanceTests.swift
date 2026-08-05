import Foundation
import Testing
@testable import GutenbergKitHTTP

@Suite("RFC 9112 Conformance")
struct RFC9112ConformanceTests {

    // MARK: - Section 2.1 (Message Format)

    @Test("RFC 9112 §2.1: empty input yields needsMoreData")
    func emptyInputIsNeedsMoreData() throws {
        let parser = HTTPRequestParser()
        #expect(!parser.state.hasHeaders)
        #expect(!parser.state.isComplete)
        #expect(try parser.parseRequest() == nil)
    }

    @Test("RFC 9112 §2.1: request line without terminating CRLF is incomplete")
    func requestLineWithoutTerminatingCRLF() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1")
        #expect(!parser.state.hasHeaders)
        #expect(try parser.parseRequest() == nil)
    }

    @Test("RFC 9112 §2.1: headers without final CRLF CRLF are incomplete")
    func headersWithoutFinalSeparator() throws {
        let parser = HTTPRequestParser("GET /wp/v2/media HTTP/1.1\r\nHost: localhost")
        #expect(!parser.state.hasHeaders)
        #expect(try parser.parseRequest() == nil)
    }

    @Test("RFC 9112 §2.1: bare LF line endings are not recognized as header terminator")
    func bareLFNotRecognizedAsTerminator() throws {
        // RFC says MAY recognize bare LF — our parser requires CRLF
        let parser = HTTPRequestParser("GET /wp/v2/blocks HTTP/1.1\nHost: localhost\n\n")
        #expect(!parser.state.hasHeaders)
        #expect(try parser.parseRequest() == nil)
    }

    @Test("RFC 9112 §2.1: request without Content-Length is immediately complete")
    func requestWithoutContentLengthIsComplete() throws {
        let parser = HTTPRequestParser("POST /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        // RFC §6.3 Step 7: no Content-Length or Transfer-Encoding means body length is zero
        #expect(parser.state.isComplete)
        #expect(request.body == nil)
    }

    // MARK: - Section 3 (Request Line)

    @Test("RFC 9112 §3: request line with only method is invalid")
    func requestLineWithOnlyMethod() {
        let parser = HTTPRequestParser("GET\r\nHost: localhost\r\n\r\n")

        #expect(throws: HTTPRequestParseError.malformedRequestLine) {
            try parser.parseRequest()
        }
    }

    @Test("RFC 9112 §3: request line missing HTTP-version is rejected")
    func requestLineMissingVersion() {
        let parser = HTTPRequestParser("GET /wp/v2/posts\r\nHost: localhost\r\n\r\n")

        #expect(throws: HTTPRequestParseError.invalidHTTPVersion) {
            try parser.parseRequest()
        }
    }

    @Test("RFC 9112 §3: HTTP/1.0 version parses and is stored")
    func http10VersionParses() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.0\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.method == "GET")
        #expect(request.target == "/wp/v2/posts")
        #expect(request.httpVersion == "HTTP/1.0")
    }

    @Test("RFC 9112 §3.1: method token is case-sensitive and preserved verbatim")
    func methodIsCaseSensitive() throws {
        let parser = HTTPRequestParser("get /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.method == "get")
    }

    @Test("RFC 9112 §3.1: non-standard method token is accepted")
    func nonStandardMethod() throws {
        let parser = HTTPRequestParser("PURGE /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.method == "PURGE")
    }

    @Test("RFC 9112 §3.2: non-origin-form request-target is rejected for non-CONNECT methods")
    func invalidTargetFormRejected() {
        // "foo" is not a valid request-target for GET:
        // not origin-form, absolute-form, authority-form, or asterisk-form
        let parser = HTTPRequestParser("GET foo HTTP/1.1\r\nHost: localhost\r\n\r\n")

        #expect(throws: HTTPRequestParseError.self) {
            try parser.parseRequest()
        }
    }

    @Test("RFC 9112 §3.2: space in request-target causes invalid HTTP-version")
    func spaceInTargetCausesInvalidVersion() {
        // split(maxSplits: 2) puts "world HTTP/1.1" in the version field, which is invalid
        let parser = HTTPRequestParser("GET /wp/v2/posts?search=hello world HTTP/1.1\r\nHost: localhost\r\n\r\n")

        #expect(throws: HTTPRequestParseError.invalidHTTPVersion) {
            try parser.parseRequest()
        }
    }

    @Test("RFC 9112 §3.2.1: origin-form with query on root path")
    func originFormQueryOnRoot() throws {
        let parser = HTTPRequestParser("GET /?_embed HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.target == "/?_embed")
    }

    @Test("RFC 9112 §3.2.1: deeply nested origin-form path")
    func deeplyNestedPath() throws {
        let parser = HTTPRequestParser("GET /wp/v2/sites/1/posts/42/revisions/3 HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.target == "/wp/v2/sites/1/posts/42/revisions/3")
    }

    @Test("RFC 9112 §3.2.2: absolute-form with HTTP scheme")
    func absoluteFormHTTPScheme() throws {
        let parser = HTTPRequestParser("GET http://localhost:8080/wp/v2/posts HTTP/1.1\r\nHost: localhost:8080\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.target == "http://localhost:8080/wp/v2/posts")
    }

    @Test("RFC 9112 §3.2.2: absolute-form with query string")
    func absoluteFormWithQuery() throws {
        let parser = HTTPRequestParser("GET http://localhost/wp/v2/posts?per_page=5 HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.target == "http://localhost/wp/v2/posts?per_page=5")
    }

    @Test("RFC 9112 §3.2.3: CONNECT with IPv6 authority-form")
    func connectIPv6Authority() throws {
        let parser = HTTPRequestParser("CONNECT [::1]:443 HTTP/1.1\r\nHost: [::1]:443\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.method == "CONNECT")
        #expect(request.target == "[::1]:443")
    }

    @Test("RFC 9112 §3: long request-target near 8000 octets")
    func longRequestTarget() throws {
        let longQuery = String(repeating: "a", count: 7900)
        let parser = HTTPRequestParser("GET /wp/v2/posts?\(longQuery) HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.method == "GET")
        #expect(request.target.hasPrefix("/wp/v2/posts?"))
        #expect(request.target.count == 7913)
    }

    // MARK: - Section 5 (Field Syntax)

    @Test("RFC 9112 §5.1: strips leading OWS from field value")
    func stripsLeadingOWSFromFieldValue() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nX-WP-Nonce:   \t  abc123\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("X-WP-Nonce") == "abc123")
    }

    @Test("RFC 9112 §5.1: strips trailing OWS from field value")
    func stripsTrailingOWSFromFieldValue() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nX-WP-Total: 42   \r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("X-WP-Total") == "42")
    }

    @Test("RFC 9112 §5.1: empty field value is permitted")
    func emptyFieldValue() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nX-WP-Nonce:\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        // Optional `String?`: `== ""` asserts present-and-empty, which `isEmpty` cannot express.
        // swiftlint:disable:next empty_string
        #expect(request.header("X-WP-Nonce") == "")
    }

    @Test("RFC 9112 §5.1: whitespace-only field value becomes empty after OWS stripping")
    func whitespaceOnlyFieldValueBecomesEmpty() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nX-WP-Nonce:   \t   \r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        // Optional `String?`: `== ""` asserts present-and-empty, which `isEmpty` cannot express.
        // swiftlint:disable:next empty_string
        #expect(request.header("X-WP-Nonce") == "")
    }

    @Test("RFC 9112 §5.1: preserves interior whitespace in field value")
    func preservesInteriorWhitespace() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nAuthorization: Bearer  tok 123\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Authorization") == "Bearer  tok 123")
    }

    @Test("RFC 9112 §5.1: field value with multiple colons")
    func fieldValueWithMultipleColons() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nX-WP-Request-URL: https://example.com:8080/wp/v2/posts?t=12:30:00\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("X-WP-Request-URL") == "https://example.com:8080/wp/v2/posts?t=12:30:00")
    }

    @Test("RFC 9112 §5: preserves original casing of field names")
    func preservesFieldNameCasing() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nX-WP-Nonce: abc\r\nx-wp-total: 10\r\nCONTENT-TYPE: text/html\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.headers["X-WP-Nonce"] == "abc")
        #expect(request.headers["x-wp-total"] == "10")
        #expect(request.headers["CONTENT-TYPE"] == "text/html")
    }

    @Test("RFC 9112 §5: header line without colon is rejected")
    func headerLineWithoutColonIsRejected() {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nNotAValidHeader\r\nHost: localhost\r\n\r\n")

        #expect(throws: HTTPRequestParseError.invalidFieldName) {
            try parser.parseRequest()
        }
    }

    @Test("RFC 9110 §5.3: duplicate header — values combined with comma")
    func duplicateHeaderCombinedWithComma() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nX-WP-Nonce: first\r\nX-WP-Nonce: second\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("X-WP-Nonce") == "first, second")
    }

    // MARK: - Section 6/8 (Message Body and Content-Length)

    @Test("RFC 9112 §6.3: Content-Length larger than body keeps parser incomplete")
    func contentLengthLargerThanBody() throws {
        let parser = HTTPRequestParser("POST /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\nContent-Length: 1000\r\n\r\n{\"title\":\"Short\"}")

        #expect(parser.state.hasHeaders)
        #expect(!parser.state.isComplete)
        #expect(parser.expectedBodyLength == 1000)

        let request = try #require(try parser.parseRequest())
        #expect(!request.isComplete)
    }

    @Test("RFC 9112 §6.3: Content-Length smaller than data sent truncates body")
    func contentLengthSmallerThanDataTruncates() throws {
        let parser = HTTPRequestParser("POST /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\nContent-Length: 5\r\n\r\n{\"title\":\"My Post\"}")
        let request = try #require(try parser.parseRequest())

        #expect(parser.state.isComplete)
        let requestBody = try #require(request.body)
        #expect(try readAll(requestBody) == Data("{\"tit".utf8))
    }

    @Test("RFC 9112 §6.3: headers and partial body in single chunk")
    func headersAndPartialBodyInSingleChunk() throws {
        let body = #"{"title":"My Post","id":42}"#
        let parser = HTTPRequestParser()

        // Headers + partial body in one chunk
        parser.append(Data("POST /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\nContent-Length: \(body.utf8.count)\r\n\r\n{\"title\":\"My".utf8))
        #expect(parser.state.hasHeaders)
        #expect(!parser.state.isComplete)

        // Rest of body
        parser.append(Data(" Post\",\"id\":42}".utf8))
        #expect(parser.state.isComplete)

        let request = try #require(try parser.parseRequest())
        let requestBody = try #require(request.body)
        #expect(try readAll(requestBody) == Data(body.utf8))
    }

    @Test("RFC 9112 §6.2: Content-Length with leading zeros")
    func contentLengthWithLeadingZeros() throws {
        let body = #"{"title":"My Post","id":42}"#
        let parser = HTTPRequestParser("POST /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0027\r\n\r\n\(body)")

        #expect(parser.state.isComplete)
        #expect(parser.expectedBodyLength == 27)
    }

    @Test("RFC 9112 §6.2: Content-Length with leading whitespace in value")
    func contentLengthWithLeadingWhitespace() throws {
        let body = #"{"data":"test"}"#
        let parser = HTTPRequestParser("POST /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\nContent-Length:   \(body.utf8.count)\r\n\r\n\(body)")

        #expect(parser.state.isComplete)
        let request = try #require(try parser.parseRequest())
        let requestBody = try #require(request.body)
        #expect(try readAll(requestBody) == Data(body.utf8))
    }

    @Test("RFC 9112 §6.3: non-numeric Content-Length is rejected as invalid")
    func nonNumericContentLengthRejected() {
        let parser = HTTPRequestParser("POST /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\nContent-Length: abc\r\n\r\n{\"title\":\"Test\"}")

        #expect(throws: HTTPRequestParseError.invalidContentLength) {
            try parser.parseRequest()
        }
    }

    @Test("RFC 9112 §6.3: negative Content-Length is rejected as invalid")
    func negativeContentLengthRejected() {
        let parser = HTTPRequestParser("POST /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\nContent-Length: -1\r\n\r\n{\"title\":\"Test\"}")

        #expect(throws: HTTPRequestParseError.invalidContentLength) {
            try parser.parseRequest()
        }
    }

    @Test("RFC 9112 §6.3: very large Content-Length remains incomplete")
    func veryLargeContentLengthRemainsIncomplete() {
        let parser = HTTPRequestParser("POST /wp/v2/media HTTP/1.1\r\nHost: localhost\r\nContent-Length: 999999999\r\n\r\nsmall body")

        #expect(parser.state.hasHeaders)
        #expect(!parser.state.isComplete)
        #expect(parser.expectedBodyLength == 999999999)
    }

    @Test("RFC 9112 §6.1: Transfer-Encoding chunked is rejected")
    func transferEncodingChunkedRejected() {
        let parser = HTTPRequestParser("POST /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n1b\r\n{\"title\":\"Test\",\"id\":42}\r\n0\r\n\r\n")

        #expect(throws: HTTPRequestParseError.unsupportedTransferEncoding) {
            try parser.parseRequest()
        }
    }

    // MARK: - Error Status Mapping

    @Test("RFC 6585 §5: headersTooLarge error maps to HTTP 431")
    func headersTooLargeIs431() throws {
        let bigHeaderValue = String(repeating: "x", count: 70000)
        let raw = "GET / HTTP/1.1\r\nHost: localhost\r\nX-Big: \(bigHeaderValue)\r\n\r\n"
        let parser = HTTPRequestParser(raw)

        do {
            _ = try parser.parseRequest()
            Issue.record("Expected headersTooLarge error")
        } catch let error as HTTPRequestParseError {
            #expect(error == .headersTooLarge)
            #expect(error.httpStatus == 431)
        }
    }

    // MARK: - Section 4 (Status Line)

    @Test("RFC 9112 §4: HTTPResponse from URLResponse uses standard English reason phrase")
    func responseUsesStandardReasonPhrase() throws {
        let url = URL(string: "http://localhost/test")!
        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: 404,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/plain"]
        )!
        let data = Data("not found".utf8)

        let response = HTTPResponse((data, httpResponse))
        let serialized = String(data: response.serialized(), encoding: .utf8)!

        #expect(serialized.hasPrefix("HTTP/1.1 404 Not Found\r\n"))
    }

    @Test("RFC 9112 §4: out-of-range status codes are clamped to 3DIGIT in serialized output")
    func outOfRangeStatusCodesAreClamped() {
        let negative = String(data: HTTPResponse(status: -1).serialized(), encoding: .utf8)!
        #expect(negative.hasPrefix("HTTP/1.1 000 "))

        let oversize = String(data: HTTPResponse(status: 1000).serialized(), encoding: .utf8)!
        #expect(oversize.hasPrefix("HTTP/1.1 999 "))
    }

    @Test("RFC 9112 §4: statusText matches status code")
    func statusTextMatchesStatusCode() {
        #expect(HTTPResponse(status: 200).statusText == "OK")
        #expect(HTTPResponse(status: 404).statusText == "Not Found")

        let serialized = String(data: HTTPResponse(status: 200).serialized(), encoding: .utf8)!
        #expect(serialized.hasPrefix("HTTP/1.1 200 OK\r\n"))
    }

    // MARK: - Section 4 (Response Sanitization)

    @Test("RFC 9112 §4: sanitize strips NUL from reason phrase")
    func sanitizeStripsNulFromReasonPhrase() {
        let response = HTTPResponse(status: 200, statusText: "OK\0Injected")
        let serialized = String(data: response.serialized(), encoding: .utf8)!
        let statusLine = serialized.components(separatedBy: "\r\n").first!

        #expect(statusLine == "HTTP/1.1 200 OKInjected")
        #expect(!statusLine.contains("\0"))
    }

    @Test("RFC 9112 §4: sanitize strips control characters from header values")
    func sanitizeStripsControlCharsFromHeaderValues() {
        let response = HTTPResponse(
            status: 200,
            headers: [("X-Test", "value\u{07}bell\u{08}backspace")]
        )
        let serialized = String(data: response.serialized(), encoding: .utf8)!

        #expect(!serialized.contains("\u{07}"))
        #expect(!serialized.contains("\u{08}"))
        #expect(serialized.contains("X-Test: valuebellbackspace"))
    }

    @Test("RFC 9112 §4: sanitize strips control characters from header names")
    func sanitizeStripsControlCharsFromHeaderNames() {
        let response = HTTPResponse(
            status: 200,
            headers: [("X\u{00}-Test", "value")]
        )
        let serialized = String(data: response.serialized(), encoding: .utf8)!

        #expect(!serialized.contains("\u{00}"))
        #expect(serialized.contains("X-Test: value"))
    }

    @Test("RFC 9112 §4: Content-Length always matches actual body size")
    func contentLengthAlwaysMatchesBodySize() {
        let response = HTTPResponse(
            status: 200,
            headers: [("Content-Type", "text/plain")],
            body: Data("hello".utf8)
        )
        let serialized = String(data: response.serialized(), encoding: .utf8)!

        #expect(serialized.contains("Content-Length: 5\r\n"))
    }

    @Test("RFC 9112 §4: caller-provided Content-Length is replaced with actual body size")
    func callerContentLengthIsReplaced() {
        let response = HTTPResponse(
            status: 200,
            headers: [("Content-Length", "999"), ("Content-Type", "text/plain")],
            body: Data("hello".utf8)
        )
        let serialized = String(data: response.serialized(), encoding: .utf8)!

        // The wrong Content-Length (999) must not appear
        #expect(!serialized.contains("Content-Length: 999"))
        // The correct Content-Length (5) must be present
        #expect(serialized.contains("Content-Length: 5\r\n"))
    }

    @Test("RFC 9112 §4: case-insensitive Content-Length replacement")
    func caseInsensitiveContentLengthReplacement() {
        let response = HTTPResponse(
            status: 200,
            headers: [("content-length", "0"), ("Content-Type", "text/plain")],
            body: Data("test body".utf8)
        )
        let serialized = String(data: response.serialized(), encoding: .utf8)!

        #expect(!serialized.contains("content-length: 0"))
        #expect(serialized.contains("Content-Length: 9\r\n"))
    }

    @Test("RFC 9110 §7.6.1: hop-by-hop Connection header is stripped from serialized response")
    func connectionHeaderStrippedFromResponse() {
        let response = HTTPResponse(
            status: 200,
            headers: [("Connection", "keep-alive"), ("Content-Type", "text/plain")],
            body: Data("ok".utf8)
        )
        let serialized = String(data: response.serialized(), encoding: .utf8)!

        #expect(!serialized.contains("Connection: keep-alive"))
        #expect(serialized.contains("Connection: close"))
    }

    @Test("RFC 9110 §7.6.1: hop-by-hop Transfer-Encoding header is stripped from serialized response")
    func transferEncodingStrippedFromResponse() {
        let response = HTTPResponse(
            status: 200,
            headers: [("Transfer-Encoding", "chunked"), ("Content-Type", "text/plain")],
            body: Data("ok".utf8)
        )
        let serialized = String(data: response.serialized(), encoding: .utf8)!

        #expect(!serialized.contains("Transfer-Encoding"))
    }

    // MARK: - L2: Sanitization preserves obs-text

    @Test("RFC 9110 §5.5: sanitize preserves obs-text (0x80+) in header values")
    func sanitizePreservesObsText() {
        let response = HTTPResponse(
            status: 200,
            headers: [("X-Test", "caf\u{00e9}")],
            body: Data()
        )
        let serialized = String(data: response.serialized(), encoding: .utf8)!

        #expect(serialized.contains("X-Test: caf\u{00e9}"))
    }

    @Test("RFC 9110 §5.5: sanitize preserves HTAB in header values")
    func sanitizePreservesHTAB() {
        let response = HTTPResponse(
            status: 200,
            headers: [("X-Test", "a\tb")],
            body: Data()
        )
        let serialized = String(data: response.serialized(), encoding: .utf8)!

        #expect(serialized.contains("X-Test: a\tb"))
    }

    // MARK: - L3/L4: Date and Server headers

    @Test("RFC 9110 §6.6.1: Date header is present in HTTP-date format")
    func dateHeaderPresent() {
        let serialized = String(data: HTTPResponse(status: 200).serialized(), encoding: .utf8)!

        let pattern = /Date: \w{3}, \d{2} \w{3} \d{4} \d{2}:\d{2}:\d{2} GMT\r\n/
        #expect(serialized.contains(pattern))
    }

    @Test("RFC 9110 §10.2.4: Server header is present")
    func serverHeaderPresent() {
        let serialized = String(data: HTTPResponse(status: 200).serialized(), encoding: .utf8)!

        #expect(serialized.contains("Server: GutenbergKit\r\n"))
    }

    @Test("caller-provided Date header is replaced, not duplicated")
    func callerDateHeaderReplaced() {
        let response = HTTPResponse(
            status: 200,
            headers: [("Date", "Thu, 01 Jan 1970 00:00:00 GMT")]
        )
        let serialized = String(data: response.serialized(), encoding: .utf8)!

        let dateCount = serialized.components(separatedBy: "Date:").count - 1
        #expect(dateCount == 1)
        #expect(!serialized.contains("Date: Thu, 01 Jan 1970"))
    }

    @Test("caller-provided Server header is replaced, not duplicated")
    func callerServerHeaderReplaced() {
        let response = HTTPResponse(
            status: 200,
            headers: [("Server", "Apache")]
        )
        let serialized = String(data: response.serialized(), encoding: .utf8)!

        #expect(!serialized.contains("Server: Apache"))
        #expect(serialized.contains("Server: GutenbergKit"))
    }

    // MARK: - L5: Orphaned temp file cleanup

    @Test("cleanOrphanedTempFiles removes files in the server-specific temp directory")
    func orphanedTempFilesCleanedOnStart() async throws {
        let serverName = "orphan-cleanup-test"
        let serverTempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GutenbergKitHTTP-\(serverName)")
        try FileManager.default.createDirectory(at: serverTempDir, withIntermediateDirectories: true)

        let orphan1 = serverTempDir.appendingPathComponent("GutenbergKitHTTP-\(UUID().uuidString)")
        let orphan2 = serverTempDir.appendingPathComponent("GutenbergKitHTTP-\(UUID().uuidString)")
        let unrelated = FileManager.default.temporaryDirectory
            .appendingPathComponent("SomeOtherFile-\(UUID().uuidString)")

        FileManager.default.createFile(atPath: orphan1.path, contents: Data("test".utf8))
        FileManager.default.createFile(atPath: orphan2.path, contents: Data("test".utf8))
        FileManager.default.createFile(atPath: unrelated.path, contents: Data("test".utf8))
        defer { try? FileManager.default.removeItem(at: unrelated) }

        // Start and immediately stop a server — start() calls cleanOrphanedTempFiles()
        let server = try await HTTPServer.start(name: serverName, handler: { _ in HTTPResponse(status: 200) })
        server.stop()

        #expect(!FileManager.default.fileExists(atPath: orphan1.path))
        #expect(!FileManager.default.fileExists(atPath: orphan2.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }
}
