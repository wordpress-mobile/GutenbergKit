import Foundation
import Testing
@testable import GutenbergKitHTTP

#if canImport(Network)
import Network
#endif

/// Tests that require platform-specific APIs (URLRequest conversion, response
/// serialization, server behavior) or conditional logic that cannot be expressed
/// in the shared JSON fixture format. All pure parse-input → expected-output
/// tests have been migrated to test-fixtures/http/request-parsing.json.
@Suite("RFC 9110 Conformance")
struct RFC9110ConformanceTests {

    // MARK: - Section 5.3 (Internal Dict Representation)

    @Test("RFC 9110 §5.3: duplicate headers preserve first occurrence's key casing")
    func duplicateHeadersPreserveFirstKeyCasing() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nX-Custom: first\r\nx-custom: second\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        // The dict key should use the casing from the first occurrence
        #expect(request.headers["X-Custom"] == "first, second")
        #expect(request.headers["x-custom"] == nil)
    }

    // MARK: - Section 7.1 (Edge Cases)

    @Test("RFC 9110 §7.1: request target with empty path")
    func requestTargetWithEmptyPath() throws {
        // An empty request-target should be rejected or treated as "/"
        let parser = HTTPRequestParser("GET  HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try? parser.parseRequest()

        // With split(maxSplits: 2) on "GET  HTTP/1.1", this splits to ["GET", "", "HTTP/1.1"]
        // The target becomes ""
        if let request {
            #expect(request.method == "GET")
        }
    }

    // MARK: - Section 15 (Security - Request Splitting / Smuggling)

    @Test("RFC 9110 §15.6: LF in header value should not cause request splitting")
    func lfInHeaderValueNoRequestSplitting() throws {
        // A bare LF in a header value within a CRLF-terminated message
        // The parser should not split on bare LF
        let raw = "GET /wp/v2/posts HTTP/1.1\r\nX-Test: val\nue\r\nHost: localhost\r\n\r\n"
        let parser = HTTPRequestParser(raw)
        let request = try? parser.parseRequest()

        // Whether it parses or not, it shouldn't create a request smuggling vector
        if let request {
            #expect(request.header("Host") == "localhost")
        }
    }

    // MARK: - Response Serialization

    @Test("RFC 9110 §15.5.2: 401 response with WWW-Authenticate header serializes correctly")
    func wwwAuthenticateHeaderOn401() {
        let response = HTTPResponse(
            status: 401,
            headers: [("WWW-Authenticate", "Bearer")]
        )
        let serialized = String(data: response.serialized(), encoding: .utf8)!

        #expect(serialized.hasPrefix("HTTP/1.1 401 Unauthorized\r\n"))
        #expect(serialized.contains("WWW-Authenticate: Bearer\r\n"))
    }

    // MARK: - Section 15.5.9 (408 Request Timeout)

    #if canImport(Network)
    @Test("RFC 9110 §15.5.9: server sends 408 before closing on read timeout", .disabled("HTTPServer does not yet send 408 on idle timeout — needs NWConnection write support"), .timeLimit(.minutes(1)))
    func serverSends408OnReadTimeout() async throws {
        // Per RFC 9110 §15.5.9, a server that decides to close an idle connection
        // SHOULD send a 408 (Request Timeout) response.
        let server = try await HTTPServer.start(
            name: "timeout-test",
            port: nil,
            requiresAuthentication: false,
            readTimeout: .milliseconds(500)
        ) { _ in
            HTTPResponse(status: 200)
        }
        defer { server.stop() }

        // Connect and immediately read — don't send any request data.
        // URLSession won't work here (it always sends a request), so use raw sockets.
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        #expect(fd >= 0, "Failed to create socket")
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = server.port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        #expect(connectResult == 0, "Failed to connect to server")

        // Set a 5-second read timeout so we don't block forever.
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        // Wait for the server to respond (it should send 408 within its 500ms timeout).
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = recv(fd, &buffer, buffer.count, 0)

        // The server should have sent a 408 response, not just closed silently.
        #expect(bytesRead > 0, "Server closed connection without sending a response")

        if bytesRead > 0 {
            let response = String(bytes: buffer[..<bytesRead], encoding: .utf8) ?? ""
            #expect(response.hasPrefix("HTTP/1.1 408"), "Expected 408 Request Timeout, got: \(response.prefix(40))")
        }
    }
    #endif

    // MARK: - urlRequest Conversion (RFC 9110 §7.1, §7.6.1)

    @Test("RFC 9110 §7.6.1: hop-by-hop headers are stripped when converting to URLRequest")
    func hopByHopHeadersStripped() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\nKeep-Alive: timeout=5\r\nProxy-Connection: keep-alive\r\nAccept: application/json\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        let urlRequest = try #require(request.urlRequest(relativeTo: URL(string: "http://localhost")!))

        // Hop-by-hop headers should be stripped
        #expect(urlRequest.value(forHTTPHeaderField: "Host") == nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Connection") == nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Keep-Alive") == nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Proxy-Connection") == nil)

        // End-to-end headers should be preserved
        #expect(urlRequest.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("RFC 9110 §7.6.1: TE header is stripped in urlRequest conversion")
    func teHeaderStripped() throws {
        let request = ParsedHTTPRequest.complete(
            method: "GET",
            target: "/wp/v2/posts",
            httpVersion: "HTTP/1.1",
            headers: [
                "Host": "localhost",
                "TE": "trailers",
                "Accept": "application/json",
            ],
            body: nil
        )

        let urlRequest = try #require(request.urlRequest(relativeTo: URL(string: "http://localhost")!))

        #expect(urlRequest.value(forHTTPHeaderField: "TE") == nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("RFC 9110 §7.6.1: Upgrade header is stripped in urlRequest conversion")
    func upgradeHeaderStripped() throws {
        let request = ParsedHTTPRequest.complete(
            method: "GET",
            target: "/wp/v2/posts",
            httpVersion: "HTTP/1.1",
            headers: [
                "Host": "localhost",
                "Upgrade": "websocket",
                "Accept": "application/json",
            ],
            body: nil
        )

        let urlRequest = try #require(request.urlRequest(relativeTo: URL(string: "http://localhost")!))

        #expect(urlRequest.value(forHTTPHeaderField: "Upgrade") == nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("RFC 9110 §7.6.1: Trailer header is stripped in urlRequest conversion")
    func trailerHeaderStripped() throws {
        let request = ParsedHTTPRequest.complete(
            method: "GET",
            target: "/wp/v2/posts",
            httpVersion: "HTTP/1.1",
            headers: [
                "Host": "localhost",
                "Trailer": "Expires",
                "Accept": "application/json",
            ],
            body: nil
        )

        let urlRequest = try #require(request.urlRequest(relativeTo: URL(string: "http://localhost")!))

        #expect(urlRequest.value(forHTTPHeaderField: "Trailer") == nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("RFC 9110 §7.6.1: headers listed in Connection header are treated as hop-by-hop")
    func connectionListedHeadersStripped() throws {
        let request = ParsedHTTPRequest.complete(
            method: "GET",
            target: "/wp/v2/posts",
            httpVersion: "HTTP/1.1",
            headers: [
                "Host": "localhost",
                "Connection": "X-Custom, close",
                "X-Custom": "should-be-stripped",
                "Accept": "application/json",
            ],
            body: nil
        )

        let urlRequest = try #require(request.urlRequest(relativeTo: URL(string: "http://localhost")!))

        #expect(urlRequest.value(forHTTPHeaderField: "X-Custom") == nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Connection") == nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("RFC 9110 §7.1: urlRequest resolves relative target against base URL")
    func urlRequestResolvesRelativeTarget() throws {
        let parser = HTTPRequestParser("GET /wp/v2/posts?per_page=5 HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let request = try #require(try parser.parseRequest())

        let urlRequest = try #require(request.urlRequest(relativeTo: URL(string: "http://localhost:8080")!))
        #expect(urlRequest.url?.absoluteString == "http://localhost:8080/wp/v2/posts?per_page=5")
    }
}
