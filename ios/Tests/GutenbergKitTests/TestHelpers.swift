import Foundation

@testable import GutenbergKit

func jsonResource(named name: String) throws -> Data {
    let url = Bundle.module.url(forResource: name, withExtension: "json")!
    return try Data(contentsOf: url)
}

func jsonResource(named name: String) throws -> String {
    String(data: try jsonResource(named: name), encoding: .utf8)!
}

protocol MakesTestFixtures {
    static var testSiteURL: URL { get }
    static var testApiRoot: URL { get }

    func makeConfiguration(
        postID: Int?, title: String?, content: String?, siteURL: URL, postType: PostTypeDetails,
        shouldUsePlugins: Bool, shouldUseThemeStyles: Bool, siteApiNamespace: [String]
    ) -> EditorConfiguration
    func makeConfigurationBuilder(postType: PostTypeDetails) -> EditorConfigurationBuilder
    func makeService(for configuration: EditorConfiguration?) -> EditorService
    func makeRepository(configuration: EditorConfiguration?, httpClient: EditorHTTPClientProtocol?)
    -> RESTAPIRepository
}

extension URL {
    static var randomTemporaryDirectory: URL {
        URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }
}

extension MakesTestFixtures {

    func makeConfiguration(
        postID: Int? = nil,
        title: String? = nil,
        content: String? = nil,
        siteURL: URL = Self.testSiteURL,
        postType: PostTypeDetails = .post,
        shouldUsePlugins: Bool = true,
        shouldUseThemeStyles: Bool = true,
        siteApiNamespace: [String] = []
    ) -> EditorConfiguration {
        var builder = EditorConfigurationBuilder(
            postType: postType,
            siteURL: siteURL,
            siteApiRoot: Self.testApiRoot,
            siteApiNamespace: siteApiNamespace,
            userCapabilities: UserCapabilities(uploadFiles: false)
        )
            .apply(title, { $0.setTitle($1) })
            .apply(content, { $0.setContent($1) })
            .setShouldUsePlugins(shouldUsePlugins)
            .setShouldUseThemeStyles(shouldUseThemeStyles)
            .setAuthHeader("Bearer test-token")

        if let postID {
            builder = builder.setPostID(postID)
        }

        return builder.build()
    }

    func makeConfigurationBuilder(postType: PostTypeDetails = .post) -> EditorConfigurationBuilder {
        EditorConfigurationBuilder(
            postType: postType,
            siteURL: Self.testSiteURL,
            siteApiRoot: Self.testApiRoot,
            userCapabilities: UserCapabilities(uploadFiles: false)
        )
    }

    func makeService(for configuration: EditorConfiguration? = nil) -> EditorService {
        EditorService(
            configuration: configuration ?? makeConfiguration(),
            storageRoot: .randomTemporaryDirectory,
            cacheRoot: .randomTemporaryDirectory
        )
    }

    func makeRepository(
        configuration: EditorConfiguration? = nil,
        httpClient: EditorHTTPClientProtocol? = nil
    ) -> RESTAPIRepository {
        let config = configuration ?? makeConfiguration()
        let client = httpClient ?? EditorAssetLibraryMockHTTPClient()
        let cache = EditorURLCache(cacheRoot: .randomTemporaryDirectory, cachePolicy: .always)

        return RESTAPIRepository(
            configuration: config,
            httpClient: client,
            cache: cache
        )
    }
}
