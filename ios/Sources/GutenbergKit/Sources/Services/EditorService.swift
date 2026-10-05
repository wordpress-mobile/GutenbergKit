import Foundation

/// Coordinates downloading and caching of editor dependencies from a WordPress site.
///
/// `EditorService` handles fetching and caching all resources needed to display the
/// Gutenberg block editor, including editor settings, plugin assets, and REST API data.
/// It reports progress during the preparation phase and provides cleanup methods for
/// managing disk space.
///
/// ## Usage
///
/// ```swift
/// let service = EditorService(configuration: config)
/// let dependencies = try await service.prepare { progress in
///     print("Loading: \(progress.fractionCompleted * 100)%")
/// }
/// ```
public actor EditorService {

    private let configuration: EditorConfiguration
    private let restRepository: RESTAPIRepository
    private let assetLibrary: EditorAssetLibrary

    /// `restRepository` under the `.always` policy, which reads whatever is on disk however old
    /// it is: what a dependency that can't be fetched falls back to.
    private let diskRepository: RESTAPIRepository

    private var progress: EditorProgress?
    private var progressCallback: EditorProgressCallback?

    /// How much of the asset bundle's weight has been counted toward `progress`.
    private var assetBundleProgress = 0

    enum DependencyWeights: CaseIterable {
        case editorSettings
        case assetBundle
        case post
        case postType
        case activeTheme
        case settingsOptions
        case postTypes

        var rawValue: Double {
            switch self {
            case .editorSettings: 10
            case .assetBundle: 50
            case .post: 10
            case .postType: 10
            case .activeTheme: 10
            case .settingsOptions: 10
            case .postTypes: 10
            }
        }
    }

    /// Creates an editor service for the given configuration.
    ///
    /// - Parameters:
    ///   - configuration: The editor configuration specifying site credentials and settings.
    ///   - httpClient: An optional HTTP client for making API requests. If `nil`, a default
    ///     client is created using the configuration's auth header.
    ///   - cachePolicy: The policy that determines when cached responses are considered valid.
    ///     Use `.ignore` to always fetch fresh data, `.maxAge(_:)` to expire entries after
    ///     a time interval, or `.always` (the default) to use cached data regardless of age.
    ///     This policy applies to both API responses and plugin and theme assets. For assets, it
    ///     decides when to check the site's asset manifest again; an unchanged manifest keeps the
    ///     bundle already on disk rather than downloading its assets again. `.ignore` is the
    ///     exception: it downloads every asset again whether or not the manifest has changed.
    public init(
        configuration: EditorConfiguration,
        httpClient: (any EditorHTTPClientProtocol)? = nil,
        cachePolicy: EditorCachePolicy = .always
    ) {
        self.init(
            configuration: configuration,
            httpClient: httpClient,
            cachePolicy: cachePolicy,
            storageRoot: nil,
            cacheRoot: nil
        )
    }

    /// Test-only init that exposes `storageRoot` and `cacheRoot` overrides for
    /// per-test directory isolation. Production callers have no reason to
    /// override these — the parent directories are always
    /// `Paths.defaultStorageRoot` / `Paths.defaultCacheRoot` and the per-site
    /// directory is appended internally — but tests need to redirect storage
    /// and cache to a temporary directory.
    ///
    /// - Parameters:
    ///   - storageRoot: The directory for storing downloaded asset bundles.
    ///     If `nil`, uses a default location based on the site ID.
    ///   - cacheRoot: The parent directory for caching API responses. The
    ///     configuration's `siteId` is appended internally so different sites
    ///     cannot collide. If `nil`, uses `Paths.defaultCacheRoot`.
    init(
        configuration: EditorConfiguration,
        httpClient: (any EditorHTTPClientProtocol)? = nil,
        cachePolicy: EditorCachePolicy = .always,
        storageRoot: URL?,
        cacheRoot: URL?
    ) {
        self.configuration = configuration

        let httpClient: any EditorHTTPClientProtocol = httpClient ?? EditorHTTPClient(
            urlSession: URLSession.shared,
            authHeader: configuration.authHeader,
            delegate: nil
        )

        let repository = { (cachePolicy: EditorCachePolicy) in
            RESTAPIRepository(
                configuration: configuration,
                httpClient: httpClient,
                cache: EditorURLCache(
                    siteId: configuration.siteId,
                    parentDirectory: cacheRoot ?? Paths.defaultCacheRoot,
                    cachePolicy: cachePolicy
                )
            )
        }

        self.restRepository = repository(cachePolicy)
        self.diskRepository = repository(.always)

        self.assetLibrary = EditorAssetLibrary(
            configuration: configuration,
            httpClient: httpClient,
            cachePolicy: cachePolicy,
            storageRoot: storageRoot ?? Paths.storageRoot(for: configuration)
        )
    }

    /// Returns the number of asset bundles currently stored on disk.
    public func fetchAssetBundleCount() async throws -> Int {
        try await self.assetLibrary.readAssetBundles().count
    }

    /// Downloads any missing editor dependencies, reporting progress along the way.
    ///
    /// This method fetches editor settings, plugin assets, and preload data concurrently,
    /// caching results for future use. If offline mode is enabled, returns empty dependencies.
    ///
    /// It gives the dependencies of ``prepareAvailable(progress:)`` without saying what went wrong
    /// getting them. With the configuration's network fallback disabled, a dependency that couldn't
    /// be fetched throws instead. With it automatic, nothing does: a dependency that couldn't be
    /// fetched comes from disk, however old, or is left out. Call ``prepareAvailable(progress:)``
    /// to have the dependencies and to know.
    ///
    /// An asset that fails to download doesn't count as a dependency that couldn't be fetched, and
    /// never stops an editor opening: the asset bundle is given without it, or with an earlier copy.
    ///
    /// - Parameter progress: A callback invoked with progress updates during loading.
    /// - Returns: The complete set of dependencies needed to initialize the editor.
    /// - Throws: An error if any required resource fails to download.
    @discardableResult
    public func prepare(progress: EditorProgressCallback? = nil) async throws -> EditorDependencies {
        let preparation = try await self.prepareAvailable(progress: progress)

        // Thrown once every dependency has been tried, rather than at the first to fail. By then
        // whatever could be fetched is stored, so trying again starts from there instead of from
        // nothing, and which error is thrown doesn't depend on which request finished first.
        if self.configuration.networkFallbackMode == .disabled {
            for case .notFetched(_, let error, _) in preparation.failures {
                throw error
            }
        }

        return preparation.dependencies
    }

    /// Prepares the best editor dependencies available, and says how they fall short of what the
    /// cache policy asked for.
    ///
    /// Each dependency is fetched as the policy asks: from disk if the policy trusts the copy
    /// there, and from the site otherwise. One that can't be fetched, for whatever reason, comes
    /// from disk however old its copy is, or is left out if there's none, and is listed in the
    /// result's `failures`. The post is never stored, so it's always left out.
    ///
    /// Nothing but cancellation throws, so there's always something to give an editor, and a
    /// failure never has to be traded for it. The configuration's network fallback mode has no
    /// effect here: it only decides what ``prepare(progress:)`` does with a failure.
    ///
    /// - Parameter progress: A callback invoked with progress updates during loading.
    /// - Throws: `CancellationError` if the task is cancelled.
    public func prepareAvailable(progress: EditorProgressCallback? = nil) async throws -> EditorPreparation {

        if self.configuration.isOfflineModeEnabled {
            return EditorPreparation(
                dependencies: EditorDependencies(editorSettings: .undefined, assetBundle: .empty, preloadList: nil),
                failures: []
            )
        }

        self.progress = EditorProgress(completed: 1, total: 100)
        self.progressCallback = progress
        self.assetBundleProgress = 0
        defer {
            self.progressCallback = nil
            self.progress = nil
        }

        async let editorSettings = self.resolveEditorSettings()
        async let assetBundle = self.resolveAssetBundle()
        async let post = self.resolvePost()
        async let postType = self.resolvePostType()
        async let postTypes = self.resolvePostTypes()
        async let activeTheme = self.resolveActiveTheme()
        async let settingsOptions = self.resolveSettingsOptions()

        // Automatically clean up old asset bundles, once a day for each site
        do {
            try await onceEvery(
                .seconds(86_400),
                { try await self.cleanup() },
                handle: "asset-bundle-cleanup-\(self.configuration.siteId)"
            )
        } catch {
            log(.warn, "Failed to clean up old asset bundles: \(error.localizedDescription)")
        }

        let resolvedAssetBundle = try await assetBundle
        let bundle = resolvedAssetBundle.value ?? .empty
        let postData = try await post?.value
        var failures = try await [
            editorSettings.failure,
            resolvedAssetBundle.failure,
            post?.failure,
            postType.failure,
            postTypes.failure,
            activeTheme.failure,
            settingsOptions.failure,
        ].compactMap { $0 }

        let missingAssets = await self.assetLibrary.missingAssets(of: bundle)
        if !missingAssets.isEmpty {
            failures.append(.assetsMissing(missingAssets))
        }

        // Only a bundle the site was asked for in this prepare: that's when these were asked for and
        // failed to download. A bundle from disk holds an earlier copy of them too, but nothing was
        // asked of the site for it, so nothing about them went wrong here.
        if resolvedAssetBundle.wasFetched {
            let assetsNotRefreshed = await self.assetLibrary.assetsNotRefreshed(in: bundle)
            if !assetsNotRefreshed.isEmpty {
                failures.append(.assetsNotRefreshed(assetsNotRefreshed))
            }
        }

        // The editor can't use a preload list without its post types, and asks for the rest itself
        var preloadList: EditorPreloadList?
        if let postTypeData = try await postType.value, let postTypesData = try await postTypes.value {
            preloadList = try await EditorPreloadList(
                postID: postData == nil ? nil : self.configuration.postID,
                postData: postData,
                postType: self.configuration.postType,
                postTypeData: postTypeData,
                postTypesData: postTypesData,
                activeThemeData: activeTheme.value,
                settingsOptionsData: settingsOptions.value
            )
        }

        return try await EditorPreparation(
            dependencies: EditorDependencies(
                editorSettings: editorSettings.value ?? .undefined,
                assetBundle: bundle,
                preloadList: preloadList
            ),
            failures: failures
        )
    }

    /// Clear unused on-disk resources associated with this service's configuration.
    ///
    /// Calling this method will preserve the most recent cache entries, ensuring that the editor still loads quickly without continuing to use unnecessary disk space.
    /// It also preserves any asset bundle the app has been handed since it launched, which an open editor or dependencies the host is holding may still be using.
    /// Use this method to regularly clean up unused editor assets.
    public func cleanup() async throws {
        try await self.assetLibrary.cleanup()
    }

    /// Clear all on-disk resources associated with this service's configuration, even ones that may be in-use.
    ///
    /// Use this method rarely, as it will require re-downloading assets before the editor is usable again.
    public func purge() async throws {
        try await self.assetLibrary.purge()
        try self.restRepository.purge()
    }

    private func incrementProgress(for weight: DependencyWeights) async {
        await self.incrementProgress(by: Int(weight.rawValue))
    }

    /// Counts an asset bundle download's progress toward the total. The download reports how far
    /// along it is each time, not how much further than the last time, so only what's new is added.
    private func incrementProgress(forAssetBundleDownload download: EditorProgress) async {
        let assetBundleProgress = Int(DependencyWeights.assetBundle.rawValue * download.fractionCompleted)
        let increase = assetBundleProgress - self.assetBundleProgress
        guard increase > 0 else { return }

        self.assetBundleProgress = assetBundleProgress
        await self.incrementProgress(by: increase)
    }

    private func incrementProgress(by amount: Int) async {
        // Progress can arrive after the `prepare()` it belongs to has returned and cleared it. A
        // bundle build shared with another service may already be calling in when this service
        // gives up on it, and an overlapping `prepare()` on this service is cleared by whichever
        // finishes first. There is nothing left to report to, so drop it.
        guard let current = self.progress else { return }

        // Progress starts at 1, and a post adds its weight to the others', so the weights can add
        // up to more than the total.
        let progress = EditorProgress(
            completed: min(current.completed + amount, current.total),
            total: current.total)
        self.progress = progress
        await self.progressCallback?(progress)
    }

    /// One dependency as a prepare ends up with it: its value, if there is one to give, and the
    /// failure to fetch it, if there was one.
    private struct Resolved<Value: Sendable>: Sendable {
        let value: Value?
        let failure: EditorPreparation.Failure?

        /// Whether `value` is what the site was asked for in this prepare, rather than a copy on disk.
        var wasFetched = false
    }

    /// Resolves one dependency. Every dependency comes through here, so each is fetched, falls
    /// back and reports its failure the same way.
    ///
    /// - Parameters:
    ///   - trusted: Reads the copy on disk, if the cache policy still trusts it.
    ///   - fetch: Fetches it from the site, which stores it.
    ///   - onDisk: Reads the copy on disk, however old.
    ///   - complete: Counts the dependency's weight toward progress, which it's owed either way.
    private func resolve<Value: Sendable>(
        _ dependency: EditorPreparation.Dependency,
        trusted: () async throws -> Value?,
        fetch: () async throws -> Value,
        onDisk: () async throws -> Value?,
        complete: () async -> Void
    ) async throws -> Resolved<Value> {
        do {
            // A copy that can't be read is no copy, and the site can still be asked
            let trustedValue: Value?
            do {
                trustedValue = try await trusted()
            } catch {
                log(.warn, "Failed to read \(dependency) from disk: \(error.localizedDescription)")
                trustedValue = nil
            }

            let value: Value
            if let trustedValue {
                value = trustedValue
            } else {
                value = try await fetch()
            }

            await complete()
            return Resolved(value: value, failure: nil, wasFetched: trustedValue == nil)
        } catch {
            // A prepare that's been cancelled has no one to report a failure to
            try Task.checkCancellation()

            // Nothing on disk can be checked against a site that can't be reached, and what's
            // there beats loading with nothing — however old it is.
            let copy = try? await onDisk()

            await complete()
            return Resolved(
                value: copy,
                failure: .notFetched(dependency, error: error, usingCopyOnDisk: copy != nil)
            )
        }
    }

    private func resolveEditorSettings() async throws -> Resolved<EditorSettings> {
        try await self.resolve(
            .editorSettings,
            trusted: { try self.restRepository.readEditorSettings() },
            fetch: { try await self.restRepository.fetchEditorSettings() },
            onDisk: { try self.diskRepository.readEditorSettings() },
            complete: { await self.incrementProgress(for: .editorSettings) }
        )
    }

    private func resolveAssetBundle() async throws -> Resolved<EditorAssetBundle> {
        // The bundle on disk, if the cache policy still trusts it, and whether it's missing assets. It's
        // read once, so that what the policy makes of it is settled before the site is asked anything,
        // and doesn't depend on how long the site takes to answer.
        let trusted: (bundle: EditorAssetBundle, isMissingAssets: Bool)?
        do {
            trusted = try await self.assetLibrary.readLatestAssetBundleWithinPolicy()
        } catch {
            log(.warn, "Failed to read the asset bundle from disk: \(error.localizedDescription)")
            trusted = nil
        }

        let resolved = try await self.resolve(
            .assetBundle,
            // One that's missing assets is still worth going to the site for, to try them again
            trusted: {
                guard let trusted, !trusted.isMissingAssets else {
                    return nil
                }

                return await self.assetLibrary.handOut(trusted.bundle)
            },
            fetch: {
                try await self.assetLibrary.downloadAssetBundle { progress in
                    await self.incrementProgress(forAssetBundleDownload: progress)
                }
            },
            onDisk: { try await self.assetLibrary.readLatestAssetBundleOnDisk() },
            // A download reports as it goes, but not to a caller that joins a build after its last
            // report, and not when it fails
            complete: { await self.incrementProgress(forAssetBundleDownload: EditorProgress(completed: 1, total: 1)) }
        )

        // If the site couldn't be asked, a bundle the policy trusts is still what the policy asked
        // for, so nothing went unfetched: its missing assets are reported as they stand, and why they
        // couldn't be tried again is logged.
        //
        // The bundle given is the latest on disk by now, which another service may have published
        // in the meantime, and otherwise the one that was trusted to begin with.
        if case .notFetched(_, let error, _)? = resolved.failure, let trusted, trusted.isMissingAssets {
            var bundle = resolved.value
            if bundle == nil {
                bundle = await self.assetLibrary.handOut(trusted.bundle)
            }

            if let bundle {
                log(.warn, "Failed to try the asset bundle's missing assets again: \(error.localizedDescription)")
                return Resolved(value: bundle, failure: nil)
            }
        }

        return resolved
    }

    /// `nil` when the configuration is for a post that doesn't exist yet.
    private func resolvePost() async throws -> Resolved<EditorURLResponse>? {
        guard let postID = self.configuration.postID, postID > 0 else {
            return nil
        }

        // The post is fetched every time, and has no copy on disk: a stored one can predate an
        // edit made since. The editor still has the title and content its host gives it.
        return try await self.resolve(
            .post,
            trusted: { try self.restRepository.readPost(id: postID) },
            fetch: { try await self.restRepository.fetchPost(id: postID) },
            onDisk: { nil },
            complete: { await self.incrementProgress(for: .post) }
        )
    }

    private func resolvePostType() async throws -> Resolved<EditorURLResponse> {
        let type = self.configuration.postType.postType

        return try await self.resolve(
            .postType,
            trusted: { try self.restRepository.readPostType(for: type) },
            fetch: { try await self.restRepository.fetchPostType(for: type) },
            onDisk: { try self.diskRepository.readPostType(for: type) },
            complete: { await self.incrementProgress(for: .postType) }
        )
    }

    private func resolvePostTypes() async throws -> Resolved<EditorURLResponse> {
        try await self.resolve(
            .postTypes,
            trusted: { try self.restRepository.readPostTypes() },
            fetch: { try await self.restRepository.fetchPostTypes() },
            onDisk: { try self.diskRepository.readPostTypes() },
            complete: { await self.incrementProgress(for: .postTypes) }
        )
    }

    private func resolveActiveTheme() async throws -> Resolved<EditorURLResponse> {
        try await self.resolve(
            .activeTheme,
            trusted: { try self.restRepository.readActiveTheme() },
            fetch: { try await self.restRepository.fetchActiveTheme() },
            onDisk: { try self.diskRepository.readActiveTheme() },
            complete: { await self.incrementProgress(for: .activeTheme) }
        )
    }

    private func resolveSettingsOptions() async throws -> Resolved<EditorURLResponse> {
        try await self.resolve(
            .settingsOptions,
            trusted: { try self.restRepository.readSettingsOptions() },
            fetch: { try await self.restRepository.fetchSettingsOptions() },
            onDisk: { try self.diskRepository.readSettingsOptions() },
            complete: { await self.incrementProgress(for: .settingsOptions) }
        )
    }
}
