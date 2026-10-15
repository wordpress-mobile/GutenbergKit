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

    /// Guards every change to a library's storage, along with `handedOut`. Every service builds
    /// its own library, so an actor's isolation doesn't order these between libraries.
    ///
    /// Storage changes in three ways and no others, each one step taken with this lock held:
    ///
    /// - ``publish(_:matchedAt:)`` moves a finished bundle in, already dated and handed out.
    /// - ``markLatest(_:matchedAt:)`` rewrites the manifest of a bundle it has found still there.
    /// - ``cleanup()`` and ``purge()`` remove whole bundles.
    ///
    /// So a bundle in storage is always complete and never gains or loses a file, and one that a
    /// build puts there is never without the protection that being handed out gives it. Assets are
    /// only ever written into a ``Draft``, in a temporary directory that none of this can see.
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
    ///     Use `.ignore` to check it every time, `.maxAge(_:)` to
    ///     check it once the last check is older than a time interval, or `.always` (the default)
    ///     to check it only when there is no bundle on disk.
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
            // Only asked when there's no bundle on disk, so an answer already on its way will do
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

        let manifest = try LocalEditorAssetManifest(remoteManifest: remoteManifest)

        // Said here, where a manifest is first seen, and nowhere else: what asks which links are
        // assets asks every time dependencies are prepared, and would say it every time.
        for url in self.linksLeftOut(of: manifest) {
            log(.warn, "Unexpected asset link: \(url)")
        }

        return manifest
    }

    // MARK: - Bundle Handling

    /// The downloaded asset bundles for a given `EditorConfiguration`, ordered by when the site's manifest last
    /// matched each: the latest first.
    ///
    public func readAssetBundles() throws -> [EditorAssetBundle] {
        try self.readAssetBundles { _ in true }
    }

    /// The bundles in the directories whose names `isIncluded` accepts, the latest first. Only those are
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
            // Not by when each was downloaded: a site can go back to a manifest it had before, whose bundle
            // was downloaded earlier than the one it replaced.
            .sorted { $0.lastMatchedDate > $1.lastMatchedDate }
    }

    /// The latest bundle on disk, if there's no reason to check the site's manifest again.
    ///
    /// Returns `nil` when there is no bundle, or when the site's manifest was last checked too long ago for the
    /// cache policy. In either case, call ``downloadAssetBundle(progress:)`` next to check.
    public func readLatestAssetBundle() throws -> EditorAssetBundle? {
        guard
            let latest = try self.readAssetBundles().first,
            self.cachePolicy.allowsResponseWith(date: latest.lastMatchedDate)
        else {
            return nil
        }

        return self.handOut(latest)
    }

    /// Records that `bundle` is being handed to a caller, so that `cleanup()` leaves it be. Returns `nil` if
    /// it's no longer on disk.
    func handOut(_ bundle: EditorAssetBundle) -> EditorAssetBundle? {
        Self.storageLock.withLock {
            guard self.hasBundle(at: bundle.bundleRoot) else { return nil }
            Self.handedOut.insert(bundle.bundleRoot.standardizedFileURL)
            return bundle
        }
    }

    /// Fetches the latest manifest from the server and downloads all of its resources, caching them on-disk.
    ///
    /// Only what the manifest says has changed is downloaded. If a bundle built
    /// from the same manifest is already on disk, it's returned instead, without downloading its assets again:
    /// they're versioned by URL, so an unchanged manifest means unchanged assets. If the manifest has changed,
    /// the new bundle takes each asset whose versioned URL (`?ver=`) a bundle on disk already has from that
    /// bundle, and downloads the rest.
    /// That trusts the site's versions: WordPress gives an asset registered without a version its own, so
    /// such a file can change while its URL doesn't. An asset without a version is downloaded again.
    ///
    /// The bundle is dated by when the manifest was fetched, however long it then takes to build:
    /// that's when the site was found to match it. It becomes the site's latest unless the site has been
    /// found to have another manifest since, and its age for the cache policy starts from then.
    ///
    /// - Parameter progress: An optional callback that receives progress updates as assets are downloaded.
    /// - Returns: The downloaded `EditorAssetBundle` containing all cached assets.
    /// - Throws: An error if the manifest cannot be fetched or assets fail to download.
    public func downloadAssetBundle(
        progress: EditorProgressCallback? = nil
    ) async throws -> EditorAssetBundle {
        let manifest = try await self.fetchManifest()
        return try await self.buildBundle(for: manifest, fetchedAt: Date(), progress: progress)
    }

    @available(*, deprecated, message: "`cachePolicy` has no effect: this always checks the site's manifest. Drop the argument.")
    public func downloadAssetBundle(
        cachePolicy: EditorCachePolicy,
        progress: EditorProgressCallback? = nil
    ) async throws -> EditorAssetBundle {
        try await self.downloadAssetBundle(progress: progress)
    }

    /// Checks whether a complete bundle with the given manifest checksum exists on disk.
    func hasBundle(forManifestChecksum checksum: String) -> Bool {
        self.existingBundle(forManifestChecksum: checksum) != nil
    }

    /// Checks whether there is a complete bundle at `bundleRoot`.
    ///
    /// A bundle is considered complete only if both `manifest.json` and `editor-representation.json` exist.
    private func hasBundle(at bundleRoot: URL) -> Bool {
        let manifestExists = FileManager.default.fileExists(atPath: bundleRoot.appending(path: "manifest.json").path)
        let editorRepExists = FileManager.default.fileExists(atPath: bundleRoot.appending(path: "editor-representation.json").path)
        return manifestExists && editorRepExists
    }

    /// Retrieves an existing bundle from disk if one exists for the given manifest checksum.
    ///
    /// A manifest can have more than one, if something was already in its directory when its bundle was put
    /// in place. This is the one the site's manifest last matched.
    func existingBundle(forManifestChecksum checksum: String) -> EditorAssetBundle? {
        // Every bundle is in a directory named for its manifest's checksum, alone or with more after it
        try? self.readAssetBundles { $0.hasPrefix(checksum) }.first { $0.id == checksum }
    }

    // MARK: - Individual Asset Handling

    /// Downloads all of the assets for a given manifest and assembles them into a bundle.
    ///
    /// Assets a bundle on disk already has are copied
    /// from it. The rest are downloaded concurrently, all into a temporary directory. Once all
    /// downloads complete successfully, the bundle is atomically moved into the library's storage. If
    /// a bundle for the manifest is already there, it's returned instead. Either way, the bundle returned is
    /// marked as matching the site's manifest at
    /// `manifestFetchDate`: when the manifest was fetched, which is when the site was found to have it.
    func buildBundle(
        for manifest: LocalEditorAssetManifest,
        fetchedAt manifestFetchDate: Date = Date(),
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
        let bundle = try await Self.inFlightBuilds.value(for: key, progress: progress) { report in
            try await self.reuseOrBuildBundle(for: manifest, fetchedAt: manifestFetchDate, reportingTo: report)
        }

        // The build dates the bundle by the fetch of the library that started it. One that joined it
        // fetched the manifest later, and so has found the site to match more recently than that.
        guard let lastCheckedDate = bundle.lastCheckedDate, lastCheckedDate < manifestFetchDate else {
            return bundle
        }

        return self.markLatest(bundle, matchedAt: manifestFetchDate) ?? bundle
    }

    /// Returns the bundle on disk for `manifest` if there is one, and otherwise builds one.
    ///
    /// The bundle on disk is looked for here, inside the build that callers share, so that a build
    /// finishing in between is reused.
    private func reuseOrBuildBundle(
        for manifest: LocalEditorAssetManifest,
        fetchedAt manifestFetchDate: Date,
        reportingTo progress: EditorProgressCallback
    ) async throws -> EditorAssetBundle {
        while true {
            if let existingBundle = self.existingBundle(forManifestChecksum: manifest.checksum) {
                await progress(EditorProgress(completed: 1, total: 1))

                // A `cleanup()` or `purge()` can delete the bundle after it's found here, in which
                // case there is nothing to reuse after all.
                if let latestBundle = self.markLatest(existingBundle, matchedAt: manifestFetchDate) {
                    return latestBundle
                }

                continue
            }

            let draft = try await self.build(manifest, reportingTo: progress)

            if let bundle = try self.publish(draft, matchedAt: manifestFetchDate) {
                return bundle
            }

            draft.discard()
        }
    }

    /// A bundle while it's being assembled, in a temporary directory that nothing else can see or delete.
    ///
    /// It's the only thing an asset is ever written into. A draft can't be made of a bundle in storage — the
    /// one way to make one starts a directory of its own — so nothing that downloads or copies an asset can
    /// reach a bundle an editor may be reading. Publishing a draft is the one way it becomes such a bundle.
    private struct Draft: Sendable {
        /// The bundle as it stands in the temporary directory.
        private(set) var bundle: EditorAssetBundle

        /// Starts a draft of the bundle for `manifest`, in a temporary directory of its own.
        init(manifest: LocalEditorAssetManifest) throws {
            self.bundle = try EditorAssetBundle(
                manifest: manifest,
                bundleRoot: URL.temporaryDirectory.appending(path: UUID().uuidString)
            )
        }

        /// Writes the draft's manifest again, for a draft about to be published: with when the site's
        /// manifest last matched it.
        mutating func record(lastCheckedDate: Date) throws {
            self.bundle = self.bundle.recording(lastCheckedDate: lastCheckedDate)
            try self.bundle.writeManifest()
        }

        /// Removes the draft's directory, for a draft that won't be published.
        func discard() {
            try? FileManager.default.removeItem(at: self.bundle.bundleRoot)
        }
    }

    /// Moves `draft` into the library's storage, as one the site's manifest matched at `matchDate` and one
    /// that's been handed out.
    ///
    /// It's all one step for anything else that changes storage: there is no moment when the bundle is there
    /// and a `cleanup()` could take it for one nobody is using. And it's a move, into a directory that didn't
    /// exist, so nothing sees the bundle half there and no bundle on disk is written over.
    ///
    /// Returns `nil`, with the draft left as it is, if another library has put a bundle for the manifest in
    /// storage since the build looked for one: that one is to be used instead.
    private func publish(_ draft: Draft, matchedAt matchDate: Date) throws -> EditorAssetBundle? {
        var draft = draft

        do {
            return try Self.storageLock.withLock {
                guard self.existingBundle(forManifestChecksum: draft.bundle.id) == nil else {
                    return nil
                }

                // Marked before it's moved, while nothing else can see it
                try draft.record(lastCheckedDate: matchDate)

                let bundle = try self.place(draft)
                Self.handedOut.insert(bundle.bundleRoot.standardizedFileURL)

                return bundle
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

    /// Downloads whichever of `draft`'s assets aren't in it yet: every asset that wasn't carried forward.
    private func downloadMissingAssets(
        of draft: Draft,
        reportingTo progress: EditorProgressCallback
    ) async throws {
        let missingAssets = self.missingAssets(of: draft.bundle)

        guard !missingAssets.isEmpty else {
            await progress(EditorProgress(completed: 1, total: 1))
            return
        }

        try await self.downloadAssets(missingAssets, into: draft, reportingTo: progress)
    }

    /// The assets `bundle` should have that aren't in it.
    private func missingAssets(of bundle: EditorAssetBundle) -> [URL] {
        self.downloadableAssets(in: bundle.manifest)
            .filter { !FileManager.default.fileExists(at: self.assetPath(for: $0, in: bundle)) }
    }

    /// Records that the site's manifest matched `bundle` at `matchDate`, and that the bundle has been handed
    /// out. That makes it the site's latest bundle, unless the site has been found to have another manifest
    /// since then, and starts its age for the cache policy from then.
    ///
    /// Returns `nil` if the bundle is no longer on disk, or is no longer its manifest's latest bundle there:
    /// another library has published one since, and marking this one would put it back in front.
    private func markLatest(_ bundle: EditorAssetBundle, matchedAt matchDate: Date) -> EditorAssetBundle? {
        Self.storageLock.withLock { () -> EditorAssetBundle? in
            // The manifest's latest bundle on disk, as it's recorded at this moment. If that isn't
            // `bundle`, it has been removed, or another library has published one since.
            guard
                let recorded = self.existingBundle(forManifestChecksum: bundle.id),
                recorded.bundleRoot == bundle.bundleRoot
            else {
                return nil
            }

            Self.handedOut.insert(bundle.bundleRoot.standardizedFileURL)

            // Another library may have found the manifest to match more recently than this one did,
            // and recorded it first
            let latestBundle = bundle.recording(lastCheckedDate: max(recorded.lastMatchedDate, matchDate))

            do {
                try self.rewriteManifest(of: latestBundle)
            } catch {
                // The bundle is still complete and correct, and what's known about it now is still
                // what the caller is given. It'll just be checked again sooner.
                log(.warn, "Failed to mark asset bundle \(bundle.id) as the latest: \(error.localizedDescription)")
            }

            return latestBundle
        }
    }

    /// Writes `bundle`'s manifest over the one in storage. Call it with `storageLock` held, for a bundle
    /// that's been found still there.
    ///
    /// It's written straight to the file: `EditorAssetBundle.writeManifest()` would create the bundle's
    /// directory if it weren't there.
    private func rewriteManifest(of bundle: EditorAssetBundle) throws {
        try bundle.dataRepresentation()
            .write(to: self.bundleManifestPath(relativeTo: bundle.bundleRoot), options: .atomic)
    }

    /// Assembles a bundle for `manifest` as a draft, for the caller to put in the library's storage with
    /// ``publish(_:matchedAt:)``. A build that fails discards the draft itself.
    private func build(
        _ manifest: LocalEditorAssetManifest,
        reportingTo progress: EditorProgressCallback
    ) async throws -> Draft {
        let draft = try Draft(manifest: manifest)

        do {
            let editorRepresentation = try manifest.buildEditorRepresentation(for: self.configuration)
            try draft.bundle.writeManifest(editorRepresentation: editorRepresentation)

            // Only a versioned URL is taken to mean the same file, and copied without asking. One
            // without a version can change without its URL saying so, so it's downloaded.
            let versioned = self.downloadableAssets(in: manifest).filter { self.isVersioned($0) }
            self.carryForward(versioned, from: self.assetSources(), into: draft)
            try await self.downloadMissingAssets(of: draft, reportingTo: progress)

            return draft
        } catch {
            draft.discard()
            throw error
        }
    }

    /// The bundles on disk that a build can take a copy of an asset from, the latest first.
    private func assetSources() -> [EditorAssetBundle] {
        (try? self.readAssetBundles()) ?? []
    }

    /// The latest of `sources` that has `asset` under the same URL. That isn't always the site's latest
    /// bundle: a site can go back to a manifest it had before, whose assets only that manifest's bundle has.
    ///
    /// The same URL: a bundle keeps an asset at its URL's path, which a URL on another host, or with
    /// another query, can share.
    private func source(of asset: URL, in sources: [EditorAssetBundle]) -> EditorAssetBundle? {
        sources.first {
            FileManager.default.fileExists(at: self.assetPath(for: asset, in: $0)) && $0.manifest.assetUrls.contains(asset)
        }
    }

    /// Copies into `draft` each of `assets` that one of `sources` has.
    private func carryForward(_ assets: [URL], from sources: [EditorAssetBundle], into draft: Draft) {
        for asset in assets {
            let destination = self.assetPath(for: asset, in: draft.bundle)

            // An asset the draft already has stays as it is
            guard
                !FileManager.default.fileExists(at: destination),
                let source = self.source(of: asset, in: sources)
            else {
                continue
            }

            do {
                try FileManager.default.copyItem(
                    at: self.assetPath(for: asset, in: source),
                    to: self.destination(for: asset, in: draft)
                )
            } catch {
                // The bundle has been removed since. Leave nothing behind, so that it reads as missing.
                try? FileManager.default.removeItem(at: destination)
            }
        }
    }

    /// Whether `url` carries a version the way WordPress adds one: a `ver` in its query.
    private func isVersioned(_ url: URL) -> Bool {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .contains { $0.name == "ver" && $0.value?.isEmpty == false } ?? false
    }

    /// The assets in `manifest` that belong in its bundle: the links its script and stylesheet tags load over
    /// HTTP, to files ending `.js`, `.css` or `.js.map`.
    private func downloadableAssets(in manifest: LocalEditorAssetManifest) -> [URL] {
        (manifest.scripts + manifest.styles).filter { self.isDownloadable($0) }
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

    /// The links in `manifest` that a bundle doesn't hold: the ones that aren't HTTP or HTTPS URLs to files
    /// ending `.js`, `.css` or `.js.map`.
    func linksLeftOut(of manifest: LocalEditorAssetManifest) -> [URL] {
        (manifest.scripts + manifest.styles).filter { !self.isDownloadable($0) }
    }

    /// Checks if the given `url` is one the library can download into a bundle. It says nothing about one
    /// that isn't: ``fetchManifest()`` does, once.
    ///
    /// Only HTTP/HTTPS URLs with `.js`, `.css`, or `.js.map` extensions are supported.
    private func isDownloadable(_ url: URL) -> Bool {
        guard url.scheme == "http" || url.scheme == "https" else {
            return false
        }

        let supportedResourceSuffixes = [".js", ".css", ".js.map"]
        return supportedResourceSuffixes.contains { url.lastPathComponent.hasSuffix($0) }
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
    /// This method removes all asset bundles except the latest one, freeing disk space
    /// while ensuring the editor can still load quickly with cached assets. It also keeps any
    /// bundle the app has been handed since it launched: an open editor, or dependencies the
    /// host is still holding, may be reading it. Those are removed by a cleanup after the next launch.
    ///
    /// - Throws: An error if the list of bundles cannot be read, or any bundle cannot be removed.
    public func cleanup() throws {
        try Self.storageLock.withLock {
            for bundle in try self.readAssetBundles().dropFirst()
            where !Self.handedOut.contains(bundle.bundleRoot.standardizedFileURL) {
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
