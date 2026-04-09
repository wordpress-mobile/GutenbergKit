import Foundation
import Testing
@testable import GutenbergKitHTTP

@Suite("HTTPRequestParser")
struct HTTPRequestParserTests {

    // MARK: - Basic Request Parsing

    @Test("parses a simple GET request")
    func parsesSimpleGet() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nHost: localhost:8080\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(parser.state.isComplete)
        #expect(request.method == "GET")
        #expect(request.target == "/wp/v2/posts")
        #expect(request.body == nil)
    }

    @Test("parses request target with query string")
    func parsesQueryString() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts?per_page=10&status=publish HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.target == "/wp/v2/posts?per_page=10&status=publish")
    }

    @Test("parses POST request with JSON body")
    func parsesPostWithBody() throws {
        let body = #"{"title":"Hello","content":"World"}"#
        let parser = HTTPRequestParser("POST /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)")
        let request = try #require(try parser.parseRequest())

        #expect(parser.state.isComplete)
        #expect(request.method == "POST")
        #expect(request.target == "/wp/v2/posts")
        #expect(request.header("Content-Type") == "application/json")

        let requestBody = try #require(request.body)
        #expect(try readAll(requestBody) == Data(body.utf8))
    }

    @Test("parses DELETE request")
    func parsesDelete() throws {
        let parser = HTTPRequestParser("DELETE /wp/v2/posts/42 HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.method == "DELETE")
        #expect(request.target == "/wp/v2/posts/42")
    }

    @Test("parses PUT request with body")
    func parsesPutWithBody() throws {
        let body = #"{"title":"Updated"}"#
        let parser = HTTPRequestParser("PUT /wp/v2/posts/42 HTTP/1.1\r\nHost: localhost\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)")
        let request = try #require(try parser.parseRequest())

        #expect(request.method == "PUT")
        let requestBody = try #require(request.body)
        #expect(try readAll(requestBody) == Data(body.utf8))
    }

    // MARK: - Header Parsing

    @Test("parses multiple headers")
    func parsesMultipleHeaders() throws {
        let parser = HTTPRequestParser("GET / HTTP/1.1\r\nHost: localhost\r\nAccept: application/json\r\nAuthorization: Bearer token123\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.headers["Host"] == "localhost")
        #expect(request.headers["Accept"] == "application/json")
        #expect(request.headers["Authorization"] == "Bearer token123")
    }

    @Test("header lookup is case-insensitive")
    func headerLookupCaseInsensitive() throws {
        let parser = HTTPRequestParser("GET / HTTP/1.1\r\nHost: localhost\r\nContent-Type: text/html\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("content-type") == "text/html")
        #expect(request.header("CONTENT-TYPE") == "text/html")
        #expect(request.header("Content-Type") == "text/html")
    }

    @Test("parses header values containing colons")
    func parsesHeaderValuesWithColons() throws {
        let parser = HTTPRequestParser("GET / HTTP/1.1\r\nHost: localhost\r\nAuthorization: Basic dXNlcjpwYXNz\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("Authorization") == "Basic dXNlcjpwYXNz")
    }

    // MARK: - Incremental Parsing

    @Test("handles data arriving in chunks")
    func handlesIncrementalData() throws {
        let raw = "GET /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let data = Data(raw.utf8)

        let parser = HTTPRequestParser()

        // Feed data byte by byte
        for i in 0..<data.count - 1 {
            parser.append(Data([data[i]]))
            #expect(!parser.state.isComplete)
        }

        // Feed the last byte
        parser.append(Data([data[data.count - 1]]))

        let request = try #require(try parser.parseRequest())
        #expect(parser.state.isComplete)
        #expect(request.method == "GET")
        #expect(request.target == "/wp/v2/posts")
    }

    @Test("transitions to headersComplete then complete as body arrives")
    func headersCompleteThenComplete() throws {
        let body = "hello world"
        let headers = "POST /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\nContent-Length: \(body.utf8.count)\r\n\r\n"
        let parser = HTTPRequestParser()

        // Send headers only — should be headersComplete, not complete
        parser.append(Data(headers.utf8))

        #expect(parser.state.hasHeaders)
        #expect(!parser.state.isComplete)
        #expect(parser.expectedBodyLength == Int64(body.utf8.count))

        let partialRequest = try #require(try parser.parseRequest())
        #expect(!partialRequest.isComplete)
        #expect(partialRequest.method == "POST")
        #expect(partialRequest.target == "/wp/v2/posts")

        // Now send the body — should transition to complete
        parser.append(Data(body.utf8))

        #expect(parser.state.isComplete)
        let request = try #require(try parser.parseRequest())
        #expect(request.isComplete)
        let requestBody = try #require(request.body)
        #expect(try readAll(requestBody) == Data(body.utf8))
    }

    @Test("headersComplete includes parsed headers")
    func headersCompleteIncludesHeaders() throws {
        let body = #"{"data":true}"#
        let parser = HTTPRequestParser("POST /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nAuthorization: Bearer tok\r\nContent-Length: \(body.utf8.count)\r\n\r\n")

        #expect(parser.state.hasHeaders)
        #expect(!parser.state.isComplete)

        let request = try #require(try parser.parseRequest())
        #expect(request.header("Content-Type") == "application/json")
        #expect(request.header("Authorization") == "Bearer tok")
    }

    @Test("returns needsMoreData for incomplete headers")
    func needsMoreDataForIncompleteHeaders() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nHost: loc")

        #expect(!parser.state.hasHeaders)
        #expect(!parser.state.isComplete)
        #expect(try parser.parseRequest() == nil)
    }

    @Test("body arriving in multiple small chunks")
    func bodyInMultipleChunks() throws {
        let body = "abcdefghij"
        let headers = "POST /wp/v2/media HTTP/1.1\r\nHost: localhost\r\nContent-Length: \(body.utf8.count)\r\n\r\n"
        let parser = HTTPRequestParser()

        parser.append(Data(headers.utf8))
        #expect(parser.state.hasHeaders)
        #expect(!parser.state.isComplete)

        // Send body in 2-byte chunks
        let bodyData = Data(body.utf8)
        for i in stride(from: 0, to: bodyData.count, by: 2) {
            let end = min(i + 2, bodyData.count)
            parser.append(bodyData[i..<end])
        }

        #expect(parser.state.isComplete)
        let request = try #require(try parser.parseRequest())
        let requestBody = try #require(request.body)
        #expect(try readAll(requestBody) == bodyData)
    }

    @Test("Content-Length with non-standard casing")
    func contentLengthCaseInsensitive() throws {
        let body = "data"
        let parser = HTTPRequestParser("POST /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\ncontent-length: \(body.utf8.count)\r\n\r\n\(body)")
        let request = try #require(try parser.parseRequest())

        #expect(parser.state.isComplete)
        let requestBody = try #require(request.body)
        #expect(try readAll(requestBody) == Data(body.utf8))
    }

    @Test("append after complete is a no-op")
    func appendAfterComplete() throws {
        let parser = HTTPRequestParser("GET /wp/v2/settings HTTP/1.1\r\nHost: localhost\r\n\r\n")
        #expect(parser.state.isComplete)

        parser.append(Data("extra garbage".utf8))
        #expect(parser.state.isComplete)

        let request = try #require(try parser.parseRequest())
        #expect(request.method == "GET")
        #expect(request.target == "/wp/v2/settings")
    }

    @Test("parses PATCH request")
    func parsesPatch() throws {
        let body = #"{"title":"Patched"}"#
        let parser = HTTPRequestParser("PATCH /wp/v2/posts/1 HTTP/1.1\r\nHost: localhost\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)")
        let request = try #require(try parser.parseRequest())

        #expect(request.method == "PATCH")
        #expect(request.target == "/wp/v2/posts/1")
    }

    @Test("parses OPTIONS request")
    func parsesOptions() throws {
        let parser = HTTPRequestParser("OPTIONS /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.method == "OPTIONS")
        #expect(request.body == nil)
    }

    // MARK: - Request Target Edge Cases (inspired by httparse uri.rs)

    @Test("preserves semicolon path parameters in target")
    func semicolonPathParams() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts;embed?per_page=5 HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.target == "/wp/v2/posts;embed?per_page=5")
    }

    @Test("preserves percent-encoded characters in target")
    func percentEncodedTarget() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts?search=%E4%BD%A0%E5%A5%BD HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.target == "/wp/v2/posts?search=%E4%BD%A0%E5%A5%BD")
    }

    @Test("preserves multiple consecutive slashes in target")
    func multipleSlashes() throws {
        let parser = HTTPRequestParser("GET //wp//v2//posts HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.target == "//wp//v2//posts")
    }

    @Test("preserves double question marks in target")
    func doubleQuestionMarks() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts?search=what??&per_page=10 HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.target == "/wp/v2/posts?search=what??&per_page=10")
    }

    @Test("preserves at-sign and brackets in target")
    func specialCharactersInTarget() throws {
        let parser = HTTPRequestParser("GET /wp/v2/users/@admin/[meta] HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.target == "/wp/v2/users/@admin/[meta]")
    }

    @Test("preserves dot segments in target")
    func dotSegments() throws {
        let parser = HTTPRequestParser("GET /wp/v2/media/..uploads/...pending HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.target == "/wp/v2/media/..uploads/...pending")
    }

    @Test("preserves absolute-form URI as target")
    func absoluteFormTarget() throws {
        let parser = HTTPRequestParser("GET https://example.com:443/wp/v2/posts HTTP/1.1\r\nHost: example.com\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.target == "https://example.com:443/wp/v2/posts")
    }

    @Test("preserves fragment in target")
    func fragmentInTarget() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts?page=1&per_page=10#post-17408 HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.target == "/wp/v2/posts?page=1&per_page=10#post-17408")
    }

    @Test("preserves quotes in target")
    func quotesInTarget() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts?search=\"hello+world\" HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.target == "/wp/v2/posts?search=\"hello+world\"")
    }

    // MARK: - Additional Methods and Target Forms (inspired by http-parser-rs)

    @Test("parses HEAD request")
    func parsesHead() throws {
        let parser = HTTPRequestParser("HEAD /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.method == "HEAD")
        #expect(request.body == nil)
    }

    @Test("parses CONNECT request with authority-form target")
    func parsesConnectAuthorityForm() throws {
        let parser = HTTPRequestParser("CONNECT wordpress.org:443 HTTP/1.1\r\nHost: wordpress.org:443\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.method == "CONNECT")
        #expect(request.target == "wordpress.org:443")
    }

    @Test("parses OPTIONS request with asterisk-form target")
    func parsesOptionsAsterisk() throws {
        let parser = HTTPRequestParser("OPTIONS * HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.method == "OPTIONS")
        #expect(request.target == "*")
    }

    @Test("parses header value with no space after colon")
    func headerNoSpaceAfterColon() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\nX-WP-Nonce:abc123\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(request.header("X-WP-Nonce") == "abc123")
    }

    // MARK: - Edge Cases

    @Test("bare CRLF returns needsMoreData after leading CRLF stripping")
    func bareCRLFIsNeedsMoreData() throws {
        // RFC 7230 §3.5: Leading CRLFs are stripped, leaving no data — needsMoreData.
        let parser = HTTPRequestParser("\r\n\r\n")

        #expect(!parser.state.hasHeaders)
        #expect(try parser.parseRequest() == nil)
    }

    @Test("throws invalidEncoding for non-UTF-8 header bytes")
    func throwsForInvalidEncoding() {
        // 0xFF 0xFE is not valid UTF-8
        var data = Data([0xFF, 0xFE])
        data.append(Data("\r\n\r\n".utf8))
        let parser = HTTPRequestParser(data)

        #expect(throws: HTTPRequestParseError.invalidEncoding) {
            try parser.parseRequest()
        }
    }

    @Test("handles HTTP/1.0 request with no headers except the request line")
    func noHeaders() throws {
        // HTTP/1.0 does not require Host, so an empty header section is valid.
        let parser = HTTPRequestParser("GET / HTTP/1.0\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(parser.state.isComplete)
        #expect(request.method == "GET")
        #expect(request.target == "/")
        #expect(request.headers.isEmpty)
    }

    @Test("handles zero Content-Length")
    func zeroContentLength() throws {
        let parser = HTTPRequestParser("POST /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        #expect(parser.state.isComplete)
        #expect(request.method == "POST")
        #expect(request.body == nil)
    }

    // MARK: - Max Body Size

    @Test("drains oversized body and returns partial with parseError")
    func rejectsOversizedContentLength() throws {
        let parser = HTTPRequestParser(maxBodySize: 100)
        parser.append(Data("POST /upload HTTP/1.1\r\nHost: localhost\r\nContent-Length: 101\r\n\r\n".utf8))

        // Parser enters drain mode — not yet complete.
        #expect(parser.state == .draining)

        // Feed the remaining body bytes to complete the drain.
        parser.append(Data(repeating: 0x41, count: 101))
        #expect(parser.state.isComplete)

        // parseRequest() returns partial headers instead of throwing.
        let request = try #require(try parser.parseRequest())
        #expect(request.method == "POST")
        #expect(request.target == "/upload")
        #expect(!request.isComplete)
        #expect(parser.parseError == .payloadTooLarge)
    }

    @Test("accepts request when Content-Length equals maxBodySize")
    func acceptsContentLengthAtLimit() throws {
        let body = String(repeating: "x", count: 100)
        let parser = HTTPRequestParser(maxBodySize: 100)
        parser.append(Data("POST /upload HTTP/1.1\r\nHost: localhost\r\nContent-Length: 100\r\n\r\n\(body)".utf8))

        #expect(parser.state.isComplete)
        let request = try #require(try parser.parseRequest())
        let requestBody = try #require(request.body)
        #expect(try readAll(requestBody) == Data(body.utf8))
    }

    @Test("accepts request when Content-Length is below maxBodySize")
    func acceptsContentLengthBelowLimit() throws {
        let body = "small"
        let parser = HTTPRequestParser(maxBodySize: 100)
        parser.append(Data("POST /upload HTTP/1.1\r\nHost: localhost\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)".utf8))

        #expect(parser.state.isComplete)
        let request = try #require(try parser.parseRequest())
        let requestBody = try #require(request.body)
        #expect(try readAll(requestBody) == Data(body.utf8))
    }

    @Test("enters drain mode for oversized Content-Length even when body hasn't arrived")
    func rejectsOversizedBeforeBodyArrives() throws {
        let parser = HTTPRequestParser(maxBodySize: 50)
        parser.append(Data("POST /upload HTTP/1.1\r\nHost: localhost\r\nContent-Length: 999999\r\n\r\n".utf8))

        // Parser enters drain mode — headers are available but not yet complete.
        #expect(parser.state == .draining)
        #expect(parser.state.hasHeaders)
        #expect(!parser.state.isComplete)

        // Feed body bytes in chunks to complete the drain.
        let chunkSize = 8192
        var remaining = 999999
        while remaining > 0 {
            let size = min(chunkSize, remaining)
            parser.append(Data(repeating: 0x42, count: size))
            remaining -= size
        }

        #expect(parser.state.isComplete)
        let request = try #require(try parser.parseRequest())
        #expect(request.method == "POST")
        #expect(!request.isComplete)
        #expect(parser.parseError == .payloadTooLarge)
    }

    @Test("drain mode does not buffer body bytes")
    func drainDoesNotBuffer() throws {
        let parser = HTTPRequestParser(maxBodySize: 10)
        let headers = "POST /upload HTTP/1.1\r\nHost: localhost\r\nContent-Length: 1000\r\n\r\n"
        parser.append(Data(headers.utf8))
        #expect(parser.state == .draining)

        // Feed 1000 bytes of body data.
        parser.append(Data(repeating: 0x43, count: 1000))
        #expect(parser.state.isComplete)

        // parseRequest() returns headers; error is on parseError.
        let request = try #require(try parser.parseRequest())
        #expect(request.method == "POST")
        #expect(!request.isComplete)
        #expect(parser.parseError == .payloadTooLarge)
    }

    @Test("rejects headers that exceed maxHeaderSize without terminator")
    func rejectsOversizedHeaders() {
        let parser = HTTPRequestParser()
        // Send more than 64KB of header data without \r\n\r\n
        let longHeader = "X-Padding: " + String(repeating: "A", count: 1000) + "\r\n"
        let headerCount = (HTTPRequestParser.maxHeaderSize / longHeader.utf8.count) + 1
        var raw = "GET / HTTP/1.1\r\n"
        for _ in 0..<headerCount {
            raw += longHeader
        }
        parser.append(Data(raw.utf8))

        #expect(parser.state.isComplete)
        #expect(throws: HTTPRequestParseError.headersTooLarge) {
            try parser.parseRequest()
        }
    }

    @Test("accepts headers just under maxHeaderSize")
    func acceptsHeadersUnderLimit() throws {
        // Build headers that fit within 64KB including the terminator
        let parser = HTTPRequestParser()
        let raw = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
        parser.append(Data(raw.utf8))

        #expect(parser.state.isComplete)
        let request = try #require(try parser.parseRequest())
        #expect(request.method == "GET")
    }

    @Test("no Content-Length is allowed regardless of maxBodySize")
    func noContentLengthAllowedWithSmallLimit() throws {
        let parser = HTTPRequestParser(maxBodySize: 0)
        parser.append(Data("GET /posts HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8))

        #expect(parser.state.isComplete)
        let request = try #require(try parser.parseRequest())
        #expect(request.method == "GET")
        #expect(request.body == nil)
    }

    // MARK: - Bare CR at Field Value Edges

    @Test("bare CR at start of field value is rejected")
    func bareCRAtStartOfFieldValue() throws {
        let parser = HTTPRequestParser("GET / HTTP/1.1\r\nHost: localhost\r\nX-Bad: \rhello\r\n\r\n")
        #expect(throws: HTTPRequestParseError.self) {
            try parser.parseRequest()
        }
    }

    @Test("bare CR at end of field value is rejected")
    func bareCRAtEndOfFieldValue() throws {
        let parser = HTTPRequestParser("GET / HTTP/1.1\r\nHost: localhost\r\nX-Bad: hello\r\r\n\r\n")
        #expect(throws: HTTPRequestParseError.self) {
            try parser.parseRequest()
        }
    }
}
