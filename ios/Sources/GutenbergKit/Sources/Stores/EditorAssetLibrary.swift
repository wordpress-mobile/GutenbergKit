import Foundation

/// The Editor Asset Library is a site-specific repository of remote assets that can be downloaded to the local device to support plugins and theme styles.
///
public actor EditorAssetLibrary {

    private let configuration: EditorConfiguration
    private let httpClient: EditorHTTPClientProtocol
    private let storageRoot: URL
    private let cachePolicy: EditorCachePolicy

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
    package func fetchManifest() async throws -> LocalEditorAssetManifest {
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
        try FileManager.default.createDirectory(at: self.storageRoot, withIntermediateDirectories: true)
        return try FileManager.default
            .contentsOfDirectory(at: self.storageRoot, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { $0.hasDirectoryPath }  // Only include directories
            .filter { $0.pathExtension != "download" }  // Don't include bundles that are being downloaded
            .map { $0.appending(path: "manifest.json") }
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
    package func hasBundle(forManifestChecksum checksum: String) -> Bool {
        let bundleRoot = self.bundleRoot(for: checksum)
        let manifestExists = FileManager.default.fileExists(atPath: bundleRoot.appending(path: "manifest.json").path)
        let editorRepExists = FileManager.default.fileExists(atPath: bundleRoot.appending(path: "editor-representation.json").path)
        return manifestExists && editorRepExists
    }

    /// Retrieves an existing bundle from disk if one exists for the given manifest checksum.
    ///
    package func existingBundle(forManifestChecksum checksum: String) -> EditorAssetBundle? {
        guard self.hasBundle(forManifestChecksum: checksum) else {
            return nil
        }

        return try? EditorAssetBundle(url: self.bundleManifestPath(for: checksum))
    }
    
    // MARK: - Individual Asset Handling
    
    /// Downloads all of the assets for a given manifest and assembles them into a bundle.
    ///
    /// Assets are downloaded concurrently and stored in a temporary directory. Once all downloads
    /// complete successfully, the bundle is atomically moved to its final location.
    package func buildBundle(
        for manifest: LocalEditorAssetManifest,
        progress: EditorProgressCallback? = nil
    ) async throws -> EditorAssetBundle {

        // Don't bother building a bundle from an empty manifest
        guard manifest != .empty else {
            await progress?(EditorProgress(completed: 100, total: 100))
            return .empty
        }

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
                await progress?(EditorProgress(completed: complete, total: links.count))
            }
        }

        return try bundle.copy(to: self.bundleRoot(for: bundle))
    }
    
    /// Downloads a single asset and copies it into the temporary bundle directory.
    ///
    private func fetchAsset(url: URL, into bundle: EditorAssetBundle) async throws {
        let tempUrl = try await logExecutionTime("Downloading \(url.lastPathComponent)") {
            try await httpClient.download(URLRequest(method: .GET, url: url)).0
        }

        let destinationPath = bundle.bundleRoot.appending(path: url.path(percentEncoded: false))
        let destinationParent = destinationPath.deletingLastPathComponent()

        // Ensure the destination directory exists
        try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)

        try FileManager.default.copyItem(at: tempUrl, to: destinationPath)
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
