import Foundation
import Testing

@testable import GutenbergKit

/// The loader's contract with its owner: it reports back, and it never holds the owner —
/// the property that lets a released editor go while its fetch is still in flight.
@Suite("EditorDependencyLoader")
struct EditorDependencyLoaderTests: MakesTestFixtures {
    static let testSiteURL = URL(string: "https://example.com")!
    static let testApiRoot = URL(string: "https://example.com/wp-json")!

    @MainActor
    @Test("delivers the dependencies it fetched")
    func deliversTheDependencies() async throws {
        // Offline mode resolves without a request, so the fetch succeeds.
        let configuration = makeConfigurationBuilder().setIsOfflineModeEnabled(true).build()
        let owner = LoaderOwner(service: makeService(for: configuration))

        try await owner.waitUntilFinished()
        #expect(owner.dependencies != nil)
        #expect(owner.error == nil)
    }

    @MainActor
    @Test("delivers the error when the fetch fails")
    func deliversTheError() async throws {
        let session = ParkedURLSession()
        let owner = LoaderOwner(service: makeService(session: session))
        try await session.waitUntilStarted()

        session.release()  // fails every parked request
        try await owner.waitUntilFinished()
        #expect(owner.error != nil)
        #expect(owner.dependencies == nil)
    }

    @MainActor
    @Test("releasing its owner mid-fetch frees the owner, and leaves the fetch running")
    func releasingTheOwnerMidFetchFreesIt() async throws {
        let session = ParkedURLSession()
        defer { session.release() }
        var owner: LoaderOwner? = LoaderOwner(service: makeService(session: session))
        weak let releasedOwner = owner
        try await session.waitUntilStarted()

        owner = nil
        #expect(releasedOwner == nil, "the fetch should not hold its owner")

        let cancelled = await session.waitUntilCancelled(timeout: .milliseconds(250))
        #expect(!cancelled, "freeing the owner should not cancel the fetch")
    }

    /// A service whose every request lands in `session`, with storage no other test shares.
    private func makeService(session: ParkedURLSession) -> EditorService {
        let configuration = makeConfiguration()
        return EditorService(
            configuration: configuration,
            httpClient: EditorHTTPClient(urlSession: session, authHeader: configuration.authHeader),
            storageRoot: .randomTemporaryDirectory,
            cacheRoot: .randomTemporaryDirectory
        )
    }
}

/// Stands in for `EditorViewController`: owns its loader, and records what it is told.
@MainActor
private final class LoaderOwner: EditorDependencyLoaderDelegate {
    private var loader: EditorDependencyLoader?
    private(set) var dependencies: EditorDependencies?
    private(set) var error: (any Error)?

    init(service: EditorService) {
        loader = EditorDependencyLoader(service: service, delegate: self)
    }

    func dependencyLoader(_ loader: EditorDependencyLoader, didUpdate progress: EditorProgress) {}

    func dependencyLoader(_ loader: EditorDependencyLoader, didLoad dependencies: EditorDependencies) {
        self.dependencies = dependencies
    }

    func dependencyLoader(_ loader: EditorDependencyLoader, didFailWith error: any Error) {
        self.error = error
    }

    func waitUntilFinished() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)
        while dependencies == nil && error == nil && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(dependencies != nil || error != nil, "the loader never reported back")
    }
}
