import Foundation
import Testing
@testable import GutenbergKitHTTP

@Suite("ParsedHTTPRequest")
struct ParsedHTTPRequestTests {

    // MARK: - urlRequest(relativeTo:)

    @Test("urlRequest resolves path against base URL")
    func urlRequestResolvesPath() {
        let request = ParsedHTTPRequest.complete(
            method: "GET",
            target: "/wp/v2/posts?per_page=10",
            httpVersion: "HTTP/1.1",
            headers: ["Accept": "application/json"],
            body: nil
        )

        let baseURL = URL(string: "https://example.com/wp-json")!
        let urlRequest = request.urlRequest(relativeTo: baseURL)

        #expect(urlRequest != nil)
        #expect(urlRequest?.url?.absoluteString == "https://example.com/wp/v2/posts?per_page=10")
        #expect(urlRequest?.httpMethod == "GET")
        #expect(urlRequest?.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("urlRequest includes body stream")
    func urlRequestIncludesBody() throws {
        let body = Data(#"{"title":"Test"}"#.utf8)
        let request = ParsedHTTPRequest.complete(
            method: "POST",
            target: "/wp/v2/posts",
            httpVersion: "HTTP/1.1",
            headers: ["Content-Type": "application/json"],
            body: RequestBody(data: body)
        )

        let baseURL = URL(string: "https://example.com/wp-json")!
        let urlRequest = request.urlRequest(relativeTo: baseURL)

        #expect(urlRequest?.httpBodyStream != nil)
        #expect(urlRequest?.httpMethod == "POST")
    }

    @Test("urlRequest strips hop-by-hop headers")
    func urlRequestStripsHopByHopHeaders() {
        let request = ParsedHTTPRequest.complete(
            method: "GET",
            target: "/wp/v2/posts",
            httpVersion: "HTTP/1.1",
            headers: [
                "Host": "localhost:8080",
                "Connection": "keep-alive",
                "Accept": "application/json",
                "Transfer-Encoding": "chunked",
                "Keep-Alive": "timeout=5",
                "Proxy-Connection": "keep-alive",
            ],
            body: nil
        )

        let baseURL = URL(string: "https://example.com")!
        let urlRequest = request.urlRequest(relativeTo: baseURL)!

        #expect(urlRequest.value(forHTTPHeaderField: "Host") == nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Connection") == nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Transfer-Encoding") == nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Keep-Alive") == nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Proxy-Connection") == nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    // MARK: - header(_:)

    @Test("header returns nil for missing header")
    func headerReturnsNilForMissing() {
        let request = ParsedHTTPRequest.complete(
            method: "GET",
            target: "/",
            httpVersion: "HTTP/1.1",
            headers: ["Accept": "text/html"],
            body: nil
        )

        #expect(request.header("Authorization") == nil)
    }

    @Test("header is case-insensitive")
    func headerCaseInsensitive() {
        let request = ParsedHTTPRequest.complete(
            method: "GET",
            target: "/",
            httpVersion: "HTTP/1.1",
            headers: ["X-Custom-Header": "value123"],
            body: nil
        )

        #expect(request.header("x-custom-header") == "value123")
        #expect(request.header("X-CUSTOM-HEADER") == "value123")
    }

    // MARK: - Partial vs Complete

    @Test("partial request has no body")
    func partialHasNoBody() {
        let request = ParsedHTTPRequest.partial(
            method: "POST",
            target: "/wp/v2/posts",
            httpVersion: "HTTP/1.1",
            headers: ["Content-Type": "application/json"]
        )

        #expect(!request.isComplete)
        #expect(request.body == nil)
        #expect(request.method == "POST")
        #expect(request.target == "/wp/v2/posts")
    }

    @Test("complete request without body")
    func completeWithoutBody() {
        let request = ParsedHTTPRequest.complete(
            method: "GET",
            target: "/wp/v2/settings",
            httpVersion: "HTTP/1.1",
            headers: [:],
            body: nil
        )

        #expect(request.isComplete)
        #expect(request.body == nil)
    }

    // MARK: - urlRequest Edge Cases

    @Test("urlRequest returns nil for malformed target")
    func urlRequestReturnsNilForMalformedTarget() {
        let request = ParsedHTTPRequest.complete(
            method: "GET",
            target: "://not a valid url",
            httpVersion: "HTTP/1.1",
            headers: [:],
            body: nil
        )

        let baseURL = URL(string: "https://example.com")!
        #expect(request.urlRequest(relativeTo: baseURL) == nil)
    }

    // MARK: - Proxy-Authorization is stripped, Authorization passes through

    @Test("urlRequest strips Proxy-Authorization header (proxy token)")
    func urlRequestStripsProxyAuthorizationHeader() {
        let request = ParsedHTTPRequest.complete(
            method: "GET",
            target: "/wp/v2/posts",
            httpVersion: "HTTP/1.1",
            headers: [
                "Proxy-Authorization": "Bearer secret-proxy-token",
                "Authorization": "Basic dXNlcjpwYXNz",
                "Accept": "application/json",
            ],
            body: nil
        )

        let baseURL = URL(string: "https://example.com")!
        let urlRequest = request.urlRequest(relativeTo: baseURL)!

        #expect(urlRequest.value(forHTTPHeaderField: "Proxy-Authorization") == nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Basic dXNlcjpwYXNz")
        #expect(urlRequest.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("urlRequest strips lowercase proxy-authorization header")
    func urlRequestStripsLowercaseProxyAuthorizationHeader() {
        let request = ParsedHTTPRequest.complete(
            method: "GET",
            target: "/wp/v2/posts",
            httpVersion: "HTTP/1.1",
            headers: [
                "proxy-authorization": "Bearer secret-proxy-token",
                "Accept": "application/json",
            ],
            body: nil
        )

        let baseURL = URL(string: "https://example.com")!
        let urlRequest = request.urlRequest(relativeTo: baseURL)!

        #expect(urlRequest.value(forHTTPHeaderField: "proxy-authorization") == nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("urlRequest strips Relay-Authorization header (fetch()-compatible proxy token)")
    func urlRequestStripsRelayAuthorizationHeader() {
        let request = ParsedHTTPRequest.complete(
            method: "GET",
            target: "/wp/v2/posts",
            httpVersion: "HTTP/1.1",
            headers: [
                "Relay-Authorization": "Bearer secret-proxy-token",
                "Authorization": "Basic dXNlcjpwYXNz",
                "Accept": "application/json",
            ],
            body: nil
        )

        let baseURL = URL(string: "https://example.com")!
        let urlRequest = request.urlRequest(relativeTo: baseURL)!

        #expect(urlRequest.value(forHTTPHeaderField: "Relay-Authorization") == nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Basic dXNlcjpwYXNz")
        #expect(urlRequest.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("urlRequest strips lowercase relay-authorization header")
    func urlRequestStripsLowercaseRelayAuthorizationHeader() {
        let request = ParsedHTTPRequest.complete(
            method: "GET",
            target: "/wp/v2/posts",
            httpVersion: "HTTP/1.1",
            headers: [
                "relay-authorization": "Bearer secret-proxy-token",
                "Accept": "application/json",
            ],
            body: nil
        )

        let baseURL = URL(string: "https://example.com")!
        let urlRequest = request.urlRequest(relativeTo: baseURL)!

        #expect(urlRequest.value(forHTTPHeaderField: "relay-authorization") == nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("urlRequest strips both Proxy-Authorization and Relay-Authorization when both present")
    func urlRequestStripsBothProxyAndRelayAuth() {
        let request = ParsedHTTPRequest.complete(
            method: "GET",
            target: "/wp/v2/posts",
            httpVersion: "HTTP/1.1",
            headers: [
                "Proxy-Authorization": "Bearer token-a",
                "Relay-Authorization": "Bearer token-b",
                "Authorization": "Basic dXNlcjpwYXNz",
                "Accept": "application/json",
            ],
            body: nil
        )

        let baseURL = URL(string: "https://example.com")!
        let urlRequest = request.urlRequest(relativeTo: baseURL)!

        #expect(urlRequest.value(forHTTPHeaderField: "Proxy-Authorization") == nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Relay-Authorization") == nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Basic dXNlcjpwYXNz")
    }

    // MARK: - Fix #2: Case-insensitive Connection header for hop-by-hop extension

    @Test("urlRequest strips headers listed in lowercase connection header")
    func urlRequestStripsHeadersFromLowercaseConnectionHeader() {
        let request = ParsedHTTPRequest.complete(
            method: "GET",
            target: "/wp/v2/posts",
            httpVersion: "HTTP/1.1",
            headers: [
                "connection": "X-Custom, close",
                "X-Custom": "should-be-stripped",
                "Accept": "application/json",
            ],
            body: nil
        )

        let baseURL = URL(string: "https://example.com")!
        let urlRequest = request.urlRequest(relativeTo: baseURL)!

        #expect(urlRequest.value(forHTTPHeaderField: "X-Custom") == nil)
        #expect(urlRequest.value(forHTTPHeaderField: "connection") == nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("urlRequest strips headers listed in mixed-case CONNECTION header")
    func urlRequestStripsHeadersFromMixedCaseConnectionHeader() {
        let request = ParsedHTTPRequest.complete(
            method: "GET",
            target: "/wp/v2/posts",
            httpVersion: "HTTP/1.1",
            headers: [
                "CONNECTION": "X-Private",
                "X-Private": "should-be-stripped",
                "Accept": "text/html",
            ],
            body: nil
        )

        let baseURL = URL(string: "https://example.com")!
        let urlRequest = request.urlRequest(relativeTo: baseURL)!

        #expect(urlRequest.value(forHTTPHeaderField: "X-Private") == nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Accept") == "text/html")
    }
}
