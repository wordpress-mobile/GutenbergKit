import Foundation

/// The Editor Asset Library is a site-specific repository of remote assets that can be downloaded to the local device to support plugins and theme styles.
///
public actor EditorAssetLibrary {

    private let configuration: EditorConfiguration
    private let httpClient: EditorHTTPClientProtocol
    private let storageRoot: URL
    private let cachePolicy: EditorCachePolicy

    /// Bundle builds in flight, keyed by the directory each writes. Every service builds its own
    /// library, so this is shared across all of them.
    static let inFlightBuilds = InFlightTasks<URL, EditorAssetBundle>()

    /// Guards every change to which bundles are on disk and which of them is a site's latest —
    /// marking the latest, `cleanup()` and `purge()` — along with `handedOut`. Every service
    /// builds its own library, so an actor's isolation doesn't order these between libraries.
    private static let storageLock = NSLock()

    /// The directory of every bundle this process has handed to a caller. An editor, or
    /// dependencies a host is holding, may still be reading one, so `cleanup()` leaves them be.
    nonisolated(unsafe) private static var handedOut: Set<URL> = []

    /// Creates a new `EditorAssetLibrary` instance.
    ///
    /// - Parameters:
    ///   - configuration: The editor configuration containing site-specific settings.
    ///   - httpClient: The HTTP client used to fetch remote assets.
    ///   - cachePolicy: The policy that determines how long ``readLatestAssetBundle()`` goes on
    ///     returning the latest bundle on disk before the site's manifest has to be checked again.
    ///     Use `.ignore` to check it every time, `.maxAge(_:)` to check it once the last check is
    ///     older than a time interval, or `.always` (the default) to check it only when there is
    ///     no bundle on disk.
    ///   - storageRoot: The root directory where asset bundles will be stored on disk.
    public init(
        configuration: EditorConfiguration,
        httpClient: EditorHTTPClientProtocol,
        cachePolicy: EditorCachePolicy = .always,
        storageRoot: URL
    ) {
        self.configuration = configuration
        self.httpClient = httpClient
        self.storageRoot = storageRoot
        self.cachePolicy = cachePolicy
    }

    // MARK: - Manifest Handling

    /// Retrieve the manifest for a given site configuration.
    ///
    /// Parsing a manifest is expensive, so when a bundle built from the same manifest is already on disk, this
    /// method returns that bundle's copy rather than parsing it again.
    ///
    func fetchManifest() async throws -> LocalEditorAssetManifest {
        guard configuration.shouldUsePlugins else { return .empty }
        var request = URLRequest(method: .GET, url: self.editorAssetsUrl(for: self.configuration))
        switch self.cachePolicy {
        case .always:
            // Only asked when there's no bundle to use, so an answer already on its way will do
            break
        case .maxAge, .ignore:
            // A check is to find out what the site serves now, which neither a stored response
            // nor a request already in flight can say.
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }
        let data = try await httpClient.perform(request).0
        let remoteManifest = try RemoteEditorAssetManifest(data: data)

        // The checksum covers the whole response, so a bundle with the same one was built from
        // this exact manifest.
        if let existingBundle = self.existingBundle(forManifestChecksum: remoteManifest.checksum) {
            return existingBundle.manifest
        }

        return try LocalEditorAssetManifest(remoteManifest: remoteManifest)
    }

    // MARK: - Bundle Handling

    /// The downloaded asset bundles for a given `EditorConfiguration`, ordered by when the site's manifest last
    /// matched each: the latest first.
    ///
    public func readAssetBundles() throws -> [EditorAssetBundle] {
        try FileManager.default.createDirectory(at: self.storageRoot, withIntermediateDirectories: true)
        return try FileManager.default
            .contentsOfDirectory(at: self.storageRoot, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { $0.hasDirectoryPath }  // Only include directories
            .filter { $0.pathExtension != "download" }  // Don't include bundles that are being downloaded
            // Not the listed URL itself: a listing resolves symlinks in the path (`/var` to `/private/var`), which
            // would make a bundle read here unequal to the same bundle built or looked up by checksum.
            .map { self.bundleManifestPath(for: $0.lastPathComponent) }
            .compactMap { try? EditorAssetBundle(url: $0) }  // Skip invalid/incomplete bundles
            // Not by when each was downloaded: a site can go back to a manifest it had before, whose bundle
            // was downloaded earlier than the one it replaced.
            .sorted { $0.lastMatchedDate > $1.lastMatchedDate }
    }

    /// The latest bundle on disk, if the cache policy still trusts it.
    ///
    /// Returns `nil` when there is no bundle, or when the site's manifest was last checked too long ago for the
    /// policy. Either way, call ``downloadAssetBundle(progress:)`` next to check it.
    public func readLatestAssetBundle() throws -> EditorAssetBundle? {
        guard
            let latestBundle = try self.readAssetBundles().first,
            self.cachePolicy.allowsResponseWith(date: latestBundle.lastMatchedDate)
        else {
            return nil
        }

        return Self.storageLock.withLock {
            guard self.hasBundle(forManifestChecksum: latestBundle.id) else { return nil }
            Self.handedOut.insert(self.bundleRoot(for: latestBundle).standardizedFileURL)
            return latestBundle
        }
    }

    /// Fetches the latest manifest from the server and downloads all of its resources, caching them on-disk.
    ///
    /// If a bundle built from the same manifest is already on disk, it's returned instead, without downloading its
    /// assets again: they're versioned by URL, so an unchanged manifest means unchanged assets. Only an asset that
    /// an earlier build failed to download is tried again. Either way the bundle becomes the site's latest, and
    /// its age for the cache policy starts over. To download every asset again regardless, ``purge()`` the
    /// library first.
    ///
    /// - Parameter progress: An optional callback that receives progress updates as assets are downloaded.
    /// - Returns: The downloaded `EditorAssetBundle` containing all cached assets.
    /// - Throws: An error if the manifest cannot be fetched or assets fail to download.
    public func downloadAssetBundle(
        progress: EditorProgressCallback? = nil
    ) async throws -> EditorAssetBundle {
        let manifest = try await self.fetchManifest()
        return try await self.buildBundle(for: manifest, progress: progress)
    }

    @available(*, deprecated, message: "`cachePolicy` has no effect: this always checks the site's manifest. Drop the argument.")
    public func downloadAssetBundle(
        cachePolicy: EditorCachePolicy,
        progress: EditorProgressCallback? = nil
    ) async throws -> EditorAssetBundle {
        try await self.downloadAssetBundle(progress: progress)
    }

    /// Checks whether a complete bundle with the given manifest checksum exists on disk.
    ///
    /// A bundle is considered complete only if both `manifest.json` and `editor-representation.json` exist.
    func hasBundle(forManifestChecksum checksum: String) -> Bool {
        let bundleRoot = self.bundleRoot(for: checksum)
        let manifestExists = FileManager.default.fileExists(atPath: bundleRoot.appending(path: "manifest.json").path)
        let editorRepExists = FileManager.default.fileExists(atPath: bundleRoot.appending(path: "editor-representation.json").path)
        return manifestExists && editorRepExists
    }

    /// Retrieves an existing bundle from disk if one exists for the given manifest checksum.
    ///
    func existingBundle(forManifestChecksum checksum: String) -> EditorAssetBundle? {
        guard self.hasBundle(forManifestChecksum: checksum) else {
            return nil
        }

        return try? EditorAssetBundle(url: self.bundleManifestPath(for: checksum))
    }

    // MARK: - Individual Asset Handling

    /// Downloads all of the assets for a given manifest and assembles them into a bundle.
    ///
    /// Assets are downloaded concurrently and stored in a temporary directory. Once all downloads
    /// complete successfully, the bundle is atomically moved to its final location. If a complete
    /// bundle for the manifest is already there, it's returned instead, once any asset it's missing
    /// has been tried again. Either way, the bundle is marked as the site's latest.
    func buildBundle(
        for manifest: LocalEditorAssetManifest,
        progress: EditorProgressCallback? = nil
    ) async throws -> EditorAssetBundle {

        // Don't bother building a bundle from an empty manifest
        guard manifest != .empty else {
            await progress?(EditorProgress(completed: 100, total: 100))
            return .empty
        }

        // Every build of one manifest writes the same directory, whichever library runs it:
        // join a build in flight rather than race a second one into it.
        let destination = self.bundleRoot(for: manifest.checksum).standardizedFileURL
        return try await Self.inFlightBuilds.value(for: destination, progress: progress) { report in
            // Checked here rather than before joining, so that a build finishing in between is
            // reused, and so that reusing a bundle doesn't race a build in flight replacing it.
            if let existingBundle = await self.existingBundle(forManifestChecksum: manifest.checksum) {
                try await self.downloadMissingAssets(of: existingBundle, reportingTo: report)

                // A `cleanup()` or `purge()` can delete the bundle after it's found here, in which
                // case there is nothing to reuse after all.
                if let latestBundle = await self.markLatest(existingBundle) {
                    return latestBundle
                }
            }

            let bundle = try await self.build(manifest, reportingTo: report)
            return await self.markLatest(bundle) ?? bundle
        }
    }

    /// Downloads whichever of `bundle`'s assets aren't on disk. A build publishes its bundle without any asset
    /// that fails to download, and an unchanged manifest would otherwise never give that asset another try.
    private func downloadMissingAssets(
        of bundle: EditorAssetBundle,
        reportingTo progress: EditorProgressCallback
    ) async throws {
        let missingAssets = self.downloadableAssets(in: bundle.manifest)
            .filter { !FileManager.default.fileExists(at: self.assetPath(for: $0, in: bundle)) }

        guard !missingAssets.isEmpty else {
            await progress(EditorProgress(completed: 1, total: 1))
            return
        }

        try await self.downloadAssets(missingAssets, into: bundle, reportingTo: progress)
    }

    /// Records that the site's manifest matches `bundle` now, and that the bundle has been handed out. That makes
    /// it the site's latest bundle, and starts its age for the cache policy over. Returns `nil` if the bundle is
    /// no longer on disk.
    private func markLatest(_ bundle: EditorAssetBundle) -> EditorAssetBundle? {
        Self.storageLock.withLock {
            guard self.hasBundle(forManifestChecksum: bundle.id) else {
                return nil
            }

            Self.handedOut.insert(self.bundleRoot(for: bundle).standardizedFileURL)

            do {
                let latestBundle = try EditorAssetBundle(
                    manifest: bundle.manifest,
                    downloadDate: bundle.downloadDate,
                    lastCheckedDate: Date(),
                    bundleRoot: bundle.bundleRoot
                )
                // Written straight to the file, which is known to be there: `writeManifest()` would
                // create the bundle's directory if it weren't.
                try latestBundle.dataRepresentation().write(to: self.bundleManifestPath(for: bundle), options: .atomic)
                return latestBundle
            } catch {
                // The bundle is still complete and correct; it'll just be checked again sooner.
                log(.warn, "Failed to mark asset bundle \(bundle.id) as the latest: \(error.localizedDescription)")
                return bundle
            }
        }
    }

    private func build(
        _ manifest: LocalEditorAssetManifest,
        reportingTo progress: EditorProgressCallback
    ) async throws -> EditorAssetBundle {
        let tempDirectory = URL.temporaryDirectory.appending(path: UUID().uuidString)

        let bundle = try EditorAssetBundle(
            manifest: manifest,
            bundleRoot: tempDirectory
        )

        let editorRepresentation = try manifest.buildEditorRepresentation(for: self.configuration)
        try bundle.writeManifest(editorRepresentation: editorRepresentation)

        try await self.downloadAssets(self.downloadableAssets(in: manifest), into: bundle, reportingTo: progress)

        return try bundle.copy(to: self.bundleRoot(for: bundle))
    }

    /// The assets in `manifest` that belong in its bundle.
    private func downloadableAssets(in manifest: LocalEditorAssetManifest) -> [URL] {
        (manifest.scripts + manifest.styles).filter { self.isSupportedAsset($0) }
    }

    /// Downloads `assets` into `bundle` concurrently, tolerating any that fail.
    private func downloadAssets(
        _ assets: [URL],
        into bundle: EditorAssetBundle,
        reportingTo progress: EditorProgressCallback
    ) async throws {
        var complete = 0

        await withTaskGroup { group in
            for asset in assets {
                group.addTask {
                    do {
                        try await self.fetchAsset(url: asset, into: bundle)
                    } catch {
                        // Log and continue - individual asset failures shouldn't block the editor
                        // This handles cases like content blockers blocking analytics scripts
                        log(.warn, "Failed to download asset \(asset.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            }

            for await _ in group {
                complete += 1
                await progress(EditorProgress(completed: complete, total: assets.count))
            }
        }

        // The group swallows every per-asset failure, cancellation included, so a
        // cancelled download still arrives here with assets missing. Nothing downstream
        // checks for them — `readAssetBundles()` reads only the manifest — so publishing
        // the bundle, or recording it as the latest, would serve the gap on every later
        // launch.
        try Task.checkCancellation()
    }

    /// Downloads a single asset and copies it into the temporary bundle directory.
    ///
    @discardableResult
    private func fetchAsset(url: URL, into bundle: EditorAssetBundle) async throws -> URL {
        let tempUrl = try await logExecutionTime("Downloading \(url.lastPathComponent)") {
            try await httpClient.download(URLRequest(method: .GET, url: url)).0
        }

        let destinationPath = self.assetPath(for: url, in: bundle)
        let destinationParent = destinationPath.deletingLastPathComponent()

        // Ensure the destination directory exists
        try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)

        try FileManager.default.copyItem(at: tempUrl, to: destinationPath)

        return destinationPath
    }

    /// Where the asset at `url` is stored in `bundle`.
    private func assetPath(for url: URL, in bundle: EditorAssetBundle) -> URL {
        bundle.bundleRoot.appending(path: url.path(percentEncoded: false))
    }

    /// Checks if the given `url` is eligible to be downloaded into the local bundle
    ///
    /// Only HTTP/HTTPS URLs with `.js`, `.css`, or `.js.map` extensions are supported.
    private func isSupportedAsset(_ url: URL) -> Bool {
        guard url.scheme == "http" || url.scheme == "https" else {
            log(.warn, "Unexpected asset link: \(url)")
            return false
        }

        let supportedResourceSuffixes = [".js", ".css", ".js.map"]
        guard supportedResourceSuffixes.contains(where: { url.lastPathComponent.hasSuffix($0) }) else {
            log(.warn, "Unsupported asset URL: \(url)")
            return false
        }

        return true
    }

    // MARK: - Helpers
    private func editorAssetsUrl(for configuration: EditorConfiguration) -> URL {
        let baseUrl: URL
        if let customEndpoint = configuration.editorAssetsEndpoint {
            baseUrl = customEndpoint
        } else if let namespace = configuration.siteApiNamespace.first {
            // Insert namespace: /wpcom/v2/editor-assets -> /wpcom/v2/sites/123/editor-assets
            baseUrl = configuration.siteApiRoot
                .appending(rawPath: "/wpcom/v2/\(namespace)editor-assets")
        } else {
            baseUrl = configuration.siteApiRoot
                .appending(rawPath: "/wpcom/v2/editor-assets")
        }
        return baseUrl.appending(queryItems: [URLQueryItem(name: "exclude", value: "core,gutenberg")])
    }

    /// Cleans up outdated library entries for this site.
    ///
    /// This method removes all asset bundles except the latest one, freeing disk space
    /// while ensuring the editor can still load quickly with cached assets. It also keeps any
    /// bundle the app has been handed since it launched: an open editor, or dependencies the
    /// host is still holding, may be reading it. Those are removed by a cleanup after the next launch.
    ///
    /// - Throws: An error if the list of bundles cannot be read, or any bundle cannot be removed.
    public func cleanup() throws {
        try Self.storageLock.withLock {
            for bundle in try self.readAssetBundles().dropFirst() {
                let bundleRoot = self.bundleRoot(for: bundle)

                if !Self.handedOut.contains(bundleRoot.standardizedFileURL) {
                    try FileManager.default.removeItem(at: bundleRoot)
                }
            }
        }
    }

    /// Erases all library entries for this site.
    ///
    /// This method removes all asset bundles, requiring assets to be re-downloaded
    /// before the editor can be used again. Use sparingly.
    ///
    /// - Throws: An error if the storage directory cannot be removed or recreated.
    public func purge() throws {
        try Self.storageLock.withLock {
            guard FileManager.default.directoryExists(at: self.storageRoot) else {
                return
            }

            try FileManager.default.removeItem(at: self.storageRoot)
            try FileManager.default.createDirectory(at: self.storageRoot, withIntermediateDirectories: true)
        }
    }

    // MARK: - File Path Helpers
    func bundleRoot(for bundle: EditorAssetBundle) -> URL {
        assert(!bundle.id.isEmpty, "Bundle must have a valid ID")
        return self.bundleRoot(for: bundle.id)
    }

    func bundleRoot(for checksum: String) -> URL {
        self.storageRoot.appending(path: checksum)
    }

    func bundleManifestPath(for bundle: EditorAssetBundle) -> URL {
        bundleManifestPath(relativeTo: self.bundleRoot(for: bundle))
    }

    func bundleManifestPath(relativeTo path: URL) -> URL {
        path.appending(path: "manifest.json")
    }

    func bundleManifestPath(for checksum: String) -> URL {
        self.bundleManifestPath(relativeTo: self.bundleRoot(for: checksum))
    }
}
