import Foundation

/// The Editor Asset Library is a site-specific repository of remote assets that can be downloaded to the local device to support plugins and theme styles.
///
public actor EditorAssetLibrary {

    private let configuration: EditorConfiguration
    private let httpClient: EditorHTTPClientProtocol
    private let storageRoot: URL
    private let cachePolicy: EditorCachePolicy

    /// A cache of ``downloadableAssets(in:)``, keyed by manifest checksum. Computing it reads every link in the
    /// manifest, and one prepare asks for it several times.
    private var downloadableAssetsByManifest: [String: [URL]] = [:]

    /// Bundle builds in flight, keyed by their manifest's bundle directory. Every service creates
    /// its own library, so this is shared across all of them.
    static let inFlightBuilds = InFlightTasks<URL, EditorAssetBundle>()

    /// Guards every change to storage, and `handedOut`. Every service creates its own library, so actor
    /// isolation alone doesn't order changes made by different libraries.
    ///
    /// Storage changes in only three ways, each made in one step while holding this lock:
    ///
    /// - ``publish(_:matchedAt:keptFrom:)`` moves a finished bundle in, already dated and handed out.
    /// - ``markLatest(_:matchedAt:recording:)`` rewrites the `manifest.json` of a bundle that's still there.
    /// - ``cleanup()`` and ``purge()`` remove whole bundles.
    ///
    /// So a bundle in storage is always complete and never gains or loses a file, and `cleanup()` can't
    /// remove a newly published bundle before it's marked as handed out. Assets are only ever written into a
    /// ``Draft``, in a temporary directory outside storage.
    private static let storageLock = NSLock()

    /// The directory of every bundle this process has handed to a caller. An editor, or
    /// dependencies a host is holding, may still be reading one, so `cleanup()` doesn't remove them.
    nonisolated(unsafe) private static var handedOut: Set<URL> = []

    /// Creates a new `EditorAssetLibrary` instance.
    ///
    /// - Parameters:
    ///   - configuration: The editor configuration containing site-specific settings.
    ///   - httpClient: The HTTP client used to fetch remote assets.
    ///   - cachePolicy: The policy that decides how long ``readLatestAssetBundle()`` keeps returning
    ///     the latest bundle on disk before the site's manifest must be checked again.
    ///     Use `.ignore` to check it every time and download every asset again, `.maxAge(_:)` to
    ///     check it once the last check is older than a time interval, or `.always` (the default)
    ///     to check it only when there's no bundle on disk, or the latest is missing assets.
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
    /// method returns the manifest stored with that bundle instead.
    ///
    func fetchManifest() async throws -> LocalEditorAssetManifest {
        guard configuration.shouldUsePlugins else { return .empty }
        var request = URLRequest(method: .GET, url: self.editorAssetsUrl(for: self.configuration))
        switch self.cachePolicy {
        case .always:
            // `EditorService` only fetches under `.always` when there's no bundle on disk, or the latest is
            // missing assets. The point is to get the assets, not to see whether the site changed, so
            // joining a request in flight is fine.
            break
        case .maxAge, .ignore:
            // A check must see what the site serves now, so it can't use a stored response or join
            // a request already in flight.
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

        // Warn only when a manifest is first parsed. `downloadableAssets(in:)` filters the same links on
        // every prepare, so warning there would repeat the same message each time.
        for url in self.linksLeftOut(of: manifest) {
            log(.warn, "Unexpected asset link: \(url)")
        }

        return manifest
    }

    // MARK: - Bundle Handling

    /// The site's asset bundles on disk, latest first: ordered by when the site's manifest last matched each
    /// one.
    ///
    public func readAssetBundles() throws -> [EditorAssetBundle] {
        try self.readAssetBundles { _ in true }
    }

    /// The bundles in directories whose names pass `isIncluded`, latest first. Filtering by name first avoids
    /// decoding every bundle's manifest.
    private func readAssetBundles(inDirectoriesNamed isIncluded: (String) -> Bool) throws -> [EditorAssetBundle] {
        try FileManager.default.createDirectory(at: self.storageRoot, withIntermediateDirectories: true)
        return try FileManager.default
            .contentsOfDirectory(at: self.storageRoot, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { $0.hasDirectoryPath }  // Only include directories
            .filter { $0.pathExtension != "download" }  // Don't include bundles that are being downloaded
            .filter { isIncluded($0.lastPathComponent) }
            // Rebuild the path rather than use the listed URL. A listing resolves symlinks (`/var` to
            // `/private/var`), so the bundle would compare unequal to the same one built or found by checksum.
            .map { self.bundleManifestPath(for: $0.lastPathComponent) }
            .compactMap { try? EditorAssetBundle(url: $0) }  // Skip invalid/incomplete bundles
            // Not by download date: a site can switch back to an earlier manifest, whose bundle was downloaded
            // before the one it replaces.
            .sorted { $0.lastMatchedDate > $1.lastMatchedDate }
    }

    /// The latest bundle on disk, if the site's manifest doesn't need checking again.
    ///
    /// Returns `nil` if there's no bundle, if the cache policy says the last check is too old, or if the
    /// bundle is missing assets that a retry might download. In each case, call
    /// ``downloadAssetBundle(progress:)`` next.
    ///
    /// A bundle that used an earlier copy for an asset that failed to download is still returned: it has
    /// every file the editor loads.
    public func readLatestAssetBundle() throws -> EditorAssetBundle? {
        guard let latest = try self.latestBundleWithinPolicy(), latest.missingAssets.isEmpty else {
            return nil
        }

        return self.handOut(latest.bundle)
    }

    /// The latest bundle on disk, if its last check is recent enough for the cache policy, and whether it's
    /// missing assets.
    ///
    /// Unlike ``readLatestAssetBundle()``, this returns a bundle that's missing assets, so the caller can retry
    /// them and fall back to the bundle if the manifest check fails. It doesn't hand the bundle out: call
    /// ``handOut(_:)`` before giving it to a caller.
    func readLatestAssetBundleWithinPolicy() throws -> (bundle: EditorAssetBundle, isMissingAssets: Bool)? {
        try self.latestBundleWithinPolicy().map { ($0.bundle, !$0.missingAssets.isEmpty) }
    }

    private func latestBundleWithinPolicy() throws -> (bundle: EditorAssetBundle, missingAssets: [URL])? {
        guard
            let latest = try self.latestBundle(),
            self.cachePolicy.allowsResponseWith(date: latest.bundle.lastMatchedDate)
        else {
            return nil
        }

        return latest
    }

    /// The site's latest bundle on disk, and the assets it's missing.
    private func latestBundle() throws -> (bundle: EditorAssetBundle, missingAssets: [URL])? {
        try self.readAssetBundles().first.map { ($0, self.missingAssets(of: $0)) }
    }

    /// Records that `bundle` is being handed to a caller, so that `cleanup()` keeps it. Returns `nil` if it's
    /// no longer on disk.
    func handOut(_ bundle: EditorAssetBundle) -> EditorAssetBundle? {
        Self.storageLock.withLock {
            guard self.hasBundle(at: bundle.bundleRoot) else { return nil }
            Self.handedOut.insert(bundle.bundleRoot.standardizedFileURL)
            return bundle
        }
    }

    /// Fetches the site's manifest and builds a bundle of its assets on disk.
    ///
    /// Under `.always` and `.maxAge`:
    ///
    /// - If a bundle for the same manifest is on disk with every asset, it's returned without downloading
    ///   anything. Asset URLs carry their version, so an unchanged manifest means unchanged assets. If that
    ///   bundle is missing assets, they're retried, into a new bundle beside it.
    /// - If the manifest has changed, each asset with a `?ver=` that a bundle on disk already has is copied
    ///   from that bundle, and the rest are downloaded.
    ///
    /// That trusts the site's versions. WordPress gives an asset registered without a version
    /// `?ver=<WordPress version>`, so that file can change while its URL stays the same. Only `.ignore`
    /// downloads it again.
    ///
    /// Under `.ignore`, every asset is downloaded into a new bundle, whether or not the manifest has changed.
    /// Assets in a bundle on disk are never changed, because an editor may be reading them. If the manifest
    /// hasn't changed and every asset comes back identical, the bundle on disk is returned instead.
    ///
    /// Under every policy, an asset that fails to download is copied from the latest bundle on disk that has
    /// it.
    ///
    /// The bundle is dated by when the manifest was fetched, not when the build finished. It becomes the
    /// site's latest unless another manifest has been seen since, and its age for the cache policy starts
    /// then.
    ///
    /// - Parameter progress: An optional callback that receives progress updates as assets are downloaded.
    /// - Returns: The downloaded `EditorAssetBundle` containing all cached assets.
    /// - Throws: An error if the manifest can't be fetched, or the bundle can't be written. An asset that fails
    ///   to download doesn't throw.
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
    /// A manifest can have several bundles on disk: each `.ignore` download or retry of missing assets that
    /// changes the assets adds one. This returns the one the site's manifest matched most recently.
    func existingBundle(forManifestChecksum checksum: String) -> EditorAssetBundle? {
        // A bundle's directory is its manifest's checksum, optionally followed by `-<UUID>`
        try? self.readAssetBundles { $0.hasPrefix(checksum) }.first { $0.id == checksum }
    }

    // MARK: - Individual Asset Handling

    /// Builds the bundle for `manifest`, or reuses the one on disk.
    ///
    /// If a bundle for the manifest is on disk with every asset, it's returned. If it's missing assets, they're
    /// retried in a new bundle beside it, which is kept only if its assets differ. Otherwise a new bundle is
    /// built in a temporary directory, copying what it can from bundles on disk and downloading the rest
    /// concurrently, then moved into storage in one step. Under `.ignore`, the bundle is always built again,
    /// downloading every asset.
    ///
    /// The bundle returned is marked as matching the site's manifest at `manifestFetchDate`, when the manifest
    /// was fetched.
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

        // An `.ignore` build never joins one in flight, not even another `.ignore` build. It must
        // download every asset after this call, and a build already running may have downloaded
        // some of them before this call.
        if case .ignore = self.cachePolicy {
            return try await self.buildFreshBundle(for: manifest, fetchedAt: manifestFetchDate) { await progress?($0) }
        }

        // Any other build of the same manifest does the same work, whichever library runs it, so
        // join one in flight rather than download everything twice.
        let key = self.bundleRoot(for: manifest.checksum).standardizedFileURL
        let bundle = try await Self.inFlightBuilds.value(for: key, progress: progress) { report in
            try await self.reuseOrBuildBundle(for: manifest, fetchedAt: manifestFetchDate, reportingTo: report)
        }

        // A shared build dates the bundle by the fetch of the library that started it. A library that
        // joined fetched the manifest later, so it marks the bundle with its own, later date.
        guard let lastCheckedDate = bundle.lastCheckedDate, lastCheckedDate < manifestFetchDate else {
            return bundle
        }

        return self.markLatest(bundle, matchedAt: manifestFetchDate) ?? bundle
    }

    /// Returns the bundle on disk for `manifest` if it has every asset downloaded, and otherwise builds one.
    ///
    /// It looks for the bundle on disk inside the build that callers share, so a build that finished in the
    /// meantime is reused.
    private func reuseOrBuildBundle(
        for manifest: LocalEditorAssetManifest,
        fetchedAt manifestFetchDate: Date,
        reportingTo progress: EditorProgressCallback
    ) async throws -> EditorAssetBundle {
        // Another library can publish a bundle for this manifest while this one works, because an
        // `.ignore` build doesn't share this one. Then what was found or built here is out of date,
        // and marking or publishing it would put it in front of the newer bundle. So look for the
        // manifest's bundle again, once for each bundle published in the meantime.
        while true {
            let existingBundle = self.existingBundle(forManifestChecksum: manifest.checksum)

            if let existingBundle, self.missingAssets(of: existingBundle).isEmpty {
                await progress(EditorProgress(completed: 1, total: 1))

                // Another library published a newer bundle, or `cleanup()` or `purge()` deleted this one
                // since it was found. Look again.
                if let latestBundle = self.markLatest(existingBundle, matchedAt: manifestFetchDate) {
                    return latestBundle
                }

                continue
            }

            // Retried assets don't go into the bundle on disk, because an editor may be reading it. The
            // new build copies what that bundle has and retries the rest.
            let draft = try await self.build(manifest, keepingAssetsOf: existingBundle, reportingTo: progress)

            if let bundle = try self.publish(draft, matchedAt: manifestFetchDate, unlessSameAs: existingBundle) {
                return bundle
            }

            draft.discard()
        }
    }

    /// Builds a bundle for `manifest` by downloading every asset, as `.ignore` requires.
    ///
    /// The new bundle goes beside the manifest's bundle on disk, not over it, because an editor may be reading
    /// that one. It never joins a build in flight: a build under another policy doesn't download everything,
    /// and another `.ignore` build started before this call. When two overlap, the one that finishes last
    /// becomes the site's latest.
    ///
    /// If every asset comes back identical to the bundle on disk, that bundle is returned and the new one is
    /// discarded. A refresh that changed nothing then takes no disk space, and a host comparing dependencies
    /// sees no change. If only some assets match, the new bundle shares their disk space with the copies they
    /// match.
    private func buildFreshBundle(
        for manifest: LocalEditorAssetManifest,
        fetchedAt manifestFetchDate: Date,
        reportingTo progress: EditorProgressCallback
    ) async throws -> EditorAssetBundle {
        let draft = try await self.build(manifest, reportingTo: progress)

        // `hasSameAssets` compares every file of this draft by content, so the draft can be compared with
        // whichever bundle the manifest has now, including one another library published in the meantime.
        while true {
            let existingBundle = self.existingBundle(forManifestChecksum: manifest.checksum)

            if let bundle = try self.publish(draft, matchedAt: manifestFetchDate, unlessSameAs: existingBundle) {
                return bundle
            }
        }
    }

    /// A bundle being assembled in a temporary directory that nothing else can see or delete.
    ///
    /// Assets are only ever written into a draft. Its only initializer picks a new directory, so a draft
    /// can't wrap a bundle in storage, and nothing that downloads or copies an asset can touch a bundle an
    /// editor may be reading. Publishing is the only way a draft gets into storage.
    private struct Draft: Sendable {
        /// The bundle as it stands in the temporary directory.
        private(set) var bundle: EditorAssetBundle

        /// The keys of the assets copied from the bundle on disk for the same manifest. The build didn't
        /// download these, so their headers come from that bundle.
        var assetsKeptFromExistingBundle: Set<String> = []

        /// Creates a draft of the bundle for `manifest`, in a new temporary directory.
        init(manifest: LocalEditorAssetManifest) throws {
            self.bundle = try EditorAssetBundle(
                manifest: manifest,
                bundleRoot: URL.temporaryDirectory.appending(path: UUID().uuidString)
            )
        }

        /// Rewrites the draft's `manifest.json` with its assets' headers and, for a draft about to be
        /// published, its `lastCheckedDate`.
        mutating func record(
            assetHeaders: [String: EditorAssetBundle.AssetHeaders],
            lastCheckedDate: Date? = nil
        ) throws {
            self.bundle = self.bundle.recording(lastCheckedDate: lastCheckedDate, assetHeaders: assetHeaders)
            try self.bundle.writeManifest()
        }

        /// Removes the draft's directory, for a draft that won't be published.
        func discard() {
            try? FileManager.default.removeItem(at: self.bundle.bundleRoot)
        }
    }

    /// Publishes `draft` as the site's latest bundle, unless `existingBundle` — the bundle on disk for the same
    /// manifest — already has the same assets.
    ///
    /// In that case, `existingBundle` is marked as the latest instead, with the headers the build received,
    /// and the draft is discarded. A build that changed nothing takes no disk space.
    ///
    /// `existingBundle` must be the bundle the draft copied assets from, if it copied any. Returns `nil`,
    /// leaving the draft in place, if another bundle has become the manifest's latest on disk since
    /// `existingBundle` was read.
    private func publish(
        _ draft: Draft,
        matchedAt matchDate: Date,
        unlessSameAs existingBundle: EditorAssetBundle?
    ) throws -> EditorAssetBundle? {
        if let existingBundle,
            self.hasSameAssets(draft, as: existingBundle),
            let latestBundle = self.markLatest(existingBundle, matchedAt: matchDate, recording: draft) {
            draft.discard()
            return latestBundle
        }

        return try self.publish(draft, matchedAt: matchDate, keptFrom: existingBundle)
    }

    /// Moves `draft` into storage, dated `matchDate` and marked as handed out.
    ///
    /// It happens in one step under `storageLock`, so `cleanup()` never sees the bundle before it's marked as
    /// handed out. It's a move into a new directory, so nothing sees a half-written bundle and no bundle on
    /// disk is overwritten.
    ///
    /// `existingBundle` is the manifest's bundle on disk as the build found it, if any. Returns `nil`, leaving
    /// the draft in place, if another library has published a bundle for the manifest since: the draft didn't
    /// account for it.
    private func publish(
        _ draft: Draft,
        matchedAt matchDate: Date,
        keptFrom existingBundle: EditorAssetBundle?
    ) throws -> EditorAssetBundle? {
        var draft = draft

        do {
            return try Self.storageLock.withLock {
                // If the manifest's latest bundle on disk isn't `existingBundle`, another library has
                // published one since.
                let recorded = self.existingBundle(forManifestChecksum: draft.bundle.id)

                guard recorded == nil || recorded?.bundleRoot == existingBundle?.bundleRoot else {
                    return nil
                }

                // The new bundle replaces the one on disk, so it must sort ahead of it. If another library
                // has recorded a later match on that bundle than this build's fetch, date this one just
                // after it.
                let matchDate = recorded.map { max(matchDate, $0.lastMatchedDate.addingTimeInterval(0.001)) } ?? matchDate

                // Write the date and headers before the move, while the draft is still private
                try draft.record(
                    assetHeaders: self.assetHeaders(from: draft, keptFrom: recorded),
                    lastCheckedDate: matchDate
                )

                let bundle = try self.place(draft)
                Self.handedOut.insert(bundle.bundleRoot.standardizedFileURL)

                return bundle
            }
        } catch {
            draft.discard()
            throw error
        }
    }

    /// The headers to record for `draft`'s assets.
    ///
    /// For assets copied from the manifest's bundle on disk, these are what `recorded` holds now, not what it
    /// held when the build read it: another library may have changed them since. Every other asset keeps the
    /// headers the draft has for it.
    private func assetHeaders(
        from draft: Draft,
        keptFrom recorded: EditorAssetBundle?
    ) -> [String: EditorAssetBundle.AssetHeaders] {
        var assetHeaders = draft.bundle.assetHeaders

        if let recorded {
            for key in draft.assetsKeptFromExistingBundle {
                assetHeaders[key] = recorded.assetHeaders[key]
            }
        }

        return assetHeaders
    }

    /// Moves `draft` into the library's storage as it stands. Call it with `storageLock` held.
    private func place(_ draft: Draft) throws -> EditorAssetBundle {
        try FileManager.default.createDirectory(at: self.storageRoot, withIntermediateDirectories: true)

        // The manifest's checksum as the directory name, or `<checksum>-<UUID>` if that's taken
        var destination = self.bundleRoot(for: draft.bundle.id)
        if FileManager.default.fileExists(atPath: destination.path) {
            destination = self.storageRoot.appending(path: "\(draft.bundle.id)-\(UUID().uuidString)")
        }

        try FileManager.default.moveItem(at: draft.bundle.bundleRoot, to: destination)

        return try EditorAssetBundle(url: self.bundleManifestPath(relativeTo: destination))
    }

    /// Whether `draft` and `other`, a bundle of the same manifest, have the same assets: each asset is either
    /// missing from both or identical in both.
    ///
    /// An asset the draft copied from `other` is identical by construction, so only its presence is checked.
    private func hasSameAssets(_ draft: Draft, as other: EditorAssetBundle) -> Bool {
        self.downloadableAssets(in: draft.bundle.manifest).allSatisfy { asset in
            let path = self.assetPath(for: asset, in: draft.bundle).path
            let otherPath = self.assetPath(for: asset, in: other).path

            guard FileManager.default.fileExists(atPath: path) else {
                return !FileManager.default.fileExists(atPath: otherPath)
            }

            guard !draft.assetsKeptFromExistingBundle.contains(EditorAssetBundle.assetKey(for: asset)) else {
                return FileManager.default.fileExists(atPath: otherPath)
            }

            return FileManager.default.contentsEqual(atPath: path, andPath: otherPath)
        }
    }

    /// Downloads the assets `draft` doesn't have yet: every asset that wasn't copied in.
    ///
    /// Returns each downloaded asset's headers, keyed by asset key.
    private func downloadMissingAssets(
        of draft: Draft,
        reportingTo progress: EditorProgressCallback
    ) async throws -> [String: EditorAssetBundle.AssetHeaders] {
        let missingAssets = self.missingAssets(of: draft.bundle)

        guard !missingAssets.isEmpty else {
            await progress(EditorProgress(completed: 1, total: 1))
            return [:]
        }

        return try await self.downloadAssets(missingAssets, into: draft, reportingTo: progress)
    }

    /// The assets `bundle` should have but doesn't. For a finished bundle, these are the ones that failed to
    /// download, with no earlier copy to stand in.
    func missingAssets(of bundle: EditorAssetBundle) -> [URL] {
        self.downloadableAssets(in: bundle.manifest)
            .filter { !FileManager.default.fileExists(at: self.assetPath(for: $0, in: bundle)) }
    }

    /// Records that the site's manifest matched `bundle` at `matchDate`, and marks the bundle as handed out.
    /// This makes it the site's latest bundle, unless another manifest has been seen since, and restarts its
    /// age for the cache policy.
    ///
    /// Returns `nil` if the bundle is gone, or is no longer its manifest's latest bundle on disk: another
    /// library has published a newer one, and marking this one would put it back in front.
    ///
    /// `draft`, if given, is a build of the same manifest with identical assets, and its headers are recorded
    /// too. Otherwise the bundle keeps the headers on disk now, not the ones `bundle` had when it was read:
    /// another library may have changed them since.
    private func markLatest(
        _ bundle: EditorAssetBundle,
        matchedAt matchDate: Date,
        recording draft: Draft? = nil
    ) -> EditorAssetBundle? {
        Self.storageLock.withLock { () -> EditorAssetBundle? in
            // If the manifest's latest bundle on disk isn't `bundle`, it's been removed, or another
            // library has published one since.
            guard
                let recorded = self.existingBundle(forManifestChecksum: bundle.id),
                recorded.bundleRoot == bundle.bundleRoot
            else {
                return nil
            }

            Self.handedOut.insert(bundle.bundleRoot.standardizedFileURL)

            let assetHeaders = draft.map { self.assetHeaders(from: $0, keptFrom: recorded) } ?? recorded.assetHeaders

            // Keep a later match date if another library has already recorded one
            let latestBundle = bundle.recording(
                lastCheckedDate: max(recorded.lastMatchedDate, matchDate),
                assetHeaders: assetHeaders
            )

            do {
                try self.rewriteManifest(of: latestBundle)
            } catch {
                // The bundle is still complete and correct, so return it, with its new date and headers,
                // anyway. Its age on disk just won't restart, so it'll be checked again sooner.
                log(.warn, "Failed to mark asset bundle \(bundle.id) as the latest: \(error.localizedDescription)")
            }

            return latestBundle
        }
    }

    /// Overwrites `bundle`'s `manifest.json` in storage. Call it with `storageLock` held, after checking the
    /// bundle is still there.
    ///
    /// It writes the file directly, because `EditorAssetBundle.writeManifest()` would recreate the bundle's
    /// directory if it had been removed.
    private func rewriteManifest(of bundle: EditorAssetBundle) throws {
        try bundle.dataRepresentation()
            .write(to: self.bundleManifestPath(relativeTo: bundle.bundleRoot), options: .atomic)
    }

    /// Builds a draft bundle for `manifest`, for the caller to publish with
    /// ``publish(_:matchedAt:unlessSameAs:)``. If the build fails, it discards the draft itself.
    ///
    /// `existingBundle` is the bundle on disk for the same manifest, if there is one and the cache policy
    /// isn't `.ignore`. The manifest hasn't changed, so the draft copies every asset that bundle has.
    private func build(
        _ manifest: LocalEditorAssetManifest,
        keepingAssetsOf existingBundle: EditorAssetBundle? = nil,
        reportingTo progress: EditorProgressCallback
    ) async throws -> Draft {
        var draft = try Draft(manifest: manifest)

        do {
            let editorRepresentation = try manifest.buildEditorRepresentation(for: self.configuration)
            try draft.bundle.writeManifest(editorRepresentation: editorRepresentation)

            let sources = self.assetSources()
            var assetHeaders: [String: EditorAssetBundle.AssetHeaders] = [:]

            switch self.cachePolicy {
            case .always, .maxAge:
                // Copy assets with a versioned URL from any bundle on disk. Download the rest: an
                // unversioned file can change without its URL changing.
                //
                // A bundle on disk for this same manifest is the exception. The manifest hasn't changed,
                // so every asset that bundle has is copied, versioned or not.
                let assets = self.downloadableAssets(in: manifest)

                if let existingBundle {
                    let unchanged = self.carryForward(assets, from: [existingBundle], into: draft)
                    assetHeaders.merge(unchanged.headers) { $1 }
                    draft.assetsKeptFromExistingBundle = unchanged.keys
                }

                let versioned = self.carryForward(assets.filter { self.isVersioned($0) }, from: sources, into: draft)
                assetHeaders.merge(versioned.headers) { $1 }

                let downloaded = try await self.downloadMissingAssets(of: draft, reportingTo: progress)
                assetHeaders.merge(downloaded) { $1 }
            case .ignore:
                // Trust nothing on disk: download every asset, then share disk space with identical copies
                assetHeaders = try await self.downloadMissingAssets(of: draft, reportingTo: progress)
                self.shareUnchangedAssets(of: draft, with: sources)
            }

            // For an asset that failed to download, an earlier copy from disk is better than none
            let failed = self.missingAssets(of: draft.bundle)
            let kept = self.carryForward(failed, from: sources, into: draft)
            assetHeaders.merge(kept.headers) { $1 }

            try draft.record(assetHeaders: assetHeaders)
            return draft
        } catch {
            draft.discard()
            throw error
        }
    }

    /// The bundles on disk a build can copy assets from, latest first.
    private func assetSources() -> [EditorAssetBundle] {
        (try? self.readAssetBundles()) ?? []
    }

    /// The latest of `sources` that has `asset` under the same URL. That isn't always the site's latest
    /// bundle: a site can go back to an earlier manifest, whose assets only that manifest's bundle has.
    ///
    /// The scheme must match too. A bundle stores an asset by host, path and query, but a copy fetched over
    /// `http` shouldn't stand in for one requested over `https`.
    private func source(of asset: URL, in sources: [EditorAssetBundle]) -> EditorAssetBundle? {
        sources.first { $0.hasAssetData(for: asset) && $0.manifest.assetUrls.contains(asset) }
    }

    /// Copies each of `assets` that one of `sources` has into `draft`, and returns what it copied.
    private func carryForward(
        _ assets: [URL],
        from sources: [EditorAssetBundle],
        into draft: Draft
    ) -> CarriedAssets {
        var carried = CarriedAssets()

        for asset in assets {
            let destination = self.assetPath(for: asset, in: draft.bundle)

            // Skip assets the draft already has
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

                let key = EditorAssetBundle.assetKey(for: asset)
                carried.keys.insert(key)
                carried.headers[key] = source.headers(for: asset)
            } catch {
                // The copy failed, most likely because the source bundle was removed. Remove any partial
                // file, so the asset reads as missing.
                try? FileManager.default.removeItem(at: destination)
            }
        }

        return carried
    }

    /// What ``carryForward(_:from:into:)`` copied: the asset keys, and the headers of the assets that have
    /// any.
    private struct CarriedAssets {
        var keys: Set<String> = []
        var headers: [String: EditorAssetBundle.AssetHeaders] = [:]
    }

    /// Whether `url` has a non-empty `ver` query item, as WordPress adds to versioned assets.
    private func isVersioned(_ url: URL) -> Bool {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .contains { $0.name == "ver" && $0.value?.isEmpty == false } ?? false
    }

    /// Replaces each asset in `draft` that's identical to a copy in `sources`, under the same URL, with an APFS
    /// clone of that copy.
    ///
    /// The bytes are the same, but a clone shares the copy's disk space. So a refresh takes space only for the
    /// assets that changed, not for a whole bundle.
    private func shareUnchangedAssets(of draft: Draft, with sources: [EditorAssetBundle]) {
        for asset in self.downloadableAssets(in: draft.bundle.manifest) {
            let downloaded = self.assetPath(for: asset, in: draft.bundle)

            guard
                let source = self.source(of: asset, in: sources),
                FileManager.default.contentsEqual(
                    atPath: downloaded.path,
                    andPath: self.assetPath(for: asset, in: source).path
                )
            else {
                continue
            }

            // Clone beside the download, then swap it in. If the source bundle is removed mid-copy, the
            // download is left as it is.
            let clone = downloaded.appendingPathExtension("clone")
            do {
                try FileManager.default.copyItem(at: self.assetPath(for: asset, in: source), to: clone)
                _ = try FileManager.default.replaceItemAt(downloaded, withItemAt: clone)
            } catch {
                try? FileManager.default.removeItem(at: clone)
            }
        }
    }

    /// The assets in `manifest` that belong in its bundle: every HTTP or HTTPS link in its script and
    /// stylesheet tags, whatever the URL ends with.
    ///
    /// Each asset is listed once. A manifest can link the same asset twice, or over both `http` and `https`,
    /// which a bundle stores as one asset. The `https` link is preferred, because an `http` request may not be
    /// allowed at all.
    private func downloadableAssets(in manifest: LocalEditorAssetManifest) -> [URL] {
        if let assets = self.downloadableAssetsByManifest[manifest.checksum] {
            return assets
        }

        var assets: [URL] = []
        var positions: [String: Int] = [:]

        for link in manifest.scripts + manifest.styles where self.isDownloadable(link) {
            let key = EditorAssetBundle.assetKey(for: link)

            if let position = positions[key] {
                if assets[position].scheme != "https", link.scheme == "https" {
                    assets[position] = link
                }
            } else {
                positions[key] = assets.count
                assets.append(link)
            }
        }

        self.downloadableAssetsByManifest[manifest.checksum] = assets
        return assets
    }

    /// Downloads `assets` into `draft` concurrently, tolerating any that fail. Returns each downloaded
    /// asset's headers, keyed by asset key.
    private func downloadAssets(
        _ assets: [URL],
        into draft: Draft,
        reportingTo progress: EditorProgressCallback
    ) async throws -> [String: EditorAssetBundle.AssetHeaders] {
        var complete = 0
        var assetHeaders: [String: EditorAssetBundle.AssetHeaders] = [:]

        await withTaskGroup(of: (URL, EditorAssetBundle.AssetHeaders?).self) { group in
            for asset in assets {
                group.addTask {
                    do {
                        return (asset, try await self.fetchAsset(url: asset, into: draft))
                    } catch {
                        // Log and continue - individual asset failures shouldn't block the editor
                        // This handles cases like content blockers blocking analytics scripts
                        log(.warn, "Failed to download asset \(asset.lastPathComponent): \(error.localizedDescription)")
                        return (asset, nil)
                    }
                }
            }

            for await (asset, headers) in group {
                if let headers {
                    assetHeaders[EditorAssetBundle.assetKey(for: asset)] = headers
                }
                complete += 1
                await progress(EditorProgress(completed: complete, total: assets.count))
            }
        }

        // The group swallows every per-asset failure, cancellation included. Without this
        // check, a cancelled build would be published with assets missing, as if they had
        // failed to download.
        try Task.checkCancellation()

        return assetHeaders
    }

    /// Downloads a single asset into `draft`, and returns the headers its server sent with it.
    private func fetchAsset(url: URL, into draft: Draft) async throws -> EditorAssetBundle.AssetHeaders? {
        let request = self.assetRequest(for: url)

        let (tempUrl, response) = try await logExecutionTime("Downloading \(url.lastPathComponent)") {
            try await httpClient.download(request)
        }

        // This method owns the downloaded file. It's moved into the draft below; if anything fails
        // first, it's deleted.
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        let destinationPath = try self.destination(for: url, in: draft)
        let headers = EditorAssetBundle.AssetHeaders(response: response)

        // A server can return a web page with a success status, such as a login or error page. If it were
        // stored, the editor would be served it in place of the asset for as long as the bundle is used.
        guard !self.isWebPage(headers?.contentType) else {
            throw UnexpectedContentType(contentType: headers?.contentType ?? "")
        }

        try FileManager.default.moveItem(at: tempUrl, to: destinationPath)

        return headers
    }

    /// Whether `contentType` is `text/html`, which no script or stylesheet is.
    ///
    /// No other type is rejected. The editor is served each asset with the type it came with, so the web view
    /// handles it as it would if the site had served it directly.
    private func isWebPage(_ contentType: String?) -> Bool {
        let mediaType = contentType?
            .split(separator: ";", omittingEmptySubsequences: false).first?
            .trimmingCharacters(in: .whitespaces)
            .lowercased()

        return mediaType == "text/html"
    }

    /// A download that returned something other than the asset. `contentType` is the type the server sent.
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

    /// Where the asset at `url` is stored in `bundle`. The bundle decides, so the library writes each asset
    /// where the editor reads it.
    private func assetPath(for url: URL, in bundle: EditorAssetBundle) -> URL {
        bundle.assetDataPath(for: url)
    }

    /// The path to write the asset at `url` to in `draft`. Creates its parent directory.
    private func destination(for url: URL, in draft: Draft) throws -> URL {
        let destination = self.assetPath(for: url, in: draft.bundle)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return destination
    }

    /// The links in `manifest` that a bundle doesn't hold: the ones that aren't HTTP or HTTPS URLs.
    func linksLeftOut(of manifest: LocalEditorAssetManifest) -> [URL] {
        (manifest.scripts + manifest.styles).filter { !self.isDownloadable($0) }
    }

    /// Whether `url` can be downloaded into a bundle: an HTTP or HTTPS URL. It doesn't log rejected links;
    /// ``fetchManifest()`` does, once per new manifest.
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
    /// bundle handed out to the app since it launched: an open editor, or dependencies the
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

    /// The directory for a manifest's bundle. If a bundle is already there, a new one for the same manifest
    /// goes in `<checksum>-<UUID>` instead.
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
