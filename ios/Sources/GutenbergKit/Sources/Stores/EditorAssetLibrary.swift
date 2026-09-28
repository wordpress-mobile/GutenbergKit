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

    /// Creates a new `EditorAssetLibrary` instance.
    ///
    /// - Parameters:
    ///   - configuration: The editor configuration containing site-specific settings.
    ///   - httpClient: The HTTP client used to fetch remote assets.
    ///   - cachePolicy: The policy that determines how long the newest bundle on disk is used
    ///     before the site's manifest is checked again. Use `.ignore` to check it every time,
    ///     `.maxAge(_:)` to check it once the bundle is older than a time interval, or `.always`
    ///     (the default) to check it only when there is no bundle on disk.
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
        let data = try await httpClient.perform(
            URLRequest(method: .GET, url: self.editorAssetsUrl(for: self.configuration))
        ).0
        let remoteManifest = try RemoteEditorAssetManifest(data: data)

        // The checksum covers the whole response, so a bundle with the same one was built from
        // this exact manifest.
        if let existingBundle = self.existingBundle(forManifestChecksum: remoteManifest.checksum) {
            return existingBundle.manifest
        }

        return try LocalEditorAssetManifest(remoteManifest: remoteManifest)
    }

    // MARK: - Bundle Handling

    /// The downloaded asset bundles for a given `EditorConfiguration`. Ordered newest to oldest.
    ///
    public func readAssetBundles() throws -> [EditorAssetBundle] {
        try FileManager.default.createDirectory(at: self.storageRoot, withIntermediateDirectories: true)
        return try FileManager.default
            .contentsOfDirectory(at: self.storageRoot, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { $0.hasDirectoryPath }  // Only include directories
            .filter { $0.pathExtension != "download" }  // Don't include bundles that are being downloaded
            .map { $0.appending(path: "manifest.json") }
            .compactMap { try? EditorAssetBundle(url: $0) }  // Skip invalid/incomplete bundles
            .sorted { $0.downloadDate > $1.downloadDate }
    }

    /// The newest bundle on disk, if the cache policy still trusts it.
    ///
    /// Returns `nil` when there is no bundle, or when the newest one is too old for the policy. Either way, call
    /// ``downloadAssetBundle(progress:)`` next to check the site's manifest.
    func readLatestAssetBundle() throws -> EditorAssetBundle? {
        guard
            let latestBundle = try self.readAssetBundles().first,
            self.cachePolicy.allowsResponseWith(date: latestBundle.downloadDate)
        else {
            return nil
        }

        return latestBundle
    }

    /// Fetches the latest manifest from the server and downloads all of its resources, caching them on-disk.
    ///
    /// If a bundle built from the same manifest is already on disk, it's returned instead, without downloading its
    /// assets again: they're versioned by URL, so an unchanged manifest means unchanged assets. The bundle then
    /// counts as newly downloaded, both for the cache policy and as the newest bundle on disk. To download every
    /// asset again regardless, ``purge()`` the library first.
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

    @available(*, deprecated, message: "`cachePolicy` has no effect; the library's own cache policy applies. Drop the argument.")
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
    /// bundle for the manifest is already there, it's marked current and returned instead.
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
            // reused, and so that marking a bundle current doesn't race a build in flight
            // replacing it.
            if let existingBundle = await self.existingBundle(forManifestChecksum: manifest.checksum) {
                await report(EditorProgress(completed: 1, total: 1))
                return await self.markCurrent(existingBundle)
            }

            return try await self.build(manifest, reportingTo: report)
        }
    }

    /// Records that the site's manifest still matches `bundle`, by resetting its download date to now. That makes
    /// it fresh again for the cache policy, and the newest bundle on disk — which matters when a site goes back to
    /// a manifest it had before, whose bundle is older than the one it replaced.
    private func markCurrent(_ bundle: EditorAssetBundle) -> EditorAssetBundle {
        do {
            let current = try EditorAssetBundle(manifest: bundle.manifest, bundleRoot: bundle.bundleRoot)
            try current.writeManifest()
            return current
        } catch {
            // The bundle is still complete and correct; it'll just be checked again sooner.
            log(.warn, "Failed to mark asset bundle \(bundle.id) current: \(error.localizedDescription)")
            return bundle
        }
    }

    private func build(
        _ manifest: LocalEditorAssetManifest,
        reportingTo progress: EditorProgressCallback
    ) async throws -> EditorAssetBundle {
        var complete = 0

        let tempDirectory = URL.temporaryDirectory.appending(path: UUID().uuidString)

        let bundle = try EditorAssetBundle(
            manifest: manifest,
            bundleRoot: tempDirectory
        )

        let editorRepresentation = try manifest.buildEditorRepresentation(for: self.configuration)
        try bundle.writeManifest(editorRepresentation: editorRepresentation)

        await withTaskGroup { group in
            let links = (manifest.scripts + manifest.styles).filter { self.isSupportedAsset($0) }

            for asset in links {
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
                await progress(EditorProgress(completed: complete, total: links.count))
            }
        }

        // The group swallows every per-asset failure, cancellation included, so a
        // cancelled build still arrives here with assets missing. Nothing downstream
        // checks for them — `readAssetBundles()` reads only the manifest — so publishing
        // it would serve the gap on every later launch.
        try Task.checkCancellation()

        return try bundle.copy(to: self.bundleRoot(for: bundle))
    }

    /// Downloads a single asset and copies it into the temporary bundle directory.
    ///
    @discardableResult
    private func fetchAsset(url: URL, into bundle: EditorAssetBundle) async throws -> URL {
        let tempUrl = try await logExecutionTime("Downloading \(url.lastPathComponent)") {
            try await httpClient.download(URLRequest(method: .GET, url: url)).0
        }

        let destinationPath = bundle.bundleRoot.appending(path: url.path(percentEncoded: false))
        let destinationParent = destinationPath.deletingLastPathComponent()

        // Ensure the destination directory exists
        try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)

        try FileManager.default.copyItem(at: tempUrl, to: destinationPath)

        return destinationPath
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
                .appending(path: "/wpcom/v2/\(namespace)editor-assets")
        } else {
            baseUrl = configuration.siteApiRoot
                .appending(path: "/wpcom/v2/editor-assets")
        }
        return baseUrl.appending(queryItems: [URLQueryItem(name: "exclude", value: "core,gutenberg")])
    }

    /// Cleans up outdated library entries for this site.
    ///
    /// This method removes all asset bundles except the most recent one, freeing disk space
    /// while ensuring the editor can still load quickly with cached assets.
    ///
    /// - Throws: An error if the list of bundles cannot be read, or any bundle cannot be removed.
    public func cleanup() throws {
        let bundles = try self.readAssetBundles().dropFirst()

        for bundle in bundles {
            try FileManager.default.removeItem(at: self.bundleRoot(for: bundle))
        }
    }

    /// Erases all library entries for this site.
    ///
    /// This method removes all asset bundles, requiring assets to be re-downloaded
    /// before the editor can be used again. Use sparingly.
    ///
    /// - Throws: An error if the storage directory cannot be removed or recreated.
    public func purge() throws {
        guard FileManager.default.directoryExists(at: self.storageRoot) else {
            return
        }

        try FileManager.default.removeItem(at: self.storageRoot)
        try FileManager.default.createDirectory(at: self.storageRoot, withIntermediateDirectories: true)
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
