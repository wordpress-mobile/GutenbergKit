#if canImport(Network)

import Foundation
import GutenbergKitHTTP
import Testing
@testable import GutenbergKit

/// End-to-end coverage of the relay against a real WordPress site: the request
/// crosses the loopback server, is forwarded natively, and the site's response
/// comes back to the caller.
///
/// Skipped unless `WP_ENV_CREDENTIALS_PATH` points at the credentials file
/// `make wp-env-start` writes, so a normal test run — and CI — never needs a
/// site:
///
/// ```sh
/// make wp-env-start
/// WP_ENV_CREDENTIALS_PATH="$PWD/.wp-env.credentials.json" swift test
/// ```
///
/// **`canUser` is not verifiable here.** The Playground runtime's web server
/// answers every `OPTIONS` itself with a bodiless 204 and permissive CORS
/// headers, before WordPress is reached, so no `Allow` header exists to relay.
/// What is checked instead is that the relay *forwards* an `OPTIONS` rather
/// than answering it locally — the defect that made `canUser` report no
/// capabilities at all.
@Suite("RestRelay against a live site", .enabled(if: WPEnvSite.current != nil), .serialized)
struct RestRelayIntegrationTests {

    // MARK: - Reads

    @Test("relays a GET and returns the site's response")
    func relaysGet() async throws {
        try await withRelay { server, site in
            let (data, response) = try await site.relayed("wp/v2/posts?per_page=1&_locale=user", on: server)

            #expect(response.statusCode == 200)
            #expect((try? JSONSerialization.jsonObject(with: data)) as? [Any] != nil)
        }
    }

    @Test("exposes the response headers the editor reads")
    func exposesResponseHeaders() async throws {
        try await withRelay { server, site in
            let (_, response) = try await site.relayed("wp/v2/posts?per_page=1", on: server)

            let exposed = try #require(response.value(forHTTPHeaderField: "Access-Control-Expose-Headers"))
            // `Allow` backs `canUser`, `Link` backs pagination, and the totals
            // back list counts. Unexposed, each reads as null in JavaScript.
            for header in ["Allow", "Link", "X-WP-Total", "X-WP-TotalPages"] {
                #expect(exposed.contains(header))
            }
        }
    }

    @Test("forwards an OPTIONS request upstream instead of answering it locally")
    func forwardsOptions() async throws {
        try await withRelay { server, site in
            let (_, response) = try await site.relayed("wp/v2/pages", method: "OPTIONS", on: server)

            // The local server would answer with a bare 204 carrying only its
            // own CORS headers. A response bearing the site's server headers
            // can only have come from the site.
            #expect(response.value(forHTTPHeaderField: "X-Powered-By") != nil)
        }
    }

    @Test("serves concurrent requests past the library's default connection cap")
    func servesConcurrentRequests() async throws {
        try await withRelay { server, site in
            // Editor boot fans out well past the default of 5, and a connection
            // over the limit is closed rather than queued.
            let statuses = try await withThrowingTaskGroup(of: Int.self) { group in
                for page in 1...10 {
                    group.addTask {
                        let (_, response) = try await site.relayed(
                            "wp/v2/types?_locale=user&page=\(page)", on: server
                        )
                        return response.statusCode
                    }
                }
                return try await group.reduce(into: [Int]()) { $0.append($1) }
            }

            #expect(statuses.count == 10)
            #expect(statuses.allSatisfy { $0 == 200 })
        }
    }

    // MARK: - Writes

    @Test("relays a write body, and the site actually stores it")
    func relaysWriteBody() async throws {
        try await withRelay { server, site in
            let title = "Relay integration \(UUID().uuidString.prefix(8))"

            let (created, createResponse) = try await site.relayed(
                "wp/v2/posts",
                method: "POST",
                body: ["title": title, "status": "draft"],
                on: server
            )
            #expect(createResponse.statusCode == 201)

            let post = try #require((try? JSONSerialization.jsonObject(with: created)) as? [String: Any])
            let id = try #require(post["id"] as? Int)

            // Read it back rather than trusting the create response: the defect
            // this covers sent an empty body, which WordPress accepts as a
            // no-op while still answering 2xx.
            let (fetched, _) = try await site.relayed("wp/v2/posts/\(id)?context=edit", on: server)
            let stored = try #require((try? JSONSerialization.jsonObject(with: fetched)) as? [String: Any])
            let storedTitle = (stored["title"] as? [String: Any])?["raw"] as? String
            #expect(storedTitle == title)

            _ = try await site.relayed(
                "wp/v2/posts/\(id)?force=true",
                method: "POST",
                headers: ["X-HTTP-Method-Override": "DELETE"],
                on: server
            )
        }
    }

    // MARK: - Refusals

    @Test("refuses a path that walks out of the API root, in a shape the editor can read")
    func refusesEscapingPath() async throws {
        try await withRelay { server, site in
            let (data, response) = try await site.relayed("../wp-admin/admin-ajax.php", on: server)

            #expect(response.statusCode == 403)
            #expect(response.value(forHTTPHeaderField: "Content-Type") == "application/json")
            // A `text/plain` body reaches JavaScript as an unparseable
            // `invalid_json` with the real reason lost.
            let error = try #require((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
            #expect(error["code"] as? String == "relay_forbidden_path")
            #expect(error["message"] is String)
        }
    }

    @Test("refuses a request without the relay token")
    func refusesUnauthenticated() async throws {
        try await withRelay { server, _ in
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/proxy/wp/v2/posts")!)
            request.setValue("file://", forHTTPHeaderField: "Origin")

            let (_, response) = try await URLSession.shared.data(for: request)
            #expect((response as? HTTPURLResponse)?.statusCode == 407)
        }
    }

    // MARK: - Helpers

    /// Runs `body` against a local server hosting a relay for the wp-env site,
    /// stopping it afterwards.
    private func withRelay(
        _ body: (MediaUploadServer, WPEnvSite) async throws -> Void
    ) async throws {
        let site = try #require(WPEnvSite.current)
        let server = try await MediaUploadServer.start(restRelay: RestRelay(configuration: site.configuration))
        defer { server.stop() }
        try await body(server, site)
    }
}

/// The local WordPress environment `make wp-env-start` provisions, as described
/// by the credentials file it writes.
struct WPEnvSite {
    let apiRoot: URL
    let authHeader: String

    /// The site described by `WP_ENV_CREDENTIALS_PATH`, or `nil` when the
    /// variable is unset or the file cannot be read.
    static let current: WPEnvSite? = {
        struct Credentials: Decodable {
            let siteApiRoot: String
            let authHeader: String
        }
        guard let path = ProcessInfo.processInfo.environment["WP_ENV_CREDENTIALS_PATH"],
              let data = FileManager.default.contents(atPath: path),
              let credentials = try? JSONDecoder().decode(Credentials.self, from: data),
              let apiRoot = URL(string: credentials.siteApiRoot) else {
            return nil
        }
        return WPEnvSite(apiRoot: apiRoot, authHeader: credentials.authHeader)
    }()

    /// A session that will actually open ten connections at once. The shared
    /// session caps concurrency per host at six, which would leave the
    /// connection-limit test unable to fail.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpMaximumConnectionsPerHost = 10
        return URLSession(configuration: configuration)
    }()

    var configuration: EditorConfiguration {
        EditorConfigurationBuilder(
            postType: .post,
            siteURL: apiRoot,
            siteApiRoot: apiRoot,
            authHeader: authHeader
        ).build()
    }

    /// Issues a request through the relay the way the editor's `fetch()` does:
    /// the upstream path below the route, the relay's own bearer token, and the
    /// headers WebKit sets on every cross-origin fetch.
    func relayed(
        _ path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        headers: [String: String] = [:],
        on server: MediaUploadServer
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/proxy/\(path)")!)
        request.httpMethod = method
        request.setValue("Bearer \(server.token)", forHTTPHeaderField: "Relay-Authorization")
        request.setValue("file://", forHTTPHeaderField: "Origin")
        request.setValue("application/json, */*;q=0.1", forHTTPHeaderField: "Accept")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

#endif // canImport(Network)
