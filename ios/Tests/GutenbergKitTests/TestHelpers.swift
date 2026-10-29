import Foundation
import Testing

@testable import GutenbergKit

/// How long a test waits for something that is supposed to happen before giving up.
///
/// Generous, because a wait that succeeds returns as soon as it can and only one that is going to
/// fail runs this long. A run's first results take half a minute to arrive on a busy CI machine,
/// which a shorter wait reads as a failure.
let patientTimeout: Duration = .seconds(60)

/// Polls `condition` until it holds, failing the test at the caller's line if it hasn't within
/// `timeout`. `condition` runs on the caller's actor.
func waitUntil(
    timeout: Duration = patientTimeout,
    isolation: isolated (any Actor)? = #isolation,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    try #require(condition(), "timed out waiting", sourceLocation: sourceLocation)
}

func jsonResource(named name: String) throws -> Data {
    let url = Bundle.module.url(forResource: name, withExtension: "json")!
    return try Data(contentsOf: url)
}

func jsonResource(named name: String) throws -> String {
    String(data: try jsonResource(named: name), encoding: .utf8)!
}

/// Puts a bundle for each of `manifests` in `storageRoot`, as an earlier launch would have left them.
/// Each bundle is complete, the last manifest's bundle is the latest, and none has been handed out by
/// this process, so `cleanup()` is free to remove all but the latest.
@discardableResult
func plantBundles(
    forManifests manifests: [String],
    in storageRoot: URL,
    configuration: EditorConfiguration = EditorAssetLibraryTests.testConfiguration
) async throws -> [EditorAssetBundle] {
    let scratchRoot = URL.randomTemporaryDirectory
    let client = EditorAssetLibraryMockHTTPClient()
    let library = EditorAssetLibrary(configuration: configuration, httpClient: client, storageRoot: scratchRoot)
    try FileManager.default.createDirectory(at: storageRoot, withIntermediateDirectories: true)

    var planted: [EditorAssetBundle] = []
    for manifest in manifests {
        client.urlResponseHandler = { url in
            url.path.contains("editor-assets") ? Data(manifest.utf8) : Data("mock content".utf8)
        }
        let bundle = try await library.downloadAssetBundle()
        let destination = storageRoot.appending(path: bundle.id)
        try FileManager.default.moveItem(at: scratchRoot.appending(path: bundle.id), to: destination)
        planted.append(try EditorAssetBundle(url: destination.appending(path: "manifest.json")))
    }
    return planted
}

extension Data {
    /// Whether this holds the same bytes as `other`, for an `#expect`.
    ///
    /// Not `==` in the `#expect` itself: Swift Testing describes a failed `==` between two
    /// collections by working out the difference between them. For megabytes of bytes that takes
    /// most of an hour on the thread the test runs on — and on the main actor, every other
    /// main-actor test in the run waits behind it.
    func hasSameBytes(as other: Data) -> Bool {
        self == other
    }
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
            siteApiNamespace: siteApiNamespace
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
            siteApiRoot: Self.testApiRoot
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
        let cache = EditorURLCache(siteId: "test", parentDirectory: .randomTemporaryDirectory, cachePolicy: .always)

        return RESTAPIRepository(
            configuration: config,
            httpClient: client,
            cache: cache
        )
    }
}
