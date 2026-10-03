import Foundation
import Testing
@testable import GutenbergKit

extension EditorAuthorizationScope {
    /// The scope of the site every test here makes requests to.
    fileprivate static let example = EditorAuthorizationScope(
        siteURL: URL(string: "https://example.com")!,
        siteApiRoot: URL(string: "https://example.com/wp-json/")!
    )
}

/// A spy mock that captures requests for inspection
private final class SpyURLSession: URLSessionProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _capturedRequests: [URLRequest] = []

    var responseData = Data()

    var capturedRequests: [URLRequest] {
        lock.withLock { _capturedRequests }
    }

    var lastCapturedRequest: URLRequest? {
        capturedRequests.last
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock {
            _capturedRequests.append(request)
        }

        let url = request.url ?? URL(string: "https://example.com")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }

    func download(for request: URLRequest, delegate: (any URLSessionTaskDelegate)?) async throws -> (URL, URLResponse) {
        lock.withLock {
            _capturedRequests.append(request)
        }

        let url = request.url ?? URL(string: "https://example.com")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try responseData.write(to: tempURL)

        return (tempURL, response)
    }
}

/// A spy delegate that captures calls to didPerformRequest
private final class SpyHTTPClientDelegate: EditorHTTPClientDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(request: URLRequest, response: URLResponse, data: EditorResponseData)] = []

    var calls: [(request: URLRequest, response: URLResponse, data: EditorResponseData)] {
        lock.withLock { _calls }
    }

    var lastCall: (request: URLRequest, response: URLResponse, data: EditorResponseData)? {
        calls.last
    }

    var callCount: Int {
        lock.withLock { _calls.count }
    }

    func didPerformRequest(_ request: URLRequest, response: URLResponse, data: EditorResponseData) {
        lock.withLock {
            _calls.append((request: request, response: response, data: data))
        }
    }
}

@Suite("EditorHTTPClient")
struct EditorHTTPClientTests {

    // MARK: - Authorization Header Tests

    @Test("perform() sets Authorization header")
    func performSetsAuthorizationHeader() async throws {
        let spySession = SpyURLSession()
        let authHeader = "Bearer test-token-12345"
        let client = EditorHTTPClient(
            urlSession: spySession,
            authHeader: authHeader,
            authorizationScope: .example
        )

        let request = URLRequest(url: URL(string: "https://example.com/wp-json/wp/v2/posts")!)
        _ = try await client.perform(request)

        let capturedRequest = try #require(spySession.lastCapturedRequest)
        #expect(capturedRequest.value(forHTTPHeaderField: "Authorization") == authHeader)
    }

    @Test("download() sets Authorization header")
    func downloadSetsAuthorizationHeader() async throws {
        let spySession = SpyURLSession()
        let authHeader = "Bearer test-token-12345"
        let client = EditorHTTPClient(
            urlSession: spySession,
            authHeader: authHeader,
            authorizationScope: .example
        )

        let request = URLRequest(url: URL(string: "https://example.com/wp-content/file.js")!)
        _ = try await client.download(request)

        let capturedRequest = try #require(spySession.lastCapturedRequest)
        #expect(capturedRequest.value(forHTTPHeaderField: "Authorization") == authHeader)
    }

    // MARK: - Authorization Scope Tests

    @Test(
        "a request to another party's host goes out without the Authorization header",
        arguments: [
            "https://cdn.vendor.net/integration.js",
            "https://example.com.vendor.net/script.js",
            "http://example.com/wp-content/plugins/plugin/script.js",
        ]
    )
    func requestOutsideScopeHasNoAuthorizationHeader(url: String) async throws {
        let spySession = SpyURLSession()
        let client = EditorHTTPClient(
            urlSession: spySession,
            authHeader: "Bearer test-token-12345",
            authorizationScope: .example
        )
        let request = URLRequest(url: URL(string: url)!)

        _ = try await client.download(request)
        _ = try await client.perform(request)
        _ = try await client.performRaw(request)

        #expect(spySession.capturedRequests.count == 3)
        #expect(spySession.capturedRequests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        // It's still this library's request
        #expect(spySession.capturedRequests.allSatisfy { $0.value(forHTTPHeaderField: "User-Agent") != nil })
    }

    @Test("a client made for a configuration sends the site's credentials only to the site")
    func clientForConfigurationScopesAuthorizationHeader() async throws {
        let spySession = SpyURLSession()
        let configuration = EditorConfigurationBuilder(
            postType: .post,
            siteURL: URL(string: "https://example.com")!,
            siteApiRoot: URL(string: "https://example.com/wp-json/")!
        )
        .setAuthHeader("Bearer test-token-12345")
        .build()
        let client = EditorHTTPClient(configuration: configuration, urlSession: spySession)

        _ = try await client.download(URLRequest(url: URL(string: "https://example.com/wp-content/script.js")!))
        _ = try await client.download(URLRequest(url: URL(string: "https://cdn.vendor.net/integration.js")!))

        #expect(spySession.capturedRequests.map { $0.value(forHTTPHeaderField: "Authorization") } == [
            "Bearer test-token-12345",
            nil,
        ])
    }

    @Test("a client made for a configuration sends the site's credentials to the places it names as well")
    func clientForConfigurationAuthorizesNamedDomains() async throws {
        let spySession = SpyURLSession()
        let configuration = EditorConfigurationBuilder(
            postType: .post,
            siteURL: URL(string: "https://example.wordpress.com")!,
            siteApiRoot: URL(string: "https://public-api.wordpress.com/")!
        )
        .setAuthHeader("Bearer test-token-12345")
        .setAuthHeaderDomains(["*.wp.com"])
        .build()
        let client = EditorHTTPClient(configuration: configuration, urlSession: spySession)

        _ = try await client.download(URLRequest(url: URL(string: "https://s0.wp.com/wp-content/script.js")!))
        _ = try await client.download(URLRequest(url: URL(string: "https://cdn.vendor.net/integration.js")!))

        #expect(spySession.capturedRequests.map { $0.value(forHTTPHeaderField: "Authorization") } == [
            "Bearer test-token-12345",
            nil,
        ])
    }

    @Test("the upload client keeps the client's authorization scope")
    func uploadClientKeepsAuthorizationScope() async throws {
        let spySession = SpyURLSession()
        let client = EditorHTTPClient(
            urlSession: spySession,
            authHeader: "Bearer test-token-12345",
            authorizationScope: .example
        )
        let uploadClient = client.uploadClient()

        _ = try await uploadClient.perform(URLRequest(url: URL(string: "https://example.com/wp-json/wp/v2/media")!))
        _ = try await uploadClient.perform(URLRequest(url: URL(string: "https://cdn.vendor.net/upload")!))

        #expect(spySession.capturedRequests.map { $0.value(forHTTPHeaderField: "Authorization") } == [
            "Bearer test-token-12345",
            nil,
        ])
    }

    // MARK: - Timeout Tests

    @Test("perform() uses custom timeout")
    func performUsesCustomTimeout() async throws {
        let spySession = SpyURLSession()
        let customTimeout: TimeInterval = 120
        let client = EditorHTTPClient(
            urlSession: spySession,
            authHeader: "Bearer token",
            authorizationScope: .example,
            requestTimeout: customTimeout
        )

        let request = URLRequest(url: URL(string: "https://example.com/wp-json/wp/v2/posts")!)
        _ = try await client.perform(request)

        let capturedRequest = try #require(spySession.lastCapturedRequest)
        #expect(capturedRequest.timeoutInterval == customTimeout)
    }

    @Test("download() uses custom timeout")
    func downloadUsesCustomTimeout() async throws {
        let spySession = SpyURLSession()
        let customTimeout: TimeInterval = 120
        let client = EditorHTTPClient(
            urlSession: spySession,
            authHeader: "Bearer token",
            authorizationScope: .example,
            requestTimeout: customTimeout
        )

        let request = URLRequest(url: URL(string: "https://example.com/wp-content/file.js")!)
        _ = try await client.download(request)

        let capturedRequest = try #require(spySession.lastCapturedRequest)
        #expect(capturedRequest.timeoutInterval == customTimeout)
    }

    @Test("perform() preserves original request timeout when not specified")
    func performPreservesOriginalTimeout() async throws {
        let spySession = SpyURLSession()
        let client = EditorHTTPClient(
            urlSession: spySession,
            authHeader: "Bearer token",
            authorizationScope: .example
        )

        var request = URLRequest(url: URL(string: "https://example.com/wp-json/wp/v2/posts")!)
        request.timeoutInterval = 45

        _ = try await client.perform(request)

        let capturedRequest = try #require(spySession.lastCapturedRequest)
        #expect(capturedRequest.timeoutInterval == 45)
    }

    @Test("uploadClient() drops the REST request timeout so uploads aren't cut off mid-resize")
    func uploadClientDropsRESTTimeout() async throws {
        let spySession = SpyURLSession()
        let authHeader = "Bearer upload-token"
        // A short REST timeout a host might set for snappy REST calls.
        let restTimeout: TimeInterval = 15
        let client = EditorHTTPClient(
            urlSession: spySession,
            authHeader: authHeader,
            authorizationScope: .example,
            requestTimeout: restTimeout
        )

        let uploadClient = client.uploadClient()
        let request = URLRequest(url: URL(string: "https://example.com/wp-json/wp/v2/media")!)
        _ = try await uploadClient.performRaw(request)

        let captured = try #require(spySession.lastCapturedRequest)
        // The short REST timeout must not bleed into uploads — the request keeps
        // its own (default) inactivity timeout instead.
        #expect(captured.timeoutInterval != restTimeout)
        #expect(captured.timeoutInterval == request.timeoutInterval)
        // Auth and the shared session are still used.
        #expect(captured.value(forHTTPHeaderField: "Authorization") == authHeader)
    }

    @Test("uploadClient() preserves an explicit upload request timeout instead of clobbering it")
    func uploadClientPreservesExplicitTimeout() async throws {
        let spySession = SpyURLSession()
        let client = EditorHTTPClient(
            urlSession: spySession,
            authHeader: "Bearer token",
            authorizationScope: .example,
            requestTimeout: 15
        )

        let uploadClient = client.uploadClient()
        var request = URLRequest(url: URL(string: "https://example.com/wp-json/wp/v2/media")!)
        request.timeoutInterval = 120

        _ = try await uploadClient.performRaw(request)

        // On the REST client the requestTimeout (15) would clobber this to 15;
        // the upload client leaves it alone.
        let captured = try #require(spySession.lastCapturedRequest)
        #expect(captured.timeoutInterval == 120)
    }

    @Test("uploadClient() carries the request-observing delegate so uploads are observed too")
    func uploadClientCarriesDelegate() async throws {
        let spySession = SpyURLSession()
        let spyDelegate = SpyHTTPClientDelegate()
        let client = EditorHTTPClient(
            urlSession: spySession,
            authHeader: "Bearer token",
            authorizationScope: .example,
            delegate: spyDelegate
        )

        let uploadClient = client.uploadClient()
        let request = URLRequest(url: URL(string: "https://example.com/wp-json/wp/v2/media")!)
        _ = try await uploadClient.performRaw(request)

        // The delegate installed on the REST client must also observe requests
        // made through the upload sibling — otherwise a host logging "all network
        // requests" silently misses every media upload.
        #expect(spyDelegate.callCount == 1)
        let observed = try #require(spyDelegate.lastCall)
        #expect(observed.request.url == request.url)
    }

    // MARK: - Cookie Handling Tests

    @Test("perform() disables cookie handling")
    func performDisablesCookieHandling() async throws {
        let spySession = SpyURLSession()
        let client = EditorHTTPClient(
            urlSession: spySession,
            authHeader: "Bearer token",
            authorizationScope: .example
        )

        let request = URLRequest(url: URL(string: "https://example.com/wp-json/wp/v2/posts")!)
        _ = try await client.perform(request)

        let capturedRequest = try #require(spySession.lastCapturedRequest)
        #expect(capturedRequest.httpShouldHandleCookies == false)
    }

    @Test("download() disables cookie handling")
    func downloadDisablesCookieHandling() async throws {
        let spySession = SpyURLSession()
        let client = EditorHTTPClient(
            urlSession: spySession,
            authHeader: "Bearer token",
            authorizationScope: .example
        )

        let request = URLRequest(url: URL(string: "https://example.com/wp-content/file.js")!)
        _ = try await client.download(request)

        let capturedRequest = try #require(spySession.lastCapturedRequest)
        #expect(capturedRequest.httpShouldHandleCookies == false)
    }

    // MARK: - Request Configuration Combination Tests

    @Test("perform() configures all request properties correctly")
    func performConfiguresAllRequestProperties() async throws {
        let spySession = SpyURLSession()
        let authHeader = "Basic dXNlcm5hbWU6cGFzc3dvcmQ="
        let customTimeout: TimeInterval = 90
        let client = EditorHTTPClient(
            urlSession: spySession,
            authHeader: authHeader,
            authorizationScope: .example,
            requestTimeout: customTimeout
        )

        let request = URLRequest(url: URL(string: "https://example.com/wp-json/wp/v2/posts")!)
        _ = try await client.perform(request)

        let capturedRequest = try #require(spySession.lastCapturedRequest)
        #expect(capturedRequest.value(forHTTPHeaderField: "Authorization") == authHeader)
        #expect(capturedRequest.timeoutInterval == customTimeout)
        #expect(capturedRequest.httpShouldHandleCookies == false)
    }

    @Test("download() configures all request properties correctly")
    func downloadConfiguresAllRequestProperties() async throws {
        let spySession = SpyURLSession()
        let authHeader = "Basic dXNlcm5hbWU6cGFzc3dvcmQ="
        let customTimeout: TimeInterval = 90
        let client = EditorHTTPClient(
            urlSession: spySession,
            authHeader: authHeader,
            authorizationScope: .example,
            requestTimeout: customTimeout
        )

        let request = URLRequest(url: URL(string: "https://example.com/wp-content/file.js")!)
        _ = try await client.download(request)

        let capturedRequest = try #require(spySession.lastCapturedRequest)
        #expect(capturedRequest.value(forHTTPHeaderField: "Authorization") == authHeader)
        #expect(capturedRequest.timeoutInterval == customTimeout)
        #expect(capturedRequest.httpShouldHandleCookies == false)
    }

    // MARK: - Delegate Tests

    @Test("perform() calls delegate with request, response, and bytes data")
    func performCallsDelegate() async throws {
        let spySession = SpyURLSession()
        let spyDelegate = SpyHTTPClientDelegate()
        let responseData = Data("test response".utf8)
        spySession.responseData = responseData

        let client = EditorHTTPClient(
            urlSession: spySession,
            authHeader: "Bearer token",
            authorizationScope: .example,
            delegate: spyDelegate
        )

        let request = URLRequest(url: URL(string: "https://example.com/wp-json/wp/v2/posts")!)
        _ = try await client.perform(request)

        #expect(spyDelegate.callCount == 1)

        let lastCall = try #require(spyDelegate.lastCall)
        #expect(lastCall.request.url?.absoluteString == "https://example.com/wp-json/wp/v2/posts")
        #expect(lastCall.request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        #expect((lastCall.response as? HTTPURLResponse)?.statusCode == 200)

        let data = try #require(lastCall.data.data)
        #expect(data == responseData)
    }

    @Test("download() calls delegate with request, response, and file URL")
    func downloadCallsDelegate() async throws {
        let spySession = SpyURLSession()
        let spyDelegate = SpyHTTPClientDelegate()

        let client = EditorHTTPClient(
            urlSession: spySession,
            authHeader: "Bearer token",
            authorizationScope: .example,
            delegate: spyDelegate
        )

        let request = URLRequest(url: URL(string: "https://example.com/wp-content/file.js")!)
        _ = try await client.download(request)

        #expect(spyDelegate.callCount == 1)

        let lastCall = try #require(spyDelegate.lastCall)
        #expect(lastCall.request.url?.absoluteString == "https://example.com/wp-content/file.js")
        #expect(lastCall.request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        #expect((lastCall.response as? HTTPURLResponse)?.statusCode == 200)

        let url = try #require(lastCall.data.url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("delegate is called for each request")
    func delegateCalledForEachRequest() async throws {
        let spySession = SpyURLSession()
        let spyDelegate = SpyHTTPClientDelegate()

        let client = EditorHTTPClient(
            urlSession: spySession,
            authHeader: "Bearer token",
            authorizationScope: .example,
            delegate: spyDelegate
        )

        _ = try await client.perform(URLRequest(url: URL(string: "https://example.com/first")!))
        _ = try await client.perform(URLRequest(url: URL(string: "https://example.com/second")!))
        _ = try await client.download(URLRequest(url: URL(string: "https://example.com/third")!))

        #expect(spyDelegate.callCount == 3)
        #expect(spyDelegate.calls[0].request.url?.absoluteString == "https://example.com/first")
        #expect(spyDelegate.calls[1].request.url?.absoluteString == "https://example.com/second")
        #expect(spyDelegate.calls[2].request.url?.absoluteString == "https://example.com/third")
    }

    @Test("delegate receives configured request with authorization header")
    func delegateReceivesConfiguredRequest() async throws {
        let spySession = SpyURLSession()
        let spyDelegate = SpyHTTPClientDelegate()
        let authHeader = "Bearer secret-token"

        let client = EditorHTTPClient(
            urlSession: spySession,
            authHeader: authHeader,
            authorizationScope: .example,
            delegate: spyDelegate
        )

        let request = URLRequest(url: URL(string: "https://example.com/wp-json/wp/v2/posts")!)
        _ = try await client.perform(request)

        let lastCall = try #require(spyDelegate.lastCall)
        #expect(lastCall.request.value(forHTTPHeaderField: "Authorization") == authHeader)
        #expect(lastCall.request.httpShouldHandleCookies == false)
    }

    // MARK: - User-Agent Header Tests

    @Test("perform() sets User-Agent header with GutenbergKit identifier")
    func performSetsUserAgentHeader() async throws {
        let spySession = SpyURLSession()
        let client = EditorHTTPClient(
            urlSession: spySession,
            authHeader: "Bearer token",
            authorizationScope: .example
        )

        let request = URLRequest(url: URL(string: "https://example.com/wp-json/wp/v2/posts")!)
        _ = try await client.perform(request)

        let capturedRequest = try #require(spySession.lastCapturedRequest)
        let userAgent = try #require(capturedRequest.value(forHTTPHeaderField: "User-Agent"))
        #expect(userAgent.contains("GutenbergKit/"))
        #expect(userAgent.contains(GutenbergKitVersion.version))
    }

    @Test("download() sets User-Agent header with GutenbergKit identifier")
    func downloadSetsUserAgentHeader() async throws {
        let spySession = SpyURLSession()
        let client = EditorHTTPClient(
            urlSession: spySession,
            authHeader: "Bearer token",
            authorizationScope: .example
        )

        let request = URLRequest(url: URL(string: "https://example.com/wp-content/file.js")!)
        _ = try await client.download(request)

        let capturedRequest = try #require(spySession.lastCapturedRequest)
        let userAgent = try #require(capturedRequest.value(forHTTPHeaderField: "User-Agent"))
        #expect(userAgent.contains("GutenbergKit/"))
        #expect(userAgent.contains(GutenbergKitVersion.version))
    }

    @Test("User-Agent header includes platform identifier")
    func userAgentIncludesPlatformIdentifier() async throws {
        let spySession = SpyURLSession()
        let client = EditorHTTPClient(
            urlSession: spySession,
            authHeader: "Bearer token",
            authorizationScope: .example
        )

        let request = URLRequest(url: URL(string: "https://example.com/wp-json/wp/v2/posts")!)
        _ = try await client.perform(request)

        let capturedRequest = try #require(spySession.lastCapturedRequest)
        let userAgent = try #require(capturedRequest.value(forHTTPHeaderField: "User-Agent"))

        #if os(iOS)
        #expect(userAgent.contains("iOS/"))
        #elseif os(macOS)
        #expect(userAgent.contains("macOS/"))
        #endif
    }
}

fileprivate extension EditorResponseData {
    var data: Data? {
        guard case .bytes(let data) = self else { return nil }
        return data
    }

    var url: URL? {
        guard case .file(let url) = self else { return nil }
        return url
    }
}
