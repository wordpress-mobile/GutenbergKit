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

    /// What `prepare()` falls back to when the site can't be reached and the network fallback is
    /// automatic: this service under the `.always` policy, which uses whatever is on disk however
    /// old it is. `nil` when the service wouldn't use it.
    private let diskFallback: EditorService?

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
    ///     bundle already on disk rather than downloading its assets again.
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

        self.restRepository = RESTAPIRepository(
            configuration: configuration,
            httpClient: httpClient,
            cache: EditorURLCache(
                siteId: configuration.siteId,
                parentDirectory: cacheRoot ?? Paths.defaultCacheRoot,
                cachePolicy: cachePolicy
            ),
        )

        self.assetLibrary = EditorAssetLibrary(
            configuration: configuration,
            httpClient: httpClient,
            cachePolicy: cachePolicy,
            storageRoot: storageRoot ?? Paths.storageRoot(for: configuration)
        )

        switch (configuration.networkFallbackMode, cachePolicy) {
        case (.automatic, .maxAge), (.automatic, .ignore):
            self.diskFallback = EditorService(
                configuration: configuration,
                httpClient: httpClient,
                cachePolicy: .always,
                storageRoot: storageRoot,
                cacheRoot: cacheRoot
            )
        case (.automatic, .always), (.disabled, _):
            self.diskFallback = nil
        }
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
    /// If the site can't be reached and the configuration's network fallback is automatic, this
    /// returns the dependencies on disk instead of throwing — even ones too old for the cache
    /// policy, which can't be checked without the site — and empty dependencies if any are missing.
    ///
    /// - Parameter progress: A callback invoked with progress updates during loading.
    /// - Returns: The complete set of dependencies needed to initialize the editor.
    /// - Throws: An error if any required resource fails to download.
    @discardableResult
    public func prepare(progress: EditorProgressCallback? = nil) async throws -> EditorDependencies {

        if self.configuration.isOfflineModeEnabled {
            return EditorDependencies(
                editorSettings: .undefined,
                assetBundle: .empty,
                preloadList: nil
            )
        }

        self.progress = EditorProgress(completed: 1, total: 100)
        self.progressCallback = progress
        self.assetBundleProgress = 0
        defer {
            self.progressCallback = nil
            self.progress = nil
        }

        if self.configuration.networkFallbackMode == .automatic {
            do {
                return try await fetchDependencies()
            } catch {
                guard isNetworkError(error) else { throw error }

                // Nothing on disk can be checked against a site that can't be reached, and what's
                // there beats loading with nothing — however old it is.
                if let diskFallback {
                    return try await diskFallback.prepare()
                }

                return EditorDependencies(
                    editorSettings: .undefined,
                    assetBundle: .empty,
                    preloadList: nil
                )
            }
        } else {
            return try await fetchDependencies()
        }
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

    private func fetchDependencies() async throws -> EditorDependencies {
        async let settings = try prepareEditorSettings()
        async let assetBundle = try self.prepareAssetBundle()
        async let preloadList = try preparePreloadList()

        // Automatically clean up old asset bundles, once a day for each site
        try await onceEvery(
            .seconds(86_400),
            { try await self.cleanup() },
            handle: "asset-bundle-cleanup-\(self.configuration.siteId)"
        )

        return try await EditorDependencies(
            editorSettings: settings,
            assetBundle: assetBundle,
            preloadList: preloadList
        )
    }

    private func isNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return [
            .notConnectedToInternet,
            .networkConnectionLost,
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed,
        ].contains(urlError.code)
    }

    private func prepareEditorSettings() async throws -> EditorSettings {
        if let settings = try restRepository.readEditorSettings() {
            await self.incrementProgress(for: .editorSettings)
            return settings
        }

        let settings = try await restRepository.fetchEditorSettings()
        await self.incrementProgress(for: .editorSettings)
        return settings
    }

    private func prepareAssetBundle() async throws -> EditorAssetBundle {
        if let latestAssetBundle = try await self.assetLibrary.readLatestAssetBundle() {
            await self.incrementProgress(for: .assetBundle)
            return latestAssetBundle
        }

        let assetBundle = try await self.assetLibrary.downloadAssetBundle { progress in
            await self.incrementProgress(forAssetBundleDownload: progress)
        }

        // A bundle with nothing to download reports no progress
        await self.incrementProgress(forAssetBundleDownload: EditorProgress(completed: 1, total: 1))
        return assetBundle
    }

    private func preparePreloadList() async throws -> EditorPreloadList {
        async let activeTheme = try self.prepareActiveTheme()
        async let settingsOptions = try self.prepareSettingsOptions()
        async let postTypeData = try self.preparePost(type: configuration.postType.postType)
        async let postTypesData = try self.preparePostTypes()

        if let postID = self.configuration.postID, postID > 0 {
            async let postData = try self.preparePost(id: postID)

            return try await EditorPreloadList(
                postID: postID,
                postData: postData,
                postType: self.configuration.postType,
                postTypeData: postTypeData,
                postTypesData: postTypesData,
                activeThemeData: activeTheme,
                settingsOptionsData: settingsOptions
            )
        } else {
            return try await EditorPreloadList(
                postType: self.configuration.postType,
                postTypeData: postTypeData,
                postTypesData: postTypesData,
                activeThemeData: activeTheme,
                settingsOptionsData: settingsOptions
            )
        }
    }

    private func preparePost(id: Int) async throws -> EditorURLResponse {
        if let postData = try self.restRepository.readPost(id: id) {
            await self.incrementProgress(for: .post)
            return postData
        }

        let postData = try await self.restRepository.fetchPost(id: id)
        await self.incrementProgress(for: .post)
        return postData
    }

    private func preparePost(type: String) async throws -> EditorURLResponse {
        if let postType = try self.restRepository.readPostType(for: type) {
            await self.incrementProgress(for: .postType)
            return postType
        }

        let response = try await self.restRepository.fetchPostType(for: type)
        await self.incrementProgress(for: .postType)
        return response
    }

    private func prepareActiveTheme() async throws -> EditorURLResponse {
        if let activeTheme = try self.restRepository.readActiveTheme() {
            await self.incrementProgress(for: .activeTheme)
            return activeTheme
        }

        let response = try await self.restRepository.fetchActiveTheme()
        await self.incrementProgress(for: .activeTheme)
        return response
    }

    private func prepareSettingsOptions() async throws -> EditorURLResponse {
        if let settingsOptions = try self.restRepository.readSettingsOptions() {
            await self.incrementProgress(for: .settingsOptions)
            return settingsOptions
        }

        let response = try await self.restRepository.fetchSettingsOptions()
        await self.incrementProgress(for: .settingsOptions)
        return response
    }

    private func preparePostTypes() async throws -> EditorURLResponse {
        if let postTypes = try self.restRepository.readPostTypes() {
            await self.incrementProgress(for: .postTypes)
            return postTypes
        }

        let response = try await self.restRepository.fetchPostTypes()
        await self.incrementProgress(for: .postTypes)
        return response
    }
}
