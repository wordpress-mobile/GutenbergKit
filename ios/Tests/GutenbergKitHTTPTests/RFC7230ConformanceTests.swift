import Foundation
import Testing
@testable import GutenbergKitHTTP

@Suite("RFC 7230 Conformance")
struct RFC7230ConformanceTests {

    // MARK: - Section 3.5 (Message Parsing Robustness)

    @Test("RFC 7230 §3.5: single leading CRLF before request line is ignored")
    func singleLeadingCRLFIsIgnored() throws {
        // RFC 7230 §3.5: server SHOULD ignore at least one leading CRLF.
        let parser = HTTPRequestParser("\r\nGET /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.method == "GET")
        #expect(request.target == "/wp/v2/posts")
        #expect(request.header("Host") == "localhost")
    }

    @Test("RFC 7230 §3.5: multiple leading CRLFs before request line are ignored")
    func multipleLeadingCRLFsAreIgnored() throws {
        // RFC 7230 §3.5: server SHOULD ignore at least one leading CRLF.
        let parser = HTTPRequestParser("\r\n\r\nGET /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.method == "GET")
        #expect(request.target == "/wp/v2/posts")
        #expect(request.header("Host") == "localhost")
    }

    // MARK: - Section 3.2 (Header Fields)

    @Test("RFC 7230 §3.2.4: whitespace between field-name and colon is rejected")
    func whitespaceBetweenFieldNameAndColon() {
        // RFC 7230 §3.2.4: "No whitespace is allowed between the header field-name
        // and colon." This is a request smuggling vector — the parser returns the
        // specific .whitespaceBeforeColon error rather than the generic .invalidFieldName.
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nHost : localhost\r\nX-WP-Nonce : abc123\r\n\r\n")

        #expect(throws: HTTPRequestParseError.whitespaceBeforeColon) {
            try parser.parseRequest()
        }
    }

    @Test("RFC 7230 §3.2.4: obs-fold continuation line is rejected")
    func obsFoldContinuationLineRejected() {
        // RFC 7230 says server MUST reject with 400 or replace obs-fold with SP.
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nX-WP-Custom: value1\r\n continued-value\r\nHost: localhost\r\n\r\n")

        #expect(throws: HTTPRequestParseError.obsFoldDetected) {
            try parser.parseRequest()
        }
    }

    @Test("RFC 7230 §3.2.4: obs-fold with tab continuation is rejected")
    func obsFoldTabContinuationRejected() {
        // Tab-prefixed continuation lines are rejected per RFC 7230 §3.2.4.
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nAuthorization: Bearer\r\n\ttok123\r\nHost: localhost\r\n\r\n")

        #expect(throws: HTTPRequestParseError.obsFoldDetected) {
            try parser.parseRequest()
        }
    }

    @Test("RFC 7230 §3.2: field-name is a token — preserved without normalization")
    func fieldNameTokenPreservedVerbatim() throws {
        // Header field names should be treated as opaque tokens
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nX-WP-Nonce: abc\r\nX_Underscore_Header: val\r\nX-123-Numeric: num\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.headers["X-WP-Nonce"] == "abc")
        #expect(request.headers["X_Underscore_Header"] == "val")
        #expect(request.headers["X-123-Numeric"] == "num")
    }

    // MARK: - Section 3.3 (Message Body)

    @Test("RFC 7230 §3.3.3: Transfer-Encoding: chunked is rejected")
    func transferEncodingChunkedRejected() {
        let body = #"{"title":"Test"}"#
        let raw = "POST /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let parser = HTTPRequestParser(raw)

        #expect(throws: HTTPRequestParseError.unsupportedTransferEncoding) {
            try parser.parseRequest()
        }
    }

    @Test("RFC 7230 §3.3.3: Transfer-Encoding without Content-Length is rejected")
    func transferEncodingWithoutContentLengthRejected() {
        let raw = "POST /wp/v2/posts HTTP/1.1\r\nTransfer-Encoding: chunked\r\nHost: localhost\r\n\r\n"
        let parser = HTTPRequestParser(raw)

        #expect(throws: HTTPRequestParseError.unsupportedTransferEncoding) {
            try parser.parseRequest()
        }
    }

    @Test("RFC 7230 §3.3.3: Transfer-Encoding: identity is also rejected")
    func transferEncodingIdentityRejected() {
        // Even `identity` is rejected — this server only supports Content-Length framing.
        let raw = "POST /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: identity\r\nContent-Length: 5\r\n\r\nhello"
        let parser = HTTPRequestParser(raw)

        #expect(throws: HTTPRequestParseError.unsupportedTransferEncoding) {
            try parser.parseRequest()
        }
    }

    @Test("RFC 7230 §3.3.3: Transfer-Encoding with mixed case is rejected")
    func transferEncodingMixedCaseRejected() {
        let raw = "POST /wp/v2/posts HTTP/1.1\r\nTRANSFER-ENCODING: chunked\r\nHost: localhost\r\n\r\n"
        let parser = HTTPRequestParser(raw)

        #expect(throws: HTTPRequestParseError.unsupportedTransferEncoding) {
            try parser.parseRequest()
        }
    }

    @Test("RFC 7230 §3.3.3: duplicate identical Content-Length values — first value used by scanner")
    func duplicateIdenticalContentLength() throws {
        // RFC says recipient MUST reject or consolidate. Our parser's scanContentLength
        // finds the first match and the header dict overwrites with the last.
        let body = #"{"id":1}"#
        let raw = "POST /wp/v2/posts HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\nContent-Length: \(body.utf8.count)\r\nHost: localhost\r\n\r\n\(body)"
        let parser = HTTPRequestParser(raw)

        #expect(parser.state.isComplete)
        let request = try #require(try parser.parseRequest())
        let requestBody = try #require(request.body)
        #expect(try readAll(requestBody) == Data(body.utf8))
    }

    @Test("RFC 7230 §3.3.3: conflicting Content-Length values are rejected as invalid")
    func conflictingContentLengthRejected() {
        // RFC says conflicting Content-Length is unrecoverable error (MUST reject).
        let parser = HTTPRequestParser("POST /wp/v2/posts HTTP/1.1\r\nContent-Length: 100\r\nContent-Length: 5\r\nHost: localhost\r\n\r\nhello")

        #expect(throws: HTTPRequestParseError.conflictingContentLength) {
            try parser.parseRequest()
        }
    }

    @Test("RFC 7230 §3.3.3 step 6: request with no Content-Length and no Transfer-Encoding has zero-length body")
    func noContentLengthNoTransferEncodingMeansZeroBody() throws {
        let parser = HTTPRequestParser("DELETE /wp/v2/posts/42?force=true HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer tok\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(parser.state.isComplete)
        #expect(request.body == nil)
    }

    @Test("RFC 7230 §3.3: Content-Length: 0 is explicitly zero-length body")
    func contentLengthZeroIsExplicitNoBody() throws {
        let parser = HTTPRequestParser("POST /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(parser.state.isComplete)
        #expect(request.body == nil)
        #expect(parser.expectedBodyLength == 0)
    }

    // MARK: - Section 3.3.3 (Message Body Length — Incremental)

    @Test("RFC 7230 §3.3.3: body arriving after headers in separate chunk")
    func bodyArrivesInSeparateChunk() throws {
        let body = #"{"title":"Hello","status":"publish"}"#
        let headers = "POST /wp/v2/posts HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\nHost: localhost\r\n\r\n"

        let parser = HTTPRequestParser()
        parser.append(Data(headers.utf8))
        #expect(parser.state.hasHeaders)
        #expect(!parser.state.isComplete)

        parser.append(Data(body.utf8))
        #expect(parser.state.isComplete)

        let request = try #require(try parser.parseRequest())
        let requestBody = try #require(request.body)
        #expect(try readAll(requestBody) == Data(body.utf8))
    }

    @Test("RFC 7230 §3.4: incomplete body — fewer bytes than Content-Length")
    func incompleteBodyFewerBytesThanContentLength() throws {
        let parser = HTTPRequestParser()
        parser.append(Data("POST /wp/v2/media HTTP/1.1\r\nHost: localhost\r\nContent-Length: 500\r\n\r\n".utf8))
        parser.append(Data("partial data".utf8))

        #expect(parser.state.hasHeaders)
        #expect(!parser.state.isComplete)

        let request = try #require(try parser.parseRequest())
        #expect(!request.isComplete)
        #expect(request.method == "POST")
        #expect(request.target == "/wp/v2/media")
    }

    // MARK: - Section 5.3 (Request Target)

    @Test("RFC 7230 §5.3.1: origin-form with empty query string")
    func originFormEmptyQuery() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts? HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.target == "/wp/v2/posts?")
    }

    @Test("RFC 7230 §5.3.1: origin-form must start with /")
    func originFormStartsWithSlash() {
        // Relative path without leading slash — rejected per RFC 9112 §3.2
        let parser = HTTPRequestParser("GET wp/v2/posts HTTP/1.1\r\nHost: localhost\r\n\r\n")

        #expect(throws: HTTPRequestParseError.self) {
            try parser.parseRequest()
        }
    }

    @Test("RFC 7230 §5.3.2: absolute-form with HTTPS scheme")
    func absoluteFormHTTPS() throws {
        let parser = HTTPRequestParser("GET https://example.com/wp/v2/posts HTTP/1.1\r\nHost: example.com\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.target == "https://example.com/wp/v2/posts")
    }

    @Test("RFC 7230 §5.3.2: absolute-form with userinfo in authority")
    func absoluteFormWithUserinfo() throws {
        let parser = HTTPRequestParser("GET http://admin:pass@example.com/wp/v2/posts HTTP/1.1\r\nHost: example.com\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.target == "http://admin:pass@example.com/wp/v2/posts")
    }

    @Test("RFC 7230 §5.3.3: authority-form with port")
    func authorityFormWithPort() throws {
        let parser = HTTPRequestParser("CONNECT wordpress.org:8443 HTTP/1.1\r\nHost: wordpress.org:8443\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.method == "CONNECT")
        #expect(request.target == "wordpress.org:8443")
    }

    @Test("RFC 7230 §5.3.4: asterisk-form for server-wide OPTIONS")
    func asteriskFormServerWideOptions() throws {
        let parser = HTTPRequestParser("OPTIONS * HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.method == "OPTIONS")
        #expect(request.target == "*")
    }

    // MARK: - Section 5.4 (Host)

    @Test("RFC 7230 §5.4: request without Host header is rejected in HTTP/1.1")
    func requestWithoutHostRejected() {
        // RFC 9110 §7.2: server MUST respond 400 if Host is missing in HTTP/1.1.
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nAccept: application/json\r\n\r\n")

        #expect(throws: HTTPRequestParseError.missingHostHeader) {
            try parser.parseRequest()
        }
    }

    @Test("RFC 7230 §5.4: Host header with port")
    func hostHeaderWithPort() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nHost: localhost:8080\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Host") == "localhost:8080")
    }

    @Test("RFC 7230 §5.4: empty Host header is accepted")
    func emptyHostHeaderAccepted() throws {
        // RFC allows empty Host for requests to root origin server
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nHost:\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        // Optional `String?`: `== ""` asserts present-and-empty, which `isEmpty` cannot express.
        // swiftlint:disable:next empty_string
        #expect(request.header("Host") == "")
    }

    // MARK: - Section 3.1.1 (Request Line Edge Cases)

    @Test("RFC 7230 §3.1.1: request line with extra spaces between components is rejected")
    func requestLineExtraSpaces() {
        // RFC 9112 §3: request-line = method SP request-target SP HTTP-version
        // Double space produces an empty target which fails validation.
        let parser = HTTPRequestParser("GET  /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\n\r\n")

        #expect(throws: HTTPRequestParseError.invalidHTTPVersion) {
            try parser.parseRequest()
        }
    }

    @Test("RFC 7230 §3.1.1: request with very long method token")
    func veryLongMethodToken() throws {
        let longMethod = String(repeating: "X", count: 100)
        let parser = HTTPRequestParser("\(longMethod) /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.method == longMethod)
    }

    // MARK: - Section 3 (General Message Format)

    @Test("RFC 7230 §3: only CRLF (no headers, no request line content) is needsMoreData")
    func onlyCRLFIsNeedsMoreData() throws {
        // Leading CRLFs are stripped per RFC 7230 §3.5, leaving no data — needsMoreData.
        let parser = HTTPRequestParser("\r\n\r\n")

        #expect(!parser.state.hasHeaders)
        #expect(try parser.parseRequest() == nil)
    }

    @Test("RFC 7230 §3: request with many headers")
    func requestWithManyHeaders() throws {
        var raw = "GET /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\n"
        for i in 0..<50 {
            raw += "X-WP-Header-\(i): value-\(i)\r\n"
        }
        raw += "\r\n"

        let parser = HTTPRequestParser(raw)
        let request = try #require(try parser.parseRequest())

        #expect(parser.state.isComplete)
        #expect(request.headers.count == 51) // 50 X-WP-Header + Host
        #expect(request.header("X-WP-Header-0") == "value-0")
        #expect(request.header("X-WP-Header-49") == "value-49")
    }

    // MARK: - Header Count Limit

    @Test("rejects requests with more than 100 header field lines")
    func tooManyHeaders() {
        // 1 Host + 100 X-Headers = 101 total header lines → rejected
        var raw = "GET / HTTP/1.1\r\nHost: localhost\r\n"
        for i in 0..<100 {
            raw += "X-Header-\(i): value\r\n"
        }
        raw += "\r\n"
        let parser = HTTPRequestParser(raw)

        #expect(throws: HTTPRequestParseError.tooManyHeaders) {
            try parser.parseRequest()
        }
    }

    @Test("accepts requests with exactly 100 header field lines")
    func maxHeadersAccepted() throws {
        // 1 Host + 99 X-Headers = 100 total header lines → accepted
        var raw = "GET / HTTP/1.1\r\nHost: localhost\r\n"
        for i in 0..<99 {
            raw += "X-Header-\(i): value\r\n"
        }
        raw += "\r\n"
        let parser = HTTPRequestParser(raw)
        let request = try #require(try parser.parseRequest())

        #expect(request.method == "GET")
    }

    @Test("RFC 7230 §3: header value with all printable ASCII characters")
    func headerValueAllPrintableASCII() throws {
        // Field values can contain any VCHAR (0x21-0x7E) plus SP and HTAB.
        // Leading/trailing whitespace in the value is stripped by the parser (OWS trimming).
        let printable = "!\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nX-WP-Test: \(printable)\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("X-WP-Test") == printable)
    }
}
