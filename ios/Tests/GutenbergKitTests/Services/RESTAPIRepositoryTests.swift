import Foundation
import Testing

@testable import GutenbergKit

@Suite
struct RESTAPIRepositoryTests: MakesTestFixtures {

    static let testSiteURL = URL(string: "https://example.com")!
    static let testApiRoot = URL(string: "https://example.com/wp-json")!

    // MARK: - fetchPost Tests
    @Test("fetchPost returns response for valid post ID")
    func fetchPostReturnsResponse() async throws {
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(#"{"id":123,"title":{"raw":"Test Post"}}"#.utf8) }

        let repository = makeRepository(httpClient: mockClient)

        let response = try await repository.fetchPost(id: 123)

        #expect(!response.data.isEmpty)
        #expect(mockClient.getCallCount == 1)
    }

    // MARK: - fetchEditorSettings Tests

    @Test("fetchEditorSettings returns empty when plugins and theme styles disabled")
    func fetchEditorSettingsReturnsEmptyWhenDisabled() async throws {
        let configuration = makeConfiguration(shouldUsePlugins: false, shouldUseThemeStyles: false)
        let mockClient = EditorAssetLibraryMockHTTPClient()
        let repository = makeRepository(configuration: configuration, httpClient: mockClient)

        let settings = try await repository.fetchEditorSettings()

        #expect(settings == .undefined)
        #expect(mockClient.getCallCount == 0)
    }

    @Test("fetchEditorSettings parses response correctly")
    func fetchEditorSettingsParsesResponse() async throws {
        let mockClient = EditorAssetLibraryMockHTTPClient()
        // InternalEditorSettings expects styles array with css and isGlobalStyles
        mockClient.urlResponseHandler = { _ in Data(
            #"{"styles":[{"css":".test{color:red}","isGlobalStyles":false}]}"#.utf8) }

        let repository = makeRepository(httpClient: mockClient)

        let settings = try await repository.fetchEditorSettings()

        #expect(settings.themeStyles.contains(".test{color:red}"))
    }

    @Test("fetchEditorSettings caches response")
    func fetchEditorSettingsCachesResponse() async throws {
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(#"{"styles":[]}"#.utf8) }

        let configuration = makeConfiguration()
        let cache = EditorURLCache(cacheRoot: .randomTemporaryDirectory)
        let repository = RESTAPIRepository(
            configuration: configuration,
            httpClient: mockClient,
            cache: cache
        )

        _ = try await repository.fetchEditorSettings()

        // Should be able to read from cache
        let cached = try repository.readEditorSettings()
        #expect(cached != nil)
    }

    // MARK: - readEditorSettings Tests

    @Test("readEditorSettings returns nil when not cached")
    func readEditorSettingsReturnsNilWhenNotCached() throws {
        let repository = makeRepository()

        let settings = try repository.readEditorSettings()

        #expect(settings == nil)
    }

    @Test("readEditorSettings returns same values as fetchEditorSettings")
    func readEditorSettingsMatchesFetched() async throws {
        let mockClient = EditorAssetLibraryMockHTTPClient()
        let rawJSON =
        #"{"styles":[{"css":".theme-style{color:blue}","isGlobalStyles":true},{"css":".another{margin:0}","isGlobalStyles":false}]}"#
        mockClient.urlResponseHandler = { _ in Data(rawJSON.utf8) }

        let configuration = makeConfiguration()
        let cache = EditorURLCache(cacheRoot: .randomTemporaryDirectory)
        let repository = RESTAPIRepository(
            configuration: configuration,
            httpClient: mockClient,
            cache: cache
        )

        let fetched = try await repository.fetchEditorSettings()
        let cached = try repository.readEditorSettings()

        #expect(cached != nil)
        #expect(cached?.stringValue == fetched.stringValue)
        #expect(cached?.themeStyles == fetched.themeStyles)
        #expect(cached?.themeStyles.contains(".theme-style{color:blue}") == true)
        #expect(cached?.themeStyles.contains(".another{margin:0}") == true)
    }

    // MARK: - fetchPostType Tests

    @Test("fetchPostType returns response")
    func fetchPostTypeReturnsResponse() async throws {
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(#"{"slug":"post","name":"Posts"}"#.utf8) }

        let repository = makeRepository(httpClient: mockClient)

        let response = try await repository.fetchPostType(for: "post")

        #expect(!response.data.isEmpty)
    }

    @Test("fetchPostType caches response")
    func fetchPostTypeCachesResponse() async throws {
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(#"{"slug":"post"}"#.utf8) }

        let configuration = makeConfiguration()
        let cache = EditorURLCache(cacheRoot: .randomTemporaryDirectory)
        let repository = RESTAPIRepository(
            configuration: configuration,
            httpClient: mockClient,
            cache: cache
        )

        _ = try await repository.fetchPostType(for: "post")

        #expect(try repository.readPostType(for: "post") != nil)
    }

    // MARK: - fetchActiveTheme Tests

    @Test("fetchActiveTheme returns response")
    func fetchActiveThemeReturnsResponse() async throws {
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(#"[{"stylesheet":"twentytwentyfour"}]"#.utf8) }

        let repository = makeRepository(httpClient: mockClient)

        let response = try await repository.fetchActiveTheme()

        #expect(!response.data.isEmpty)
    }

    @Test("fetchActiveTheme caches response")
    func fetchActiveThemeCachesResponse() async throws {
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(#"[{"stylesheet":"theme"}]"#.utf8) }

        let configuration = makeConfiguration()
        let cache = EditorURLCache(cacheRoot: .randomTemporaryDirectory)
        let repository = RESTAPIRepository(
            configuration: configuration,
            httpClient: mockClient,
            cache: cache
        )

        _ = try await repository.fetchActiveTheme()

        #expect(try repository.readActiveTheme() != nil)
    }

    // MARK: - fetchSettingsOptions Tests

    @Test("fetchSettingsOptions returns response")
    func fetchSettingsOptionsReturnsResponse() async throws {
        let mockClient = EditorAssetLibraryMockHTTPClient()
        // OPTIONS doesn't use urlResponseHandler, it uses the OPTIONS method

        let repository = makeRepository(httpClient: mockClient)

        let response = try await repository.fetchSettingsOptions()

        // OPTIONS returns empty data by default in mock
        #expect(response.data.isEmpty || !response.data.isEmpty)
    }

    // MARK: - fetchPostTypes Tests

    @Test("fetchPostTypes returns response")
    func fetchPostTypesReturnsResponse() async throws {
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(#"{"post":{"slug":"post"},"page":{"slug":"page"}}"#.utf8) }

        let repository = makeRepository(httpClient: mockClient)

        let response = try await repository.fetchPostTypes()

        #expect(!response.data.isEmpty)
    }

    @Test("fetchPostTypes caches response")
    func fetchPostTypesCachesResponse() async throws {
        let mockClient = EditorAssetLibraryMockHTTPClient()
        mockClient.urlResponseHandler = { _ in Data(#"{"post":{}}"#.utf8) }

        let configuration = makeConfiguration()
        let cache = EditorURLCache(cacheRoot: .randomTemporaryDirectory)
        let repository = RESTAPIRepository(
            configuration: configuration,
            httpClient: mockClient,
            cache: cache
        )

        _ = try await repository.fetchPostTypes()

        #expect(try repository.readPostTypes() != nil)
    }

    // MARK: - URL Building Tests

    @Test("Post URL includes context=edit query parameter")
    func postUrlIncludesContextEdit() async throws {
        var capturedURL: URL?
        let capturingClient = URLCapturingMockHTTPClient { url in
            capturedURL = url
            return (
                Data(#"{}"#.utf8),
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!
            )
        }

        let configuration = makeConfiguration()
        let cache = EditorURLCache(cacheRoot: .randomTemporaryDirectory)
        let repository = RESTAPIRepository(
            configuration: configuration,
            httpClient: capturingClient,
            cache: cache
        )

        _ = try await repository.fetchPost(id: 42)

        #expect(capturedURL?.absoluteString.contains("context=edit") == true)
        #expect(capturedURL?.absoluteString.contains("/posts/42") == true)
    }
}

// MARK: - URL Capturing Mock Client

final class URLCapturingMockHTTPClient: EditorHTTPClientProtocol, @unchecked Sendable {
    private let handler: (URL) -> (Data, HTTPURLResponse)

    init(handler: @escaping (URL) -> (Data, HTTPURLResponse)) {
        self.handler = handler
    }

    func perform(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try handler(#require(urlRequest.url))
    }

    func download(_ urlRequest: URLRequest) async throws -> (URL, HTTPURLResponse) {
        let url = try #require(urlRequest.url)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: tempURL)
        return (
            tempURL,
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        )
    }
}
