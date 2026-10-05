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
    /// - ``publish(_:)`` moves a finished bundle in, already marked as the latest and handed out.
    /// - ``markLatest(_:)`` rewrites the manifest of a bundle it has found still there.
    /// - ``cleanup()`` and ``purge()`` remove whole bundles.
    ///
    /// So a bundle in storage is always complete, never gains or loses a file, and is never
    /// there without the protection that being handed out gives it. Assets are only ever
    /// written into a ``Draft``, in a temporary directory that none of this can see.
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
    ///     Use `.ignore` to check it every time and download every asset again, `.maxAge(_:)` to
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

    /// The latest bundle on disk, if there's no reason to check the site's manifest again.
    ///
    /// Returns `nil` when there is no bundle, when the site's manifest was last checked too long ago for the
    /// cache policy, or when the bundle is missing assets, which another try may download. In each case, call
    /// ``downloadAssetBundle(progress:)`` next to check.
    public func readLatestAssetBundle() throws -> EditorAssetBundle? {
        guard
            let latestBundle = try self.readAssetBundles().first,
            self.cachePolicy.allowsResponseWith(date: latestBundle.lastMatchedDate),
            self.missingAssets(of: latestBundle).isEmpty
        else {
            return nil
        }

        return self.handOut(latestBundle)
    }

    /// The latest bundle on disk, however long ago the site's manifest was checked and whether or not it has
    /// every asset: what there is to use when the site can't be asked.
    func readLatestAssetBundleOnDisk() throws -> EditorAssetBundle? {
        try self.readAssetBundles().first.flatMap { self.handOut($0) }
    }

    /// Records that `bundle` is being handed to a caller, so that `cleanup()` leaves it be. Returns `nil` if
    /// it's no longer on disk.
    private func handOut(_ bundle: EditorAssetBundle) -> EditorAssetBundle? {
        Self.storageLock.withLock {
            guard self.hasBundle(at: bundle.bundleRoot) else { return nil }
            Self.handedOut.insert(bundle.bundleRoot.standardizedFileURL)
            return bundle
        }
    }

    /// Fetches the latest manifest from the server and downloads all of its resources, caching them on-disk.
    ///
    /// Under `.always` and `.maxAge`, only what the manifest says has changed is downloaded. If a bundle built
    /// from the same manifest is already on disk, it's returned instead, without downloading its assets again:
    /// they're versioned by URL, so an unchanged manifest means unchanged assets. Only an asset that an earlier
    /// build failed to download is tried again, in a new bundle beside that one. If the manifest has changed, the new bundle takes each asset
    /// whose versioned URL (`?ver=`) a bundle on disk already has from that bundle, and downloads the rest.
    /// That trusts the site's versions: WordPress gives an asset registered without a version its own, so
    /// such a file can change while its URL doesn't, and only `.ignore` downloads it again. An asset without
    /// a version is asked for again, but only for a newer copy if its server sent an `ETag` or `Last-Modified`
    /// with the one on disk. An asset that fails to download is taken from the latest bundle on disk that has it.
    ///
    /// Under `.ignore`, every asset is downloaded whether or not the manifest has changed, into a new bundle: a
    /// bundle already on disk is never changed, because an editor may be reading it. An asset that fails to
    /// download is taken from the latest bundle on disk that has it. If the manifest hasn't changed and its
    /// assets all come back the same as the bundle on disk has them, that bundle is returned instead.
    ///
    /// Either way the bundle becomes the site's latest, and its age for the cache policy starts over.
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
    /// A manifest can have more than one: each download under `.ignore` that changes a manifest's assets leaves
    /// a bundle of its own. This is the one the site's manifest last matched.
    func existingBundle(forManifestChecksum checksum: String) -> EditorAssetBundle? {
        try? self.readAssetBundles().first { $0.id == checksum }
    }

    // MARK: - Individual Asset Handling

    /// Downloads all of the assets for a given manifest and assembles them into a bundle.
    ///
    /// Unless the cache policy is `.ignore`, assets a bundle on disk already has are copied
    /// from it. The rest are downloaded concurrently, all into a temporary directory. Once all
    /// downloads complete successfully, the bundle is atomically moved into the library's storage. If
    /// a bundle for the manifest is already there with every asset, it's returned instead. If one is
    /// there with assets missing, they're tried again in a new bundle beside it, which is only kept
    /// if it gains any. Under `.ignore`, the bundle is built again regardless. Either way, the bundle
    /// returned is marked as the site's latest.
    func buildBundle(
        for manifest: LocalEditorAssetManifest,
        progress: EditorProgressCallback? = nil
    ) async throws -> EditorAssetBundle {

        // Don't bother building a bundle from an empty manifest
        guard manifest != .empty else {
            await progress?(EditorProgress(completed: 100, total: 100))
            return .empty
        }

        if case .ignore = self.cachePolicy {
            return try await self.buildFreshBundle(for: manifest) { await progress?($0) }
        }

        // Every build of one manifest does the same work, whichever library runs it: join a
        // build in flight rather than download it all a second time.
        let key = self.bundleRoot(for: manifest.checksum).standardizedFileURL
        return try await Self.inFlightBuilds.value(for: key, progress: progress) { report in
            try await self.reuseOrBuildBundle(for: manifest, reportingTo: report)
        }
    }

    /// Returns the bundle on disk for `manifest` if it has every asset, and otherwise builds one.
    ///
    /// The bundle on disk is looked for here, inside the build that callers share, so that a build
    /// finishing in between is reused.
    private func reuseOrBuildBundle(
        for manifest: LocalEditorAssetManifest,
        reportingTo progress: EditorProgressCallback
    ) async throws -> EditorAssetBundle {
        let existingBundle = self.existingBundle(forManifestChecksum: manifest.checksum)

        if let existingBundle, self.missingAssets(of: existingBundle).isEmpty {
            await progress(EditorProgress(completed: 1, total: 1))

            // A `cleanup()` or `purge()` can delete the bundle after it's found here, in which
            // case there is nothing to reuse after all.
            if let latestBundle = self.markLatest(existingBundle) {
                return latestBundle
            }
        }

        // A bundle on disk that's missing assets is left as it is: an editor may be reading it.
        // The build takes what that bundle has and tries the rest again.
        let draft = try await self.build(manifest, reportingTo: progress)

        // Another try that gained nothing isn't worth a second bundle on disk
        if let existingBundle,
            self.missingAssets(of: draft.bundle) == self.missingAssets(of: existingBundle),
            let latestBundle = self.markLatest(existingBundle) {
            draft.discard()
            return latestBundle
        }

        return try self.publish(draft)
    }

    /// Builds a bundle for `manifest` with every asset downloaded now, which is what `.ignore` asks for.
    ///
    /// The bundle goes beside the one the manifest already has rather than over it: a bundle on disk is never
    /// changed, because an editor may be reading it. It has no build to join, because a build under another
    /// policy doesn't download everything. If the assets all come back the same as the manifest's bundle on
    /// disk has them, that bundle is still right, so it's returned instead and the new one is discarded. That
    /// keeps a refresh that changed nothing from costing disk space, or looking like a change to a host
    /// comparing dependencies.
    private func buildFreshBundle(
        for manifest: LocalEditorAssetManifest,
        reportingTo progress: EditorProgressCallback
    ) async throws -> EditorAssetBundle {
        let draft = try await self.build(manifest, reportingTo: progress)

        if let existingBundle = self.existingBundle(forManifestChecksum: manifest.checksum),
            self.hasSameAssets(draft.bundle, as: existingBundle),
            let latestBundle = self.markLatest(existingBundle) {
            draft.discard()
            return latestBundle
        }

        return try self.publish(draft)
    }

    /// A bundle while it's being assembled, in a temporary directory that nothing else can see or delete.
    ///
    /// It's the only thing an asset is ever written into. A draft can't be made of a bundle in storage — the
    /// one way to make one starts a directory of its own — so nothing that downloads or copies an asset can
    /// reach a bundle an editor may be reading. ``publish(_:)`` is the one way a draft becomes such a bundle.
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

        /// Writes the draft's manifest again, with what's been learned since it was started: its assets'
        /// headers, and, for a draft about to be published, when the site's manifest last matched it.
        mutating func record(
            assetHeaders: [String: EditorAssetBundle.AssetHeaders],
            lastCheckedDate: Date? = nil
        ) throws {
            self.bundle = try EditorAssetBundle(
                manifest: self.bundle.manifest,
                downloadDate: self.bundle.downloadDate,
                lastCheckedDate: lastCheckedDate,
                assetHeaders: assetHeaders,
                bundleRoot: self.bundle.bundleRoot
            )
            try self.bundle.writeManifest()
        }

        /// Removes the draft's directory, for a draft that won't be published.
        func discard() {
            try? FileManager.default.removeItem(at: self.bundle.bundleRoot)
        }
    }

    /// Moves `draft` into the library's storage, as the site's latest bundle and one that's been handed out.
    ///
    /// It's all one step for anything else that changes storage: there is no moment when the bundle is there
    /// and a `cleanup()` could take it for one nobody is using. And it's a move, into a directory that didn't
    /// exist, so nothing sees the bundle half there and no bundle on disk is written over.
    private func publish(_ draft: Draft) throws -> EditorAssetBundle {
        var draft = draft

        do {
            // Marked before it's moved, while nothing else can see it
            try draft.record(assetHeaders: draft.bundle.assetHeaders, lastCheckedDate: Date())

            return try Self.storageLock.withLock {
                try FileManager.default.createDirectory(at: self.storageRoot, withIntermediateDirectories: true)

                // The manifest's own directory, unless something is already there
                var destination = self.bundleRoot(for: draft.bundle.id)
                if FileManager.default.fileExists(atPath: destination.path) {
                    destination = self.storageRoot.appending(path: "\(draft.bundle.id)-\(UUID().uuidString)")
                }

                try FileManager.default.moveItem(at: draft.bundle.bundleRoot, to: destination)
                Self.handedOut.insert(destination.standardizedFileURL)

                return try EditorAssetBundle(url: self.bundleManifestPath(relativeTo: destination))
            }
        } catch {
            draft.discard()
            throw error
        }
    }

    /// Whether two bundles of one manifest hold the same assets: each either missing from both, or identical.
    private func hasSameAssets(_ bundle: EditorAssetBundle, as other: EditorAssetBundle) -> Bool {
        self.downloadableAssets(in: bundle.manifest).allSatisfy { asset in
            let path = self.assetPath(for: asset, in: bundle).path
            let otherPath = self.assetPath(for: asset, in: other).path

            guard FileManager.default.fileExists(atPath: path) else {
                return !FileManager.default.fileExists(atPath: otherPath)
            }

            return FileManager.default.contentsEqual(atPath: path, andPath: otherPath)
        }
    }

    /// Downloads whichever of `draft`'s assets aren't in it yet: every asset that wasn't carried forward.
    ///
    /// Returns the headers each downloaded asset's server sent with it, by the asset's key.
    private func downloadMissingAssets(
        of draft: Draft,
        unlessSameAsIn sources: [AssetSource] = [],
        reportingTo progress: EditorProgressCallback
    ) async throws -> [String: EditorAssetBundle.AssetHeaders] {
        let missingAssets = self.missingAssets(of: draft.bundle)

        guard !missingAssets.isEmpty else {
            await progress(EditorProgress(completed: 1, total: 1))
            return [:]
        }

        return try await self.downloadAssets(
            missingAssets,
            into: draft,
            unlessSameAsIn: sources,
            reportingTo: progress
        )
    }

    /// The assets `bundle` should have that aren't on disk: the ones that failed to download.
    func missingAssets(of bundle: EditorAssetBundle) -> [URL] {
        self.downloadableAssets(in: bundle.manifest)
            .filter { !FileManager.default.fileExists(at: self.assetPath(for: $0, in: bundle)) }
    }

    /// Records that the site's manifest matches `bundle` now, and that the bundle has been handed out. That makes
    /// it the site's latest bundle, and starts its age for the cache policy over. Returns `nil` if the bundle is
    /// no longer on disk.
    private func markLatest(_ bundle: EditorAssetBundle) -> EditorAssetBundle? {
        Self.storageLock.withLock {
            guard self.hasBundle(at: bundle.bundleRoot) else {
                return nil
            }

            Self.handedOut.insert(bundle.bundleRoot.standardizedFileURL)

            do {
                let latestBundle = try EditorAssetBundle(
                    manifest: bundle.manifest,
                    downloadDate: bundle.downloadDate,
                    lastCheckedDate: Date(),
                    assetHeaders: bundle.assetHeaders,
                    bundleRoot: bundle.bundleRoot
                )
                // Written straight to the file, which is known to be there: `writeManifest()` would
                // create the bundle's directory if it weren't.
                try latestBundle.dataRepresentation()
                    .write(to: self.bundleManifestPath(relativeTo: bundle.bundleRoot), options: .atomic)
                return latestBundle
            } catch {
                // The bundle is still complete and correct; it'll just be checked again sooner.
                log(.warn, "Failed to mark asset bundle \(bundle.id) as the latest: \(error.localizedDescription)")
                return bundle
            }
        }
    }

    /// Assembles a bundle for `manifest` as a draft, for the caller to put in the library's storage with
    /// ``publish(_:)`` or to discard. A build that fails discards the draft itself.
    private func build(
        _ manifest: LocalEditorAssetManifest,
        reportingTo progress: EditorProgressCallback
    ) async throws -> Draft {
        var draft = try Draft(manifest: manifest)

        do {
            let editorRepresentation = try manifest.buildEditorRepresentation(for: self.configuration)
            try draft.bundle.writeManifest(editorRepresentation: editorRepresentation)

            let sources = self.assetSources()
            let carried: [String: EditorAssetBundle.AssetHeaders]
            let downloaded: [String: EditorAssetBundle.AssetHeaders]

            switch self.cachePolicy {
            case .always, .maxAge:
                // Only a versioned URL is taken to mean the same file, and copied without asking. One
                // without a version can change without its URL saying so: the site is asked for it,
                // though only for a newer copy when its server said how to tell one from another.
                //
                // A bundle already on disk for this manifest is the exception: the manifest hasn't
                // changed, so the bundle keeps every asset it has, and only what it's missing is
                // asked for.
                let assets = self.downloadableAssets(in: manifest)
                let unchanged = self.carryForward(
                    assets,
                    from: sources.filter { $0.bundle.id == manifest.checksum },
                    into: draft
                )
                let versioned = self.carryForward(assets.filter { self.isVersioned($0) }, from: sources, into: draft)
                carried = unchanged.merging(versioned) { $1 }
                downloaded = try await self.downloadMissingAssets(
                    of: draft,
                    unlessSameAsIn: sources,
                    reportingTo: progress
                )
            case .ignore:
                // Takes nothing on disk as valid, so every asset is downloaded in full.
                carried = [:]
                downloaded = try await self.downloadMissingAssets(of: draft, reportingTo: progress)
            }

            // An asset that fails to download has no better copy than one already on disk, which
            // beats a gap.
            let kept = self.carryForward(self.missingAssets(of: draft.bundle), from: sources, into: draft)

            // Each asset has one entry at most: an asset in the draft is neither downloaded nor
            // carried again.
            try draft.record(assetHeaders: carried.merging(downloaded) { $1 }.merging(kept) { $1 })
            return draft
        } catch {
            draft.discard()
            throw error
        }
    }

    /// A bundle on disk, and the assets it should have.
    private typealias AssetSource = (bundle: EditorAssetBundle, assets: Set<URL>)

    /// The bundles on disk that a build can take a copy of an asset from, the latest first.
    private func assetSources() -> [AssetSource] {
        ((try? self.readAssetBundles()) ?? []).map {
            (bundle: $0, assets: Set(self.downloadableAssets(in: $0.manifest)))
        }
    }

    /// The latest of `sources` that has `asset` under the same URL. That isn't always the site's latest
    /// bundle: a site can go back to a manifest it had before, whose assets only that manifest's bundle has.
    private func source(of asset: URL, in sources: [AssetSource]) -> EditorAssetBundle? {
        sources.first {
            $0.assets.contains(asset) && FileManager.default.fileExists(at: self.assetPath(for: asset, in: $0.bundle))
        }?.bundle
    }

    /// Copies into `draft` each of `assets` that one of `sources` has under the same URL. Returns the
    /// headers that came with each asset copied, by the asset's key.
    private func carryForward(
        _ assets: [URL],
        from sources: [AssetSource],
        into draft: Draft
    ) -> [String: EditorAssetBundle.AssetHeaders] {
        var assetHeaders: [String: EditorAssetBundle.AssetHeaders] = [:]

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
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try FileManager.default.copyItem(at: self.assetPath(for: asset, in: source), to: destination)
                assetHeaders[EditorAssetBundle.assetKey(for: asset)] = source.headers(for: asset)
            } catch {
                // The bundle has been removed since. Leave nothing behind, so that it reads as missing.
                try? FileManager.default.removeItem(at: destination)
            }
        }

        return assetHeaders
    }

    /// Whether `url` carries a version the way WordPress adds one: a `ver` in its query.
    private func isVersioned(_ url: URL) -> Bool {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .contains { $0.name == "ver" && $0.value?.isEmpty == false } ?? false
    }

    /// The assets in `manifest` that belong in its bundle: every link that one of its script or stylesheet
    /// tags loads over HTTP. The tag is what makes a link an asset, however its URL ends.
    private func downloadableAssets(in manifest: LocalEditorAssetManifest) -> [URL] {
        (manifest.scripts + manifest.styles).filter { self.isDownloadable($0) }
    }

    /// Downloads `assets` into `draft` concurrently, tolerating any that fail. Returns the headers each
    /// one's server sent with it, by the asset's key.
    private func downloadAssets(
        _ assets: [URL],
        into draft: Draft,
        unlessSameAsIn sources: [AssetSource],
        reportingTo progress: EditorProgressCallback
    ) async throws -> [String: EditorAssetBundle.AssetHeaders] {
        var complete = 0
        var assetHeaders: [String: EditorAssetBundle.AssetHeaders] = [:]

        await withTaskGroup(of: (URL, EditorAssetBundle.AssetHeaders?).self) { group in
            for asset in assets {
                group.addTask {
                    do {
                        return (asset, try await self.fetchAsset(url: asset, into: draft, unlessSameAsIn: sources))
                    } catch {
                        // Log and continue - individual asset failures shouldn't block the editor
                        // This handles cases like content blockers blocking analytics scripts
                        log(.warn, "Failed to download asset \(asset.lastPathComponent): \(error.localizedDescription)")
                        return (asset, nil)
                    }
                }
            }

            for await (asset, headers) in group {
                assetHeaders[EditorAssetBundle.assetKey(for: asset)] = headers
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

        return assetHeaders
    }

    /// Downloads a single asset into `draft`, and returns the headers its server sent with it.
    ///
    /// If one of `sources` has the asset, and its server said how to tell one version from another, the
    /// server is asked only for a newer copy. When it has none, the draft takes the copy on disk rather than
    /// downloading the same file again.
    private func fetchAsset(
        url: URL,
        into draft: Draft,
        unlessSameAsIn sources: [AssetSource]
    ) async throws -> EditorAssetBundle.AssetHeaders? {
        let source = self.source(of: url, in: sources)
        let heldHeaders = source?.headers(for: url).flatMap { $0.canRevalidate ? $0 : nil }

        var request = self.assetRequest(for: url)
        if let heldHeaders {
            heldHeaders.makeConditional(&request)
            // The request says which copy it has, so a stored response has nothing to add
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }

        let (tempUrl, response) = try await logExecutionTime("Downloading \(url.lastPathComponent)") { [request] in
            try await httpClient.download(request)
        }

        // The download's file is this method's to deal with. It's moved into the draft below; when it
        // isn't — the server had nothing newer, or something fails first — it's removed.
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        let destinationPath = self.assetPath(for: url, in: draft.bundle)
        let destinationParent = destinationPath.deletingLastPathComponent()

        // Ensure the destination directory exists
        try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)

        guard response.statusCode != 304 else {
            // Only a request that said which copy it has should be answered this way
            guard let source, let heldHeaders else {
                throw URLError(.badServerResponse)
            }

            // The copy on disk is the file, so what came with it still describes it
            try FileManager.default.copyItem(at: self.assetPath(for: url, in: source), to: destinationPath)
            return heldHeaders
        }

        let headers = EditorAssetBundle.AssetHeaders(response: response)

        // A server can answer with a web page and still say the request went well: one to log in on, or one
        // saying what went wrong. Kept, it would be served in the asset's place for as long as the bundle is.
        guard !self.isWebPage(headers?.contentType) else {
            throw UnexpectedContentType(contentType: headers?.contentType ?? "")
        }

        try FileManager.default.moveItem(at: tempUrl, to: destinationPath)

        return headers
    }

    /// Whether a response of `contentType` is a web page, which no script or stylesheet is.
    ///
    /// Nothing else about its type is held against a download. The editor is served an asset with the type it
    /// came with, so a web view decides what to make of it just as it would if the site had served it.
    private func isWebPage(_ contentType: String?) -> Bool {
        let mediaType = contentType?
            .split(separator: ";", omittingEmptySubsequences: false).first?
            .trimmingCharacters(in: .whitespaces)
            .lowercased()

        return mediaType == "text/html"
    }

    /// A download answered with something other than the asset: `contentType` is what the server said it was.
    struct UnexpectedContentType: LocalizedError {
        let contentType: String

        var errorDescription: String? {
            "The server answered with \(self.contentType)"
        }
    }

    /// The request for the asset at `url`. Under `.ignore`, it asks for a stored response not to be used.
    private func assetRequest(for url: URL) -> URLRequest {
        var request = URLRequest(method: .GET, url: url)
        if case .ignore = self.cachePolicy {
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }
        return request
    }

    /// Where the asset at `url` is stored in `bundle`, which is for the bundle to say: the editor reads it
    /// from there.
    private func assetPath(for url: URL, in bundle: EditorAssetBundle) -> URL {
        bundle.assetDataPath(for: url)
    }

    /// The links in `manifest` that a bundle doesn't hold: the ones that aren't HTTP or HTTPS URLs.
    func linksLeftOut(of manifest: LocalEditorAssetManifest) -> [URL] {
        (manifest.scripts + manifest.styles).filter { !self.isDownloadable($0) }
    }

    /// Checks if the given `url` is one the library can download into a bundle. It says nothing about one
    /// that isn't: ``fetchManifest()`` does, once.
    private func isDownloadable(_ url: URL) -> Bool {
        url.scheme == "http" || url.scheme == "https"
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

    /// Where a manifest's bundle goes, unless it's built under `.ignore`, which gives each build a directory
    /// of its own.
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
