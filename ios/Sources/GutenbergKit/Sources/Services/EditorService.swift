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

    private var progress: EditorProgress?
    private var progressCallback: EditorProgressCallback?

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
    ///     This policy applies to both API response caching and asset manifest caching.
    ///   - storageRoot: The directory for storing downloaded asset bundles. If `nil`, uses
    ///     a default location based on the site ID.
    ///   - cacheRoot: The directory for caching API responses. If `nil`, uses a default
    ///     location based on the site ID.
    public init(
        configuration: EditorConfiguration,
        httpClient: EditorHTTPClient? = nil,
        cachePolicy: EditorCachePolicy = .always,
        storageRoot: URL? = nil,
        cacheRoot: URL? = nil
    ) {
        self.configuration = configuration

        let httpClient = httpClient ?? EditorHTTPClient(
            urlSession: URLSession.shared,
            authHeader: configuration.authHeader,
            delegate: nil
        )

        self.restRepository = RESTAPIRepository(
            configuration: configuration,
            httpClient: httpClient,
            cache: EditorURLCache(
                cacheRoot: cacheRoot ?? Paths.cacheRoot(for: configuration),
                cachePolicy: cachePolicy
            ),
        )

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

        async let settings = try prepareEditorSettings()
        async let assetBundle = try self.prepareAssetBundle()
        async let preloadList = try preparePreloadList()

        // Automatically clean up old asset bundles
        try await onceEvery(.seconds(86_400)) {
            try await self.cleanup()
        }

        return try await EditorDependencies(
            editorSettings: settings,
            assetBundle: assetBundle,
            preloadList: preloadList
        )
    }

    /// Clear unused on-disk resources associated with this service's configuration.
    ///
    /// Calling this method will preserve the most recent cache entries, ensuring that the editor still loads quickly without continuing to use unnecessary disk space.
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

    private func incrementProgress(for weight: DependencyWeights, fraction: Double = 1.0) async {
        precondition(
            self.progress != nil,
            "Progress has not been initialized. This is a bug in the EditorService. Please file an issue."
        )
        let progress = EditorProgress(
            completed: self.progress!.completed + Int(weight.rawValue * fraction),
            total: self.progress!.total)
        self.progress = progress
        await self.progressCallback?(progress)
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
        if let latestAssetBundle = try await self.assetLibrary.readAssetBundles().first {
            await self.incrementProgress(for: .assetBundle)
            return latestAssetBundle
        }

        return try await self.assetLibrary.downloadAssetBundle { progress in
            await self.incrementProgress(for: .assetBundle, fraction: progress.fractionCompleted)
        }
    }

    private func preparePreloadList() async throws -> EditorPreloadList {
        async let activeTheme = try self.prepareActiveTheme()
        async let settingsOptions = try self.prepareSettingsOptions()
        async let postTypeData = try self.preparePost(type: configuration.postType)
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
