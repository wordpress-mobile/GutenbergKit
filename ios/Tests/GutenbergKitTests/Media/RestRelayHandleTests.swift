import Foundation
import Testing
import GutenbergKitHTTP
@testable import GutenbergKit

/// Covers what ``RestRelay/handle(_:)`` sends upstream and what it hands back,
/// against a stubbed session rather than a site.
///
/// The header rewriting on both sides of the hop is the part of the relay that
/// fails silently: an upstream `Access-Control-Allow-Origin` that survives is
/// honored by WebKit over the policy's own, and a surviving `Content-Encoding`
/// makes WebKit decode an already-decoded body.
@Suite("RestRelay request handling")
struct RestRelayHandleTests {

    // MARK: - Session

    @Test("waits as long as an upload for a slow site")
    func sharedSessionWaitsAsLongAsAnUpload() {
        #expect(RestRelay.sharedSession.configuration.timeoutIntervalForRequest == EditorHTTPClient.uploadInactivityTimeout)
    }

    @Test("doesn't answer one caller with a response cached for another")
    func sharedSessionDoesNotShareCachedResponses() async throws {
        // A server may let a client cache a response to a request that carried
        // a token. `URLCache` keys on the URL alone, and the shared session
        // serves every frame, so a cached copy would reach a caller that sent
        // another token. A stubbed `URLProtocol` is never answered from the
        // cache, so this needs a real server.
        let server = try await HTTPServer.start(name: "relay-cache-test", requiresAuthentication: false) { request in
            HTTPResponse(
                status: 200,
                headers: [("Content-Type", "text/plain"), ("Cache-Control", "private, max-age=600")],
                body: Data((request.parsed.header("Authorization") ?? "none").utf8)
            )
        }
        defer { server.stop() }

        let site = "http://127.0.0.1:\(server.port)"
        let relay = RestRelay(
            configuration: EditorConfigurationBuilder(
                postType: .post,
                siteURL: URL(string: site)!,
                siteApiRoot: URL(string: "\(site)/wp-json/")!,
                authHeader: "Bearer test-token"
            ).build()
        )
        // A URL of its own, so no other test's response is in the cache.
        let url = Self.relayURL(for: "\(site)/wp-json/wp/v2/users/me?test=\(UUID().uuidString)")

        var first = URLRequest(url: url)
        first.setValue("Bearer TOKEN-A", forHTTPHeaderField: "Authorization")
        let firstResponse = try await relay.handle(first).collected()

        var second = URLRequest(url: url)
        second.setValue("Bearer TOKEN-B", forHTTPHeaderField: "Authorization")
        let secondResponse = try await relay.handle(second).collected()

        #expect(String(decoding: firstResponse.body, as: UTF8.self) == "Bearer TOKEN-A")
        #expect(String(decoding: secondResponse.body, as: UTF8.self) == "Bearer TOKEN-B")
    }

    // MARK: - Request rewriting

    @Test("adds the site credential to a site API request that has none")
    func addsSiteCredential() async throws {
        let exchange = try await relay()

        #expect(exchange.upstream.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
    }

    @Test("sends a caller's own credential to the site API as it is")
    func keepsCallerCredentialForSiteAPI() async throws {
        // Jetpack AI on a WordPress.com site: the API root is
        // `public-api.wordpress.com`, and the request carries a token of its own.
        let exchange = try await relay(headers: ["Authorization": "Bearer caller-token"])

        #expect(exchange.upstream.value(forHTTPHeaderField: "Authorization") == "Bearer caller-token")
    }

    // MARK: - Other hosts

    @Test("forwards a request for another host to the URL it names")
    func forwardsToAnotherHost() async throws {
        let exchange = try await relay(
            target: Self.relayTarget("https://public-api.wordpress.com/wpcom/v2/jetpack-ai-query?stream=true"),
            method: "POST",
            headers: ["Content-Type": "application/json"],
            body: Data(#"{"question":"Hi"}"#.utf8),
            responseBody: Data("answer".utf8)
        )

        #expect(exchange.upstream.url?.absoluteString == "https://public-api.wordpress.com/wpcom/v2/jetpack-ai-query?stream=true")
        #expect(exchange.upstream.httpMethod == "POST")
        #expect(exchange.upstream.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(exchange.sentBody == Data(#"{"question":"Hi"}"#.utf8))
        #expect(exchange.response.status == 200)
        #expect(exchange.response.body == Data("answer".utf8))
        #expect(exchange.response.header("Access-Control-Allow-Origin") == "*")
    }

    @Test("sends a caller's own credential to another host as it is")
    func keepsCallerCredentialForAnotherHost() async throws {
        let exchange = try await relay(
            target: Self.relayTarget("https://public-api.wordpress.com/wpcom/v2/jetpack-ai-query"),
            headers: ["Authorization": "Bearer jwt"]
        )

        #expect(exchange.upstream.value(forHTTPHeaderField: "Authorization") == "Bearer jwt")
    }

    @Test("never adds the site credential to a request for another host")
    func addsNoSiteCredentialForAnotherHost() async throws {
        let exchange = try await relay(target: Self.relayTarget("https://example.org/api"))

        #expect(exchange.upstream.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("sends the site credential the page attached to another host as it is")
    func keepsPageSentSiteCredentialForAnotherHost() async throws {
        // Which hosts get the site credential is the page's decision. The page
        // holds the credential, so removing it here would protect nothing.
        for target in ["https://example.org/api", "https://example.com/b/wp-json/wp/v2/posts"] {
            let exchange = try await relay(
                target: Self.relayTarget(target),
                headers: ["Authorization": "Bearer test-token"]
            )

            #expect(exchange.upstream.value(forHTTPHeaderField: "Authorization") == "Bearer test-token", "\(target)")
        }
    }

    @Test("sends the page's Authorization to the rest of the site as it is, and adds nothing")
    func keepsCallerCredentialForRestOfSite() async throws {
        // VideoPress asks `admin-ajax.php` for its upload token with
        // `apiFetch( { url: ajaxurl } )`. It is the site, but not its REST API.
        let target = Self.relayTarget("https://example.com/wp-admin/admin-ajax.php")

        let withHeader = try await relay(target: target, headers: ["Authorization": "Bearer test-token"])
        #expect(withHeader.upstream.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")

        let withoutHeader = try await relay(target: target)
        #expect(withoutHeader.upstream.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("sends a joined Authorization as it is, wherever it goes")
    func keepsJoinedAuthorization() async throws {
        // A caller that writes its header as `authorization`, plus api-fetch's
        // `Authorization`: `Headers` keeps both, joined with ", ". `fetch`
        // would send that value as it is, so the relay does too.
        for target in ["https://example.com/wp-json/wp/v2/posts", "https://example.org/api"] {
            let exchange = try await relay(
                target: Self.relayTarget(target),
                headers: ["Authorization": "Bearer own-key, Bearer test-token"]
            )

            #expect(exchange.upstream.value(forHTTPHeaderField: "Authorization") == "Bearer own-key, Bearer test-token", "\(target)")
        }
    }

    @Test(
        "replaces nothing, and adds the site credential only to a site API request without one",
        arguments: [
            // (caller's value, to the site API, expected)
            (nil, true, "Bearer test-token"),
            (nil, false, nil),
            ("Bearer own-key", true, "Bearer own-key"),
            ("Bearer own-key", false, "Bearer own-key"),
            ("Bearer test-token", false, "Bearer test-token"),
            ("Bearer own-key, Bearer test-token", true, "Bearer own-key, Bearer test-token"),
            ("Bearer own-key, Bearer test-token", false, "Bearer own-key, Bearer test-token"),
            // An empty header is still the caller's, and isn't replaced.
            ("", true, ""),
        ] as [(String?, Bool, String?)]
    )
    func authorizationRule(callerValue: String?, toSiteAPI: Bool, expected: String?) {
        #expect(Self.siteRelay(authHeader: "Bearer test-token").authorization(sentByCaller: callerValue, toSiteAPI: toSiteAPI) == expected)
    }

    @Test("adds nothing when the editor has no site credential")
    func addsNothingWithoutSiteCredential() {
        #expect(Self.siteRelay(authHeader: "").authorization(sentByCaller: nil, toSiteAPI: true) == nil)
    }

    private static func siteRelay(authHeader: String) -> RestRelay {
        RestRelay(
            configuration: EditorConfigurationBuilder(
                postType: .post,
                siteURL: URL(string: "https://example.com")!,
                siteApiRoot: URL(string: "https://example.com/wp-json/")!,
                authHeader: authHeader
            ).build()
        )
    }

    @Test("refuses anything but an http or https URL before sending anything")
    func refusesOtherSchemes() async throws {
        for target in [
            Self.relayTarget("file:///etc/hosts"),
            Self.relayTarget("gbk-rest://relay/fetch?url=https%3A%2F%2Fexample.org%2F"),
            Self.relayTarget("https:no-host"),
            Self.relayTarget("not a url"),
            "/fetch",
            "/fetch/https://example.org/",
            "/proxy/wp/v2/posts",
        ] {
            let exchange = try await relay(target: target)

            #expect(exchange.response.status == 400, "\(target)")
            #expect(exchange.sentRequest == nil, "nothing should have been sent for \(target)")
        }
    }

    @Test("refuses a URL with a user name or password before sending anything")
    func refusesCredentialsInURL() async throws {
        // As `fetch` does. `URLSession` would store them and send them on
        // later requests to the host, in place of the caller's own.
        for url in [
            "https://user:pass@api.example/v1",
            "https://user@api.example/v1",
            "https://example.com@evil.example/",
            "https://user:pass@example.com/wp-json/wp/v2/posts",
        ] {
            let exchange = try await relay(target: Self.relayTarget(url))

            #expect(exchange.response.status == 400, "\(url)")
            #expect(String(decoding: exchange.response.body, as: UTF8.self).contains("relay_credentials_in_url"), "\(url)")
            #expect(exchange.sentRequest == nil, "nothing should have been sent for \(url)")
        }
    }

    // MARK: - Plain http

    @Test("refuses a plain http request to another host before sending it")
    func refusesHTTPToOtherHosts() async throws {
        // A local address in any spelling, a name that could point at one, and
        // a public host. None of them is the site.
        for url in [
            "http://192.168.1.1/admin",
            "http://127.0.0.1:8080/x",
            "http://2130706433:8080/x",
            "http://[::1]:3000/",
            "http://router.example/admin",
            "http://api.example/v1",
            "http://example.com.evil.example/",
        ] {
            let exchange = try await relay(target: Self.relayTarget(url))

            #expect(exchange.response.status == 426, "\(url)")
            #expect(exchange.response.header("Upgrade") == "TLS/1.2, HTTP/1.1", "\(url)")
            #expect(String(decoding: exchange.response.body, as: UTF8.self).contains("relay_https_required"), "\(url)")
            #expect(exchange.sentRequest == nil, "nothing should have been sent for \(url)")
        }
    }

    @Test("sends a plain http request to the site's own host, on any port")
    func sendsHTTPToSiteHost() async throws {
        // The host of the API root or of the site URL, in the spellings
        // `destination(of:)` takes for the site.
        for (root, siteURL, url) in [
            ("http://192.168.1.50/wp-json/", "http://192.168.1.50", "http://192.168.1.50/wp-admin/admin-ajax.php"),
            ("http://192.168.1.50/wp-json/", "http://192.168.1.50", "http://192.168.1.50:8080/api"),
            ("http://localhost:8888/wp-json/", "http://localhost:8888", "http://127.0.0.1:3000/api"),
            ("https://example.com/wp-json/", "https://example.com", "http://www.example.com/legacy.php"),
            // A Jetpack site reached through WordPress.com, whose plugins call
            // the site's own host.
            ("https://public-api.wordpress.com/", "http://jetpack.example", "http://jetpack.example/wp-admin/admin-ajax.php"),
        ] {
            let exchange = try await relay(target: Self.relayTarget(url), siteApiRoot: root, siteURL: siteURL)

            #expect(exchange.sentRequest?.url?.absoluteString == url, "\(url)")
        }
    }

    @Test("sends an https request to any host")
    func sendsHTTPSToAnyHost() async throws {
        // A device on the local network can't present a valid certificate for
        // the name, so TLS stops a name pointed at one before anything is sent.
        for url in ["https://192.168.1.1/admin", "https://localhost:8443/", "https://api.example/v1"] {
            let exchange = try await relay(target: Self.relayTarget(url))

            #expect(exchange.sentRequest?.url?.absoluteString == url, "\(url)")
        }
    }

    @Test("strips the headers that describe the web view's own hop")
    func stripsHopHeaders() async throws {
        // `origin`/`referer`/`sec-fetch-*` describe the `file://` page and are
        // what WordPress rejects in the first place; the page's cookies are
        // not how the relay authenticates; the rest belong to the hop.
        let exchange = try await relay(headers: [
            "Origin": "file://",
            "Referer": "file:///editor.html",
            "Sec-Fetch-Site": "cross-site",
            "Sec-Fetch-Mode": "cors",
            "Cookie": "wordpress_logged_in_abc=1",
            "Connection": "keep-alive",
            "Accept-Encoding": "gzip, deflate",
        ])

        for header in [
            "Origin", "Referer", "Sec-Fetch-Site", "Sec-Fetch-Mode",
            "Cookie", "Connection",
        ] {
            #expect(
                exchange.upstream.value(forHTTPHeaderField: header) == nil,
                "\(header) should not reach the site"
            )
        }
    }

    @Test("forwards the headers the site needs")
    func forwardsContentHeaders() async throws {
        let exchange = try await relay(
            method: "POST",
            headers: ["Content-Type": "application/json", "X-HTTP-Method-Override": "PUT"]
        )

        #expect(exchange.upstream.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(exchange.upstream.value(forHTTPHeaderField: "X-HTTP-Method-Override") == "PUT")
        #expect(exchange.upstream.httpMethod == "POST")
    }

    @Test("sends a POST body that has no type as application/octet-stream")
    func typesUntypedPostBody() async throws {
        let exchange = try await relay(method: "POST", body: Data("raw bytes".utf8))

        #expect(exchange.upstream.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
        #expect(exchange.sentBody == Data("raw bytes".utf8))
    }

    @Test(
        "leaves Content-Type alone when URLSession adds none",
        arguments: [
            ("PUT", Data("raw bytes".utf8)),
            ("POST", Data()),
        ]
    )
    func leavesOtherBodiesUntyped(method: String, body: Data) async throws {
        let exchange = try await relay(method: method, body: body)

        #expect(exchange.upstream.value(forHTTPHeaderField: "Content-Type") == nil)
    }

    // MARK: - Response rewriting

    @Test("strips the upstream CORS headers that would override the policy's")
    func stripsUpstreamCORSHeaders() async throws {
        // WordPress answers an origin it rejects with an *empty*
        // `Access-Control-Allow-Origin`. One that survived would replace the
        // relay's own, and WebKit would reject the response the relay exists
        // to deliver.
        let exchange = try await relay(responseHeaders: [
            "Access-Control-Allow-Origin": "",
            "Access-Control-Allow-Credentials": "true",
            "Access-Control-Expose-Headers": "X-Upstream",
            "Vary": "Origin",
        ])

        for header in ["Access-Control-Allow-Credentials", "Vary"] {
            #expect(
                exchange.response.header(header) == nil,
                "\(header) should not reach the web view"
            )
        }
        // The relay's own headers replace the upstream's, rather than both
        // arriving and the browser reading whichever came first.
        #expect(exchange.response.header("Access-Control-Allow-Origin") == "*")
        let exposed = exchange.response.headers.filter { $0.key.lowercased() == "access-control-expose-headers" }
        #expect(exposed.count == 1)
        #expect(exposed.first?.value.hasPrefix("*, Allow") == true)
    }

    @Test("strips the site's cookies rather than rescoping them to the relay")
    func stripsSetCookie() async throws {
        // Passed on, these would be stored against the relay's scheme, a
        // different origin from the site that set them.
        let exchange = try await relay(responseHeaders: [
            "Set-Cookie": "wordpress_logged_in_abc=user%7C123; Path=/; HttpOnly",
        ])

        #expect(exchange.response.header("Set-Cookie") == nil)
    }

    @Test("strips Content-Encoding and Content-Length, which URLSession already acted on")
    func stripsContentEncoding() async throws {
        // `URLSession` decompresses transparently, so advertising the upstream
        // encoding makes WebKit decode plain bytes a second time, and the
        // upstream length is the compressed one.
        let exchange = try await relay(responseHeaders: ["Content-Encoding": "gzip", "Content-Length": "12"])

        #expect(exchange.response.header("Content-Encoding") == nil)
        #expect(exchange.response.header("Content-Length") == nil)
    }

    @Test("sends the page's body on, and exposes a block's own response headers")
    func relaysBodiesAndPluginHeaders() async throws {
        // A VideoPress chunk: the page read its `Blob` into an `ArrayBuffer`,
        // which WebKit delivers as `httpBody`, and the block reads the video
        // it made off the response headers.
        let exchange = try await relay(
            target: Self.relayTarget("https://example.com/wp-json/videopress/v1/upload-relay/abc"),
            method: "POST",
            headers: ["Content-Type": "application/offset+octet-stream", "Upload-Offset": "0"],
            body: Data("chunk bytes".utf8),
            status: 204,
            responseHeaders: ["x-videopress-upload-guid": "eDeLfBNN"]
        )

        #expect(exchange.upstream.url?.absoluteString == "https://example.com/wp-json/videopress/v1/upload-relay/abc")
        #expect(exchange.sentBody == Data("chunk bytes".utf8))
        #expect(exchange.upstream.value(forHTTPHeaderField: "Upload-Offset") == "0")
        #expect(exchange.response.status == 204)
        #expect(exchange.response.header("x-videopress-upload-guid") == "eDeLfBNN")
        #expect(exchange.response.header("Access-Control-Expose-Headers")?.hasPrefix("*") == true)
    }

    @Test("relays the status, body, and the headers the editor reads")
    func relaysStatusBodyAndHeaders() async throws {
        let exchange = try await relay(
            status: 201,
            responseHeaders: ["Allow": "GET, POST", "X-WP-Total": "42"],
            responseBody: Data(#"{"id":1}"#.utf8)
        )

        #expect(exchange.response.status == 201)
        #expect(exchange.response.body == Data(#"{"id":1}"#.utf8))
        #expect(exchange.response.header("Allow") == "GET, POST")
        #expect(exchange.response.header("X-WP-Total") == "42")
    }

    @Test("throws when the site can't be reached, rather than answering for it")
    func throwsWhenSiteUnreachable() async throws {
        await #expect {
            try await relay(failure: URLError(.notConnectedToInternet))
        } throws: { error in
            (error as? URLError)?.code == .notConnectedToInternet
        }
    }

    @Test("reports the upstream request's task to the observer, with the whole body")
    func reportsUpstreamTask() async throws {
        let recorder = TaskEventRecorder()

        _ = try await relay(responseBody: Data("[]".utf8), observer: recorder)

        #expect(recorder.events == ["created", "metrics", "completed", "performed"])
        #expect(Set(recorder.tasks).count == 1)
        guard case .bytes(let body) = recorder.completedData else {
            Issue.record("expected the response body, got \(String(describing: recorder.completedData))")
            return
        }
        #expect(body == Data("[]".utf8))
    }

    @Test("reports the task of a request that never reaches the site")
    func reportsUnreachableTask() async throws {
        let recorder = TaskEventRecorder()

        _ = try? await relay(failure: URLError(.notConnectedToInternet), observer: recorder)

        #expect(recorder.events.first == "created")
        #expect(recorder.events.last == "failed")
    }

    @Test("refuses a site API redirect to another host, rather than following it")
    func refusesRedirectToAnotherHost() async throws {
        let recorder = TaskEventRecorder()

        let exchange = try await relay(status: 302, redirect: "https://elsewhere.example/wp-json/wp/v2/posts", observer: recorder)

        #expect(exchange.response.status == 502)
        #expect(String(decoding: exchange.response.body, as: UTF8.self).contains("relay_redirect_refused"))
        #expect(exchange.response.header("Location") == nil)
        // The relay answers before the upstream task has finished.
        try await waitUntil { recorder.events.contains("completed") }
        #expect(!recorder.events.contains("performed"), "reported the refused redirect as the answer")
    }

    @Test("refuses a path outside the API root before sending anything")
    func refusesForbiddenPath() async throws {
        let exchange = try await relay(target: Self.relayTarget("https://example.com/wp-json/../wp-admin/"))

        #expect(exchange.response.status == 403)
        #expect(exchange.sentRequest == nil, "nothing should have been sent upstream")
    }

    // MARK: - Helpers

    /// The relay target for a request to `url`, encoded as the page encodes it
    /// (`encodeURIComponent`).
    static func relayTarget(_ url: String) -> String {
        // `CharacterSet.alphanumerics` would leave non-ASCII letters unencoded.
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.!~*'()")
        return "\(RestRelay.route)?url=" + url.addingPercentEncoding(withAllowedCharacters: allowed)!
    }

    /// The relay URL the page sends a request for `url` to.
    static func relayURL(for url: String) -> URL {
        URL(string: "gbk-rest://relay" + relayTarget(url))!
    }

    /// One relayed exchange: what reached the stub, and what the relay returned.
    private struct Exchange {
        let sentRequest: URLRequest?
        let sentBody: Data?
        let response: SchemeResponse

        /// The request that reached the stub. Fails the test if none did.
        var upstream: URLRequest {
            guard let sentRequest else {
                Issue.record("No request reached the stubbed session")
                return URLRequest(url: URL(string: "about:blank")!)
            }
            return sentRequest
        }
    }

    /// Relays one request through a stubbed session and reports both sides.
    private func relay(
        target: String = RestRelayHandleTests.relayTarget("https://example.com/wp-json/wp/v2/posts?_locale=user"),
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil,
        status: Int = 200,
        responseHeaders: [String: String] = [:],
        responseBody: Data = Data(),
        failure: (any Error)? = nil,
        redirect: String? = nil,
        observer: (any EditorHTTPClientDelegate)? = nil,
        siteApiRoot: String = "https://example.com/wp-json/",
        siteURL: String = "https://example.com"
    ) async throws -> Exchange {
        let stub = StubURLProtocol.Stub(
            status: status,
            headers: responseHeaders,
            body: responseBody,
            failure: failure,
            redirect: redirect.map { URL(string: $0)! }
        )
        let stubbed = StubURLProtocol.makeSession(stub: stub)
        defer { stubbed.finish() }

        let relay = RestRelay(
            configuration: EditorConfigurationBuilder(
                postType: .post,
                siteURL: URL(string: siteURL)!,
                siteApiRoot: URL(string: siteApiRoot)!,
                authHeader: "Bearer test-token"
            ).build(),
            session: stubbed.session,
            observer: observer
        )

        var request = URLRequest(url: try #require(URL(string: "gbk-rest://relay\(target)")))
        request.httpMethod = method
        request.allHTTPHeaderFields = headers
        request.httpBody = body
        let response = try await relay.handle(request).collected()

        return Exchange(sentRequest: stubbed.recorder.request, sentBody: stubbed.recorder.request?.httpBody, response: response)
    }
}

private extension SchemeResponse {
    /// The value of the first header matching `name`, case-insensitively.
    func header(_ name: String) -> String? {
        headers.first { $0.key.lowercased() == name.lowercased() }?.value
    }
}

extension RestRelay.Response {
    /// Reads the whole body, and returns the complete response.
    func collected() async throws -> SchemeResponse {
        SchemeResponse(status: status, headers: headers, body: try await body.reduce(into: Data()) { $0.append($1) })
    }
}

/// Covers how ``RestRelaySchemeHandler`` answers the page. A failure to reach the
/// site has to fail the page's `fetch`, as it would without the relay: api-fetch
/// turns that into `offline_error`, and an HTTP response would hide it.
@MainActor
@Suite("RestRelaySchemeHandler")
struct RestRelaySchemeHandlerTests {
    @Test("fails the page's request when the site can't be reached")
    func failsWhenSiteUnreachable() async throws {
        let stubbed = StubURLProtocol.makeSession(stub: .init(failure: URLError(.notConnectedToInternet)))
        defer { stubbed.finish() }
        let handler = makeHandler(session: stubbed.session)
        let task = FakeSchemeTask(request: URLRequest(url: RestRelayHandleTests.relayURL(for: "https://example.com/wp-json/wp/v2/posts")))

        handler.start(task)
        await task.waitUntilAnswered()

        #expect((task.failure as? URLError)?.code == .notConnectedToInternet)
        #expect(task.response == nil, "a response would reach the page as the site's own error")
        #expect(handler.activeRequestCount == 0)
    }

    @Test("answers a refused path, so the page can show why")
    func answersRefusal() async throws {
        let stubbed = StubURLProtocol.makeSession(stub: .init())
        defer { stubbed.finish() }
        let handler = makeHandler(session: stubbed.session)
        let task = FakeSchemeTask(request: URLRequest(url: RestRelayHandleTests.relayURL(for: "https://example.com/wp-json/../wp-admin/")))

        handler.start(task)
        await task.waitUntilAnswered()

        #expect(task.status == 403)
        #expect(task.failure == nil)
    }

    /// WebKit can create a new request at the address of one it just stopped. Starting the
    /// same object again stands in for that.
    @Test("doesn't give a new request at a stopped one's address the stopped one's outcome")
    func staleWorkMissesANewRequest() async throws {
        let stubbed = StubURLProtocol.makeSession(stub: .init(body: Data("[]".utf8)))
        defer { stubbed.finish() }
        let handler = makeHandler(session: stubbed.session)
        let task = FakeSchemeTask(request: URLRequest(url: RestRelayHandleTests.relayURL(for: "https://example.com/wp-json/wp/v2/posts")))

        handler.start(task)
        handler.stop(task)
        handler.start(task)
        await task.waitUntilAnswered()

        #expect(task.failure == nil, "the stopped request's cancellation reached the new request")
        #expect(task.status == 200)
    }

    // MARK: - Streaming

    /// The `Content-Type` for streamed test responses. `URLSession` holds back a
    /// response with no type, or `text/plain`, until it has 512 bytes.
    private static let eventStream = ["Content-Type": "text/event-stream"]

    @Test("passes the body on to the page as it arrives")
    func streamsTheBody() async throws {
        let gate = StubURLProtocol.Gate()
        let stubbed = StubURLProtocol.makeSession(stub: .init(
            headers: Self.eventStream,
            body: Data("data: one\n\n".utf8),
            gate: gate,
            rest: Data("data: two\n\n".utf8)
        ))
        defer { stubbed.finish() }
        let handler = makeHandler(session: stubbed.session)
        let task = FakeSchemeTask(request: URLRequest(url: RestRelayHandleTests.relayURL(for: "https://example.com/wp-json/wpcom/v2/jetpack-ai-query")))

        handler.start(task)
        try await waitUntil { !task.body.isEmpty }

        #expect(task.status == 200)
        #expect(task.header("Content-Type") == "text/event-stream")
        #expect(task.body == Data("data: one\n\n".utf8))
        #expect(!task.finished)

        gate.open()
        await task.waitUntilAnswered()

        #expect(task.body == Data("data: one\n\ndata: two\n\n".utf8))
        #expect(task.finished)
        #expect(handler.activeRequestCount == 0)
    }

    @Test("cancels the request to the site when the page stops the response partway")
    func stopCancelsAStreamingResponse() async throws {
        let gate = StubURLProtocol.Gate()
        let stubbed = StubURLProtocol.makeSession(stub: .init(
            headers: Self.eventStream,
            body: Data("data: one\n\n".utf8),
            gate: gate,
            rest: Data("data: two\n\n".utf8)
        ))
        defer { stubbed.finish() }
        let handler = makeHandler(session: stubbed.session)
        let task = FakeSchemeTask(request: URLRequest(url: RestRelayHandleTests.relayURL(for: "https://example.com/wp-json/wpcom/v2/jetpack-ai-query")))

        handler.start(task)
        try await waitUntil { !task.body.isEmpty }
        handler.stop(task)

        try await waitUntil { stubbed.recorder.wasStopped }
        gate.open()
        try await Task.sleep(for: .milliseconds(50))
        #expect(task.body == Data("data: one\n\n".utf8), "answered a stopped task, which WebKit raises on")
        #expect(!task.finished)
        #expect(task.failure == nil)
    }

    /// The handler sends each chunk on the main actor. Here the test keeps the main actor
    /// busy until the rest of the response has arrived, then stops the task. So the
    /// second chunk has reached the handler, but hasn't been sent to the page yet.
    @Test("doesn't send the page a chunk that was on its way when the page stopped the response")
    func stopDropsAChunkOnItsWay() async throws {
        let gate = StubURLProtocol.Gate()
        let stubbed = StubURLProtocol.makeSession(stub: .init(
            headers: Self.eventStream,
            body: Data("data: one\n\n".utf8),
            gate: gate,
            rest: Data("data: two\n\n".utf8)
        ))
        defer { stubbed.finish() }
        // The observer hears that the request completed only after every chunk has
        // reached the handler.
        let observer = TaskEventRecorder()
        let handler = makeHandler(session: stubbed.session, observer: observer)
        let task = FakeSchemeTask(request: URLRequest(url: RestRelayHandleTests.relayURL(for: "https://example.com/wp-json/wpcom/v2/jetpack-ai-query")))

        handler.start(task)
        try await waitUntil { !task.body.isEmpty }
        gate.open()
        try holdMainActor { observer.events.contains("completed") }
        handler.stop(task)

        try await Task.sleep(for: .milliseconds(50))
        #expect(task.body == Data("data: one\n\n".utf8), "answered a stopped task, which WebKit raises on")
        #expect(!task.finished)
        #expect(task.failure == nil)
    }

    @Test("fails the page's request, rather than finishing it, when its work is cancelled partway")
    func cancellingFailsAPartialResponse() async throws {
        let gate = StubURLProtocol.Gate()
        let stubbed = StubURLProtocol.makeSession(stub: .init(
            headers: Self.eventStream,
            body: Data("data: one\n\n".utf8),
            gate: gate,
            rest: Data("data: two\n\n".utf8)
        ))
        defer { stubbed.finish() }
        let handler = makeHandler(session: stubbed.session)
        let task = FakeSchemeTask(request: URLRequest(url: RestRelayHandleTests.relayURL(for: "https://example.com/wp-json/wpcom/v2/jetpack-ai-query")))

        handler.start(task)
        try await waitUntil { !task.body.isEmpty }
        handler.cancelAll()
        await task.waitUntilAnswered()

        #expect(task.failure != nil)
        #expect(!task.finished, "finished the page's request with part of the body")
        #expect(task.body == Data("data: one\n\n".utf8))
    }

    @Test("fails the page's request when the response breaks off partway")
    func failsWhenTheResponseBreaksOff() async throws {
        let gate = StubURLProtocol.Gate()
        let stubbed = StubURLProtocol.makeSession(stub: .init(
            headers: Self.eventStream,
            body: Data("data: one\n\n".utf8),
            gate: gate,
            restFailure: URLError(.networkConnectionLost)
        ))
        defer { stubbed.finish() }
        let handler = makeHandler(session: stubbed.session)
        let task = FakeSchemeTask(request: URLRequest(url: RestRelayHandleTests.relayURL(for: "https://example.com/wp-json/wpcom/v2/jetpack-ai-query")))

        handler.start(task)
        try await waitUntil { !task.body.isEmpty }
        gate.open()
        await task.waitUntilAnswered()

        #expect((task.failure as? URLError)?.code == .networkConnectionLost)
        #expect(task.body == Data("data: one\n\n".utf8))
        #expect(!task.finished)
        #expect(handler.activeRequestCount == 0)
    }

    /// Every response streams, whether it comes over `https` or plain `http`.
    @Test(
        "streams every response, over https or http",
        arguments: [
            ("https://example.com/wp-json/", "https://example.org/stream"),
            ("http://example.com/wp-json/", "http://example.com/stream"),
            ("http://example.com/wp-json/", "http://example.com/wp-json/wp/v2/posts"),
        ]
    )
    func streamsEveryResponse(siteApiRoot: String, url: String) async throws {
        let gate = StubURLProtocol.Gate()
        let stubbed = StubURLProtocol.makeSession(stub: .init(headers: Self.eventStream, body: Data("one ".utf8), gate: gate, rest: Data("two".utf8)))
        defer { stubbed.finish() }
        let handler = makeHandler(session: stubbed.session, siteApiRoot: siteApiRoot)
        let task = FakeSchemeTask(request: URLRequest(url: RestRelayHandleTests.relayURL(for: url)))

        handler.start(task)
        try await waitUntil { !task.body.isEmpty }
        gate.open()
        await task.waitUntilAnswered()

        #expect(task.status == 200)
        #expect(task.body == Data("one two".utf8))
        #expect(task.finished)
    }

    private func makeHandler(
        session: URLSession,
        siteApiRoot: String = "https://example.com/wp-json/",
        observer: (any EditorHTTPClientDelegate)? = nil
    ) -> RestRelaySchemeHandler {
        RestRelaySchemeHandler(relay: RestRelay(
            configuration: EditorConfigurationBuilder(
                postType: .post,
                siteURL: URL(string: "https://example.com")!,
                siteApiRoot: URL(string: siteApiRoot)!,
                authHeader: "Bearer test-token"
            ).build(),
            session: session,
            observer: observer
        ))
    }

    /// Waits for `condition` without giving up the main actor, so nothing else runs on
    /// it in the meantime. Fails the test if `condition` hasn't held within `timeout`.
    ///
    /// `condition` has to become true without the main thread. Otherwise this can only
    /// time out.
    ///
    /// The timeout is shorter than `patientTimeout`, because waiting here blocks every
    /// other main-actor test. Call it only once the response has started arriving, so
    /// a slow CI machine's start-up delay is already over.
    private func holdMainActor(
        timeout: Duration = .seconds(10),
        sourceLocation: SourceLocation = #_sourceLocation,
        until condition: () -> Bool
    ) throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() && ContinuousClock.now < deadline {
            Thread.sleep(forTimeInterval: 0.001)
        }
        try #require(condition(), "timed out waiting", sourceLocation: sourceLocation)
    }
}
