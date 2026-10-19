import Foundation
import Testing
@testable import GutenbergKit

/// Covers what ``RestRelay/handle(_:)`` sends upstream and what it hands back,
/// against a stubbed session rather than a site.
///
/// The header rewriting on both sides of the hop is the part of the relay that
/// fails silently: an upstream `Access-Control-Allow-Origin` that survives is
/// honored by WebKit over the policy's own.
@Suite("RestRelay request handling")
struct RestRelayHandleTests {

    // MARK: - Session

    @Test("waits as long as an upload for a slow site")
    func sharedSessionWaitsAsLongAsAnUpload() {
        #expect(RestRelay.sharedSession.configuration.timeoutIntervalForRequest == EditorHTTPClient.uploadInactivityTimeout)
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

    @Test("removes the site credential from a request for another host")
    func removesSiteCredentialForAnotherHost() async throws {
        // api-fetch's token middleware puts the site credential on every
        // request it makes, whatever the host.
        for target in ["https://example.org/api", "https://example.com/b/wp-json/wp/v2/posts"] {
            let exchange = try await relay(
                target: Self.relayTarget(target),
                headers: ["Authorization": "Bearer test-token"]
            )

            #expect(exchange.upstream.value(forHTTPHeaderField: "Authorization") == nil, "\(target)")
        }
    }

    @Test("removes the site credential when the page joined it to the caller's own")
    func removesSiteCredentialJoinedToCallerCredential() async throws {
        // A caller that writes its header as `authorization`, plus api-fetch's
        // `Authorization`: `Headers` keeps both, joined with ", ".
        let exchange = try await relay(
            target: Self.relayTarget("https://example.org/api"),
            headers: ["Authorization": "Bearer own-key, Bearer test-token"]
        )

        #expect(exchange.upstream.value(forHTTPHeaderField: "Authorization") == "Bearer own-key")
    }

    @Test("matches the site credential with its whitespace trimmed, and leaves other values alone")
    func matchesTrimmedSiteCredential() {
        // `Headers` trims whitespace, so the page's copy of a credential
        // configured with a trailing space has none.
        let relay = RestRelay(
            configuration: EditorConfigurationBuilder(
                postType: .post,
                siteURL: URL(string: "https://example.com")!,
                siteApiRoot: URL(string: "https://example.com/wp-json/")!,
                authHeader: "Bearer test-token "
            ).build()
        )

        #expect(relay.authorization(sentByCaller: "Bearer test-token", toSiteAPI: false) == nil)
        #expect(relay.authorization(sentByCaller: "Bearer own-key,Bearer test-token", toSiteAPI: false) == "Bearer own-key")
        // A value with commas of its own, and no site credential, goes as sent.
        let digest = #"Digest username="a", realm="b", nonce="c""#
        #expect(relay.authorization(sentByCaller: digest, toSiteAPI: false) == digest)
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
        ])

        #expect(exchange.response.header("Access-Control-Allow-Credentials") == nil)
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

    @Test("relays Content-Encoding, Content-Length and Vary as the server sent them")
    func relaysEncodingHeaders() async throws {
        // `fetch` shows the server's values over the decoded body, and WebKit
        // acts on neither header in a scheme response.
        let exchange = try await relay(
            responseHeaders: ["Content-Encoding": "gzip", "Content-Length": "12", "Vary": "Origin"],
            responseBody: Data(String(repeating: "x", count: 100).utf8)
        )

        #expect(exchange.response.header("Content-Encoding") == "gzip")
        #expect(exchange.response.header("Content-Length") == "12")
        #expect(exchange.response.header("Vary") == "Origin")
        #expect(exchange.response.body.count == 100)
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

    @Test("reports the upstream request's task to the observer")
    func reportsUpstreamTask() async throws {
        let recorder = TaskEventRecorder()

        _ = try await relay(responseBody: Data("[]".utf8), observer: recorder)

        #expect(recorder.events == ["created", "metrics", "completed", "performed"])
        #expect(Set(recorder.tasks).count == 1)
    }

    @Test("reports the task of a request that never reaches the site")
    func reportsUnreachableTask() async throws {
        let recorder = TaskEventRecorder()

        _ = try? await relay(failure: URLError(.notConnectedToInternet), observer: recorder)

        #expect(recorder.events.first == "created")
        #expect(recorder.events.last == "failed")
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
        observer: (any EditorHTTPClientDelegate)? = nil,
        siteApiRoot: String = "https://example.com/wp-json/",
        siteURL: String = "https://example.com"
    ) async throws -> Exchange {
        let stub = StubURLProtocol.Stub(
            status: status,
            headers: responseHeaders,
            body: responseBody,
            failure: failure
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
        let response = try await relay.handle(request)

        return Exchange(sentRequest: stubbed.recorder.request, sentBody: stubbed.recorder.request?.httpBody, response: response)
    }
}

private extension SchemeResponse {
    /// The value of the first header matching `name`, case-insensitively.
    func header(_ name: String) -> String? {
        headers.first { $0.key.lowercased() == name.lowercased() }?.value
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

    private func makeHandler(session: URLSession) -> RestRelaySchemeHandler {
        RestRelaySchemeHandler(relay: RestRelay(
            configuration: EditorConfigurationBuilder(
                postType: .post,
                siteURL: URL(string: "https://example.com")!,
                siteApiRoot: URL(string: "https://example.com/wp-json/")!,
                authHeader: "Bearer test-token"
            ).build(),
            session: session
        ))
    }
}
