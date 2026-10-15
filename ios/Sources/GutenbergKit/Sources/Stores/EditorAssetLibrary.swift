import Foundation

/// The Editor Asset Library is a site-specific repository of remote assets that can be downloaded to the local device to support plugins and theme styles.
///
public actor EditorAssetLibrary {

    private let configuration: EditorConfiguration
    private let httpClient: EditorHTTPClientProtocol
    private let storageRoot: URL
    private let cachePolicy: EditorCachePolicy

    /// Bundle builds in flight, keyed by the directory named for the manifest each builds. Every
    /// service builds its own library, so this is shared across all of them.
    static let inFlightBuilds = InFlightTasks<URL, EditorAssetBundle>()

    /// Guards every change to a library's storage. Every service builds
    /// its own library, so an actor's isolation doesn't order these between libraries.
    ///
    /// Storage changes in two ways and no others, each one step taken with this lock held:
    ///
    /// - ``publish(_:)`` moves a finished bundle in.
    /// - ``cleanup()`` and ``purge()`` remove whole bundles.
    ///
    /// So a bundle in storage is always complete and never gains or loses a file. Assets are
    /// only ever written into a ``Draft``, in a temporary directory that none of this can see.
    private static let storageLock = NSLock()

    /// Creates a new `EditorAssetLibrary` instance.
    ///
    /// - Parameters:
    ///   - configuration: The editor configuration containing site-specific settings.
    ///   - httpClient: The HTTP client used to fetch remote assets.
    ///   - cachePolicy: The policy that determines when cached asset manifests are considered valid.
    ///     Use `.ignore` to always fetch fresh manifests, `.maxAge(_:)` to expire entries after
    ///     a time interval, or `.always` (the default) to use cached manifests regardless of age.
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
    /// Applications should periodically check for a new editor manifest. This can be very expensive, so this method defaults to returning an existing one on-disk.
    ///
    func fetchManifest() async throws -> LocalEditorAssetManifest {
        guard configuration.shouldUsePlugins else { return .empty }
        let data = try await httpClient.perform(
            URLRequest(method: .GET, url: self.editorAssetsUrl(for: self.configuration))
        ).0
        let remoteManifest = try RemoteEditorAssetManifest(data: data)

        guard
            let existingManifest = self.existingBundle(forManifestChecksum: remoteManifest.checksum),
            self.cachePolicy.allowsResponseWith(date: existingManifest.downloadDate)
        else {
            return try LocalEditorAssetManifest(remoteManifest: remoteManifest)
        }

        return existingManifest.manifest
    }

    // MARK: - Bundle Handling

    /// The downloaded asset bundles for a given `EditorConfiguration`. Ordered newest to oldest.
    ///
    public func readAssetBundles() throws -> [EditorAssetBundle] {
        try self.readAssetBundles { _ in true }
    }

    /// The bundles in the directories whose names `isIncluded` accepts, newest first. Only those are
    /// read, and reading a bundle means decoding its manifest.
    private func readAssetBundles(inDirectoriesNamed isIncluded: (String) -> Bool) throws -> [EditorAssetBundle] {
        try FileManager.default.createDirectory(at: self.storageRoot, withIntermediateDirectories: true)
        return try FileManager.default
            .contentsOfDirectory(at: self.storageRoot, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { $0.hasDirectoryPath }  // Only include directories
            .filter { $0.pathExtension != "download" }  // Don't include bundles that are being downloaded
            .filter { isIncluded($0.lastPathComponent) }
            // Not the listed URL itself: a listing resolves symlinks in the path (`/var` to `/private/var`), which
            // would make a bundle read here unequal to the same bundle built or looked up by checksum.
            .map { self.bundleManifestPath(for: $0.lastPathComponent) }
            .compactMap { try? EditorAssetBundle(url: $0) }  // Skip invalid/incomplete bundles
            .sorted { $0.downloadDate > $1.downloadDate }
    }

    /// Fetches the latest manifest from the server and downloads all of its resources, caching them on-disk.
    ///
    /// - Parameter progress: An optional callback that receives progress updates as assets are downloaded.
    /// - Returns: The downloaded `EditorAssetBundle` containing all cached assets.
    /// - Throws: An error if the manifest cannot be fetched or assets fail to download.
    public func downloadAssetBundle(
        cachePolicy: EditorCachePolicy = .always,
        progress: EditorProgressCallback? = nil
    ) async throws -> EditorAssetBundle {
        let manifest = try await self.fetchManifest()
        return try await self.buildBundle(for: manifest, progress: progress)
    }

    /// Checks whether a complete bundle with the given manifest checksum exists on disk.
    ///
    /// A bundle is considered complete only if both `manifest.json` and `editor-representation.json` exist.
    func hasBundle(forManifestChecksum checksum: String) -> Bool {
        self.existingBundle(forManifestChecksum: checksum) != nil
    }

    /// Retrieves an existing bundle from disk if one exists for the given manifest checksum.
    ///
    /// A manifest can have more than one, if something was already in its directory when its bundle was put
    /// in place. This is the newest of them.
    func existingBundle(forManifestChecksum checksum: String) -> EditorAssetBundle? {
        // Every bundle is in a directory named for its manifest's checksum, alone or with more after it
        try? self.readAssetBundles { $0.hasPrefix(checksum) }.first { $0.id == checksum }
    }

    // MARK: - Individual Asset Handling

    /// Downloads all of the assets for a given manifest and assembles them into a bundle.
    ///
    /// Assets are downloaded concurrently, all into a temporary directory. Once all downloads complete
    /// successfully, the bundle is atomically moved into the library's storage — unless a bundle for the
    /// manifest is already there, which is returned instead.
    func buildBundle(
        for manifest: LocalEditorAssetManifest,
        progress: EditorProgressCallback? = nil
    ) async throws -> EditorAssetBundle {

        // Don't bother building a bundle from an empty manifest
        guard manifest != .empty else {
            await progress?(EditorProgress(completed: 100, total: 100))
            return .empty
        }

        // Every build of one manifest does the same work, whichever library runs it: join a build in
        // flight rather than download it all a second time.
        let key = self.bundleRoot(for: manifest.checksum).standardizedFileURL
        return try await Self.inFlightBuilds.value(for: key, progress: progress) { report in
            let draft = try await self.build(manifest, reportingTo: report)
            return try await self.publish(draft)
        }
    }

    /// A bundle while it's being assembled, in a temporary directory that nothing else can see or delete.
    ///
    /// It's the only thing an asset is ever written into. A draft can't be made of a bundle in storage — the
    /// one way to make one starts a directory of its own — so nothing that downloads an asset can
    /// reach a bundle an editor may be reading. Publishing a draft is the one way it becomes such a bundle.
    private struct Draft: Sendable {
        /// The bundle as it stands in the temporary directory.
        let bundle: EditorAssetBundle

        /// Starts a draft of the bundle for `manifest`, in a temporary directory of its own.
        init(manifest: LocalEditorAssetManifest) throws {
            self.bundle = try EditorAssetBundle(
                manifest: manifest,
                bundleRoot: URL.temporaryDirectory.appending(path: UUID().uuidString)
            )
        }

        /// Removes the draft's directory, for a draft that won't be published.
        func discard() {
            try? FileManager.default.removeItem(at: self.bundle.bundleRoot)
        }
    }

    /// Moves `draft` into the library's storage — unless a bundle for its manifest is there already, which is
    /// kept and given instead.
    ///
    /// It's all one step for anything else that changes storage. And it's a move, into a directory that didn't
    /// exist, so nothing sees the bundle half there and no bundle on disk is written over.
    private func publish(_ draft: Draft) throws -> EditorAssetBundle {
        do {
            return try Self.storageLock.withLock {
                // Another build of the manifest finished first. Its bundle is as good as this one, and an
                // editor may be reading it.
                if let existingBundle = self.existingBundle(forManifestChecksum: draft.bundle.id) {
                    draft.discard()
                    return existingBundle
                }

                return try self.place(draft)
            }
        } catch {
            draft.discard()
            throw error
        }
    }

    /// Moves `draft` into the library's storage as it stands. Call it with `storageLock` held.
    private func place(_ draft: Draft) throws -> EditorAssetBundle {
        try FileManager.default.createDirectory(at: self.storageRoot, withIntermediateDirectories: true)

        // The manifest's own directory, unless something is already there
        var destination = self.bundleRoot(for: draft.bundle.id)
        if FileManager.default.fileExists(atPath: destination.path) {
            destination = self.storageRoot.appending(path: "\(draft.bundle.id)-\(UUID().uuidString)")
        }

        try FileManager.default.moveItem(at: draft.bundle.bundleRoot, to: destination)

        return try EditorAssetBundle(url: self.bundleManifestPath(relativeTo: destination))
    }

    /// Assembles a bundle for `manifest` as a draft, for the caller to put in the library's storage with
    /// ``publish(_:)``. A build that fails discards the draft itself.
    private func build(
        _ manifest: LocalEditorAssetManifest,
        reportingTo progress: EditorProgressCallback
    ) async throws -> Draft {
        let draft = try Draft(manifest: manifest)

        do {
            let editorRepresentation = try manifest.buildEditorRepresentation(for: self.configuration)
            try draft.bundle.writeManifest(editorRepresentation: editorRepresentation)

            let assets = (manifest.scripts + manifest.styles).filter { self.isSupportedAsset($0) }
            try await self.downloadAssets(assets, into: draft, reportingTo: progress)

            return draft
        } catch {
            draft.discard()
            throw error
        }
    }

    /// Downloads `assets` into `draft` concurrently, tolerating any that fail.
    private func downloadAssets(
        _ assets: [URL],
        into draft: Draft,
        reportingTo progress: EditorProgressCallback
    ) async throws {
        var complete = 0

        await withTaskGroup { group in
            for asset in assets {
                group.addTask {
                    do {
                        try await self.fetchAsset(url: asset, into: draft)
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

    /// Downloads a single asset into `draft`.
    private func fetchAsset(url: URL, into draft: Draft) async throws {
        let tempUrl = try await logExecutionTime("Downloading \(url.lastPathComponent)") {
            try await httpClient.download(URLRequest(method: .GET, url: url)).0
        }

        // The download's file is this method's to deal with. It's moved into the draft below; when it
        // isn't, because something fails first, it's removed.
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        try FileManager.default.moveItem(at: tempUrl, to: try self.destination(for: url, in: draft))
    }

    /// Where the asset at `url` is stored in `bundle`: at its URL's path, under the bundle's root.
    private func assetPath(for url: URL, in bundle: EditorAssetBundle) -> URL {
        bundle.bundleRoot.appending(path: url.path(percentEncoded: false))
    }

    /// Where `draft` keeps the asset at `url`, in a directory that's there to write it into.
    private func destination(for url: URL, in draft: Draft) throws -> URL {
        let destination = self.assetPath(for: url, in: draft.bundle)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return destination
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
        try Self.storageLock.withLock {
            for bundle in try self.readAssetBundles().dropFirst() {
                try FileManager.default.removeItem(at: bundle.bundleRoot)
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
    /// Where `bundle` is on disk. Not derived from its checksum: a manifest can have more than one bundle.
    func bundleRoot(for bundle: EditorAssetBundle) -> URL {
        bundle.bundleRoot
    }

    /// Where a manifest's bundle goes, unless something is already there.
    func bundleRoot(for checksum: String) -> URL {
        self.storageRoot.appending(path: checksum)
    }

    func bundleManifestPath(for bundle: EditorAssetBundle) -> URL {
        bundleManifestPath(relativeTo: bundle.bundleRoot)
    }

    func bundleManifestPath(relativeTo path: URL) -> URL {
        path.appending(path: "manifest.json")
    }

    func bundleManifestPath(for checksum: String) -> URL {
        self.bundleManifestPath(relativeTo: self.bundleRoot(for: checksum))
    }
}
