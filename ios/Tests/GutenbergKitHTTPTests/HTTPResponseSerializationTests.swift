import Foundation
import Testing
@testable import GutenbergKitHTTP

@Suite("HTTPResponse Serialization")
struct HTTPResponseSerializationTests {

    @Test("Content-Length always matches actual body size")
    func contentLengthMatchesBody() {
        let response = HTTPResponse(
            status: 200,
            headers: [("Content-Type", "text/plain")],
            body: Data("hello".utf8)
        )
        let serialized = String(decoding: response.serialized(), as: UTF8.self)

        #expect(serialized.contains("Content-Length: 5\r\n"))
    }

    @Test("Caller-provided Content-Length is replaced with actual body size")
    func contentLengthIsReplaced() {
        let response = HTTPResponse(
            status: 200,
            headers: [("Content-Length", "999"), ("Content-Type", "text/plain")],
            body: Data("hello".utf8)
        )
        let serialized = String(decoding: response.serialized(), as: UTF8.self)

        #expect(!serialized.contains("Content-Length: 999"))
        #expect(serialized.contains("Content-Length: 5\r\n"))
    }

    @Test("Case-insensitive Content-Length replacement")
    func caseInsensitiveContentLengthReplacement() {
        let response = HTTPResponse(
            status: 200,
            headers: [("content-length", "0"), ("Content-Type", "text/plain")],
            body: Data("test body".utf8)
        )
        let serialized = String(decoding: response.serialized(), as: UTF8.self)

        #expect(!serialized.contains("content-length: 0"))
        #expect(serialized.contains("Content-Length: 9\r\n"))
    }

    @Test("Connection: close is always present")
    func connectionClosePresent() {
        let response = HTTPResponse(status: 200, body: Data("ok".utf8))
        let serialized = String(decoding: response.serialized(), as: UTF8.self)

        #expect(serialized.contains("Connection: close\r\n"))
    }

    @Test("Hop-by-hop Connection header is stripped and replaced with close")
    func hopByHopConnectionReplaced() {
        let response = HTTPResponse(
            status: 200,
            headers: [("Connection", "keep-alive")],
            body: Data("ok".utf8)
        )
        let serialized = String(decoding: response.serialized(), as: UTF8.self)

        #expect(!serialized.contains("Connection: keep-alive"))
        #expect(serialized.contains("Connection: close"))
    }

    @Test("Hop-by-hop Transfer-Encoding header is stripped")
    func transferEncodingStripped() {
        let response = HTTPResponse(
            status: 200,
            headers: [("Transfer-Encoding", "chunked"), ("Content-Type", "text/plain")],
            body: Data("ok".utf8)
        )
        let serialized = String(decoding: response.serialized(), as: UTF8.self)

        #expect(!serialized.contains("Transfer-Encoding"))
    }

    @Test("401 response with WWW-Authenticate header serializes correctly")
    func unauthorizedResponse() {
        let response = HTTPResponse(
            status: 401,
            headers: [("WWW-Authenticate", "Bearer")]
        )
        let serialized = String(decoding: response.serialized(), as: UTF8.self)

        #expect(serialized.hasPrefix("HTTP/1.1 401 Unauthorized\r\n"))
        #expect(serialized.contains("WWW-Authenticate: Bearer\r\n"))
    }

    @Test("Header values are sanitized (BEL character stripped)")
    func headerValuesSanitized() {
        let response = HTTPResponse(
            status: 200,
            headers: [("X-Test", "value\u{07}bell")],
            body: Data()
        )
        let serialized = String(decoding: response.serialized(), as: UTF8.self)

        #expect(!serialized.contains("\u{07}"))
        #expect(serialized.contains("X-Test: valuebell"))
    }

    @Test("Sanitize preserves obs-text (0x80+) per RFC 9110")
    func obsTextPreserved() {
        let response = HTTPResponse(
            status: 200,
            headers: [("X-Test", "caf\u{00e9}")],
            body: Data()
        )
        let serialized = String(decoding: response.serialized(), as: UTF8.self)

        #expect(serialized.contains("X-Test: caf\u{00e9}"))
    }

    @Test("Sanitize preserves HTAB in header values")
    func htabPreserved() {
        let response = HTTPResponse(
            status: 200,
            headers: [("X-Test", "a\tb")],
            body: Data()
        )
        let serialized = String(decoding: response.serialized(), as: UTF8.self)

        #expect(serialized.contains("X-Test: a\tb"))
    }

    @Test("Date header is present in RFC 9110 HTTP-date format")
    func dateHeaderPresent() {
        let response = HTTPResponse(status: 200)
        let serialized = String(decoding: response.serialized(), as: UTF8.self)

        let datePattern = /Date: \w{3}, \d{2} \w{3} \d{4} \d{2}:\d{2}:\d{2} GMT\r\n/
        #expect(serialized.contains(datePattern))
    }

    @Test("Server header is present")
    func serverHeaderPresent() {
        let response = HTTPResponse(status: 200)
        let serialized = String(decoding: response.serialized(), as: UTF8.self)

        #expect(serialized.contains("Server: GutenbergKit\r\n"))
    }

    @Test("Caller-provided Date header is replaced")
    func callerDateReplaced() {
        let response = HTTPResponse(
            status: 200,
            headers: [("Date", "Thu, 01 Jan 1970 00:00:00 GMT")],
            body: Data()
        )
        let serialized = String(decoding: response.serialized(), as: UTF8.self)

        let dateCount = serialized.components(separatedBy: "Date:").count - 1
        #expect(dateCount == 1, "Exactly one Date header")
        #expect(!serialized.contains("Date: Thu, 01 Jan 1970"))
    }

    @Test("Caller-provided Server header is replaced")
    func callerServerReplaced() {
        let response = HTTPResponse(
            status: 200,
            headers: [("Server", "Apache")],
            body: Data()
        )
        let serialized = String(decoding: response.serialized(), as: UTF8.self)

        #expect(!serialized.contains("Server: Apache"))
        #expect(serialized.contains("Server: GutenbergKit"))
    }

    @Test("Status code is zero-padded to 3 digits")
    func statusCodeZeroPadded() {
        let response = HTTPResponse(status: 1, statusText: "Test")
        let serialized = String(decoding: response.serialized(), as: UTF8.self)

        #expect(serialized.hasPrefix("HTTP/1.1 001 Test\r\n"))
    }

    @Test("Body is appended after headers")
    func bodyAppendedAfterHeaders() {
        let body = Data("Hello, World!".utf8)
        let response = HTTPResponse(status: 200, body: body)
        let serialized = response.serialized()

        let headerEnd = "\r\n\r\n".data(using: .utf8)!
        let range = serialized.range(of: headerEnd)!
        let bodyPortion = serialized[range.upperBound...]
        #expect(bodyPortion == body)
    }

    @Test("Empty body produces Content-Length: 0")
    func emptyBodyContentLength() {
        let response = HTTPResponse(status: 204, body: Data())
        let serialized = String(decoding: response.serialized(), as: UTF8.self)

        #expect(serialized.contains("Content-Length: 0\r\n"))
    }
}
