import Foundation

/// The Editor Asset Library is a site-specific repository of remote assets that can be downloaded to the local device to support plugins and theme styles.
///
public actor EditorAssetLibrary {

    private let configuration: EditorConfiguration
    private let httpClient: EditorHTTPClientProtocol
    private let storageRoot: URL
    private let cachePolicy: EditorCachePolicy

    /// The assets of each manifest this library has been asked about, by the manifest's checksum. Working
    /// them out means reading every link in the manifest, and one prepare asks several times.
    private var downloadableAssetsByManifest: [String: [URL]] = [:]

    /// The bundles this library has already tried to copy into the layout a bundle has now. One prepare
    /// asks for the site's latest bundle several times, and a copy that couldn't be made once won't be
    /// the next time either.
    private var bundlesTriedInCurrentLayout: Set<URL> = []

    /// Bundle builds in flight, keyed by the directory named for the manifest each builds. Every
    /// service builds its own library, so this is shared across all of them.
    static let inFlightBuilds = InFlightTasks<URL, EditorAssetBundle>()

    /// Guards every change to a library's storage, along with `handedOut`. Every service builds
    /// its own library, so an actor's isolation doesn't order these between libraries.
    ///
    /// Storage changes in three ways and no others, each one step taken with this lock held:
    ///
    /// - ``publish(_:matchedAt:keptFrom:)`` moves a finished bundle in, already dated and handed out.
    ///   ``copyInCurrentLayout(of:missing:)`` moves in a copy of a bundle stored in an earlier layout,
    ///   which is handed out when a caller is given it: until then it's the site's latest, or no one's.
    /// - ``markLatest(_:matchedAt:recording:)`` rewrites the manifest of a bundle it has found still there.
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
            //
            // Two bundles only tie when one is a copy of the other in the layout a bundle has now, which
            // keeps the other's dates. The copy comes first: its directory has the other's name and more.
            .sorted {
                ($0.lastMatchedDate, $0.bundleRoot.lastPathComponent)
                    > ($1.lastMatchedDate, $1.bundleRoot.lastPathComponent)
            }
    }

    /// The latest bundle on disk, if there's no reason to check the site's manifest again.
    ///
    /// Returns `nil` when there is no bundle, when the site's manifest was last checked too long ago for the
    /// cache policy, or when the bundle is missing assets, which another try may download. In each case, call
    /// ``downloadAssetBundle(progress:)`` next to check.
    ///
    /// A bundle that holds an earlier copy of an asset that failed to download is returned all the same:
    /// it has everything an editor loads. That asset is asked for again when the manifest is next checked.
    public func readLatestAssetBundle() throws -> EditorAssetBundle? {
        guard let latest = try self.latestBundleWithinPolicy(), latest.missingAssets.isEmpty else {
            return nil
        }

        return self.handOut(latest.bundle)
    }

    /// The latest bundle on disk if the site's manifest was checked recently enough for the cache policy,
    /// and whether it's missing assets.
    ///
    /// It's the bundle the policy asks for, and no more than that. Trying its missing assets again is worth
    /// asking the site for, but the bundle doesn't depend on the answer. It isn't handed out: that's for
    /// ``handOut(_:)``, once a caller is to be given it.
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

    /// The latest bundle on disk, however long ago the site's manifest was checked and whether or not it has
    /// every asset: what there is to use when the site can't be asked.
    func readLatestAssetBundleOnDisk() throws -> EditorAssetBundle? {
        try self.latestBundle().flatMap { self.handOut($0.bundle) }
    }

    /// The site's latest bundle on disk, with its assets where a bundle keeps them now, and the assets it's
    /// missing. Everything that wants the site's latest bundle comes through here.
    private func latestBundle() throws -> (bundle: EditorAssetBundle, missingAssets: [URL])? {
        guard let latestBundle = try self.readAssetBundles().first else {
            return nil
        }

        let missingAssets = self.missingAssets(of: latestBundle)

        guard let copy = self.copyInCurrentLayout(of: latestBundle, missing: missingAssets) else {
            return (latestBundle, missingAssets)
        }

        return (copy, self.missingAssets(of: copy))
    }

    /// A copy of `bundle`, the site's latest, with its assets where a bundle keeps them now. `nil` if it has
    /// none to move, and `bundle` is as good as it gets.
    ///
    /// A bundle used to keep each asset at its URL's path, where nothing looks for it any more. Left at
    /// that, the bundle would read as missing every asset: all of them to download again, and none to give
    /// an editor until the site could be reached. So the assets found there are copied, in a new bundle
    /// beside the old one, which is left as it was. The copy keeps the old bundle's dates, because the site
    /// hasn't been asked anything. And it records each asset it copies as one that wasn't refreshed: an
    /// earlier bundle's copy, to use until the site's manifest is next checked, and to ask for again then.
    /// Such a bundle kept whatever a site answered with, and none of what's kept with an asset now.
    private func copyInCurrentLayout(of bundle: EditorAssetBundle, missing missingAssets: [URL]) -> EditorAssetBundle? {
        let assetsToCopy = self.assetsInEarlierLayout(of: bundle, missing: missingAssets)

        guard !assetsToCopy.isEmpty, self.bundlesTriedInCurrentLayout.insert(bundle.bundleRoot).inserted else {
            return nil
        }

        do {
            var draft = try Draft(manifest: bundle.manifest, downloadDate: bundle.downloadDate)

            // Once it's placed, a draft has left its directory, and there's nothing of it to remove
            defer { draft.discard() }

            let editorRepresentation: EditorAssetBundle.EditorRepresentation = try bundle.getEditorRepresentation()
            try draft.bundle.writeManifest(editorRepresentation: editorRepresentation)

            // What the bundle already keeps in today's layout, then what it kept in the earlier one
            let assetHeaders = self.carryForward(
                self.downloadableAssets(in: bundle.manifest),
                from: [bundle],
                whetherOrNotRefreshed: true,
                into: draft
            ).headers

            // One that can't be copied is one asset to download, not a reason to leave the rest
            let copied = assetsToCopy.filter { asset in
                guard let location = bundle.legacyAssetLocation(for: asset) else {
                    return false
                }

                do {
                    try FileManager.default.copyItem(at: location, to: self.destination(for: asset, in: draft))
                    return true
                } catch {
                    log(.warn, "Failed to copy asset \(asset.lastPathComponent): \(error.localizedDescription)")
                    return false
                }
            }

            guard !copied.isEmpty else {
                return nil
            }

            try draft.record(
                assetHeaders: assetHeaders,
                assetsNotRefreshed: bundle.assetsNotRefreshed
                    .union(copied.map { EditorAssetBundle.assetKey(for: $0) }),
                lastCheckedDate: bundle.lastCheckedDate
            )

            return try Self.storageLock.withLock {
                let latestBundle = try self.readAssetBundles().first

                // Another library may have made the copy, or built another bundle, in the meantime
                guard latestBundle?.bundleRoot == bundle.bundleRoot else {
                    return latestBundle
                }

                return try self.place(draft, asCopyOf: bundle)
            }
        } catch {
            log(.warn, "Failed to copy asset bundle \(bundle.id) into the current layout: \(error.localizedDescription)")

            // The bundle is as usable as it was, if it's still the latest: its assets are just asked for
            // again. If it isn't, the latest is whatever took its place.
            let latestBundle = try? self.readAssetBundles().first
            return latestBundle?.bundleRoot == bundle.bundleRoot ? nil : latestBundle
        }
    }

    /// The assets `bundle` is missing that it holds where a bundle used to keep them: at their URL's path.
    ///
    /// A bundle kept one file there for every asset with that path, whichever host or query each was asked
    /// for by. Where its manifest has more than one, there's no telling which of them the file holds, so
    /// it's taken for none of them, and they're downloaded.
    private func assetsInEarlierLayout(of bundle: EditorAssetBundle, missing missingAssets: [URL]) -> [URL] {
        let assets = missingAssets.filter { bundle.legacyAssetLocation(for: $0) != nil }

        guard !assets.isEmpty else {
            return []
        }

        // By the file each leads to, which two paths written differently can share. Capitals are left
        // out of it, since not every volume tells them apart.
        let file = { (asset: URL) in bundle.legacyAssetLocation(for: asset)?.path.lowercased() }
        let assetsByFile = Dictionary(grouping: self.downloadableAssets(in: bundle.manifest), by: file)

        return assets.filter { assetsByFile[file($0)]?.count == 1 }
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
    /// Under `.always` and `.maxAge`, only what the manifest says has changed is downloaded. If a bundle built
    /// from the same manifest is already on disk, it's returned instead, without downloading its assets again:
    /// they're versioned by URL, so an unchanged manifest means unchanged assets. Only an asset that an earlier
    /// build failed to download is tried again, in a new bundle beside that one. If the manifest has changed,
    /// the new bundle takes each asset whose versioned URL (`?ver=`) a bundle on disk already has from that
    /// bundle, and downloads the rest.
    /// That trusts the site's versions: WordPress gives an asset registered without a version its own, so
    /// such a file can change while its URL doesn't, and only `.ignore` downloads it again. An asset without
    /// a version is asked for again, but only for a newer copy if its server sent an `ETag` or `Last-Modified`
    /// with the one on disk.
    ///
    /// Under `.ignore`, every asset is downloaded whether or not the manifest has changed, into a new bundle: a
    /// bundle already on disk is never changed, because an editor may be reading it. If the manifest hasn't
    /// changed and its assets all come back the same as the bundle on disk has them, that bundle is returned
    /// instead.
    ///
    /// Under every policy, an asset that fails to download is taken from the latest bundle on disk that has
    /// it, and the bundle records that it wasn't downloaded: ``assetsNotRefreshed(in:)`` lists it, and it's
    /// asked for again the next time the site's manifest is checked, whether or not its URL has a version.
    ///
    /// Either way the bundle is dated by when the manifest was fetched, however long it then takes to build:
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
    /// A manifest can have more than one: each download under `.ignore` that changes a manifest's assets leaves
    /// a bundle of its own. This is the one the site's manifest last matched.
    func existingBundle(forManifestChecksum checksum: String) -> EditorAssetBundle? {
        // Every bundle is in a directory named for its manifest's checksum, alone or with more after it
        try? self.readAssetBundles { $0.hasPrefix(checksum) }.first { $0.id == checksum }
    }

    // MARK: - Individual Asset Handling

    /// Downloads all of the assets for a given manifest and assembles them into a bundle.
    ///
    /// Unless the cache policy is `.ignore`, assets a bundle on disk already has are copied
    /// from it. The rest are downloaded concurrently, all into a temporary directory. Once all
    /// downloads complete successfully, the bundle is atomically moved into the library's storage. If
    /// a bundle for the manifest is already there with every asset downloaded, it's returned instead.
    /// If one is there with assets that failed to download, they're tried again in a new bundle beside
    /// it, which is only kept if its assets come out different. Under `.ignore`, the bundle is built
    /// again regardless. Either way, the bundle returned is marked as matching the site's manifest at
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

        // A bundle stored in an earlier layout has assets this build can fall back on, once they're
        // where a bundle keeps them now.
        _ = try? self.latestBundle()

        // A build under `.ignore` joins no build in flight, not even another under `.ignore`: what's
        // asked for is every asset as it is from now on, and a build already under way may have
        // downloaded some of them before that.
        if case .ignore = self.cachePolicy {
            return try await self.buildFreshBundle(for: manifest, fetchedAt: manifestFetchDate) { await progress?($0) }
        }

        // Every other build of one manifest does the same work, whichever library runs it: join a
        // build in flight rather than download it all a second time.
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

    /// Returns the bundle on disk for `manifest` if it has every asset downloaded, and otherwise builds one.
    ///
    /// The bundle on disk is looked for here, inside the build that callers share, so that a build
    /// finishing in between is reused.
    private func reuseOrBuildBundle(
        for manifest: LocalEditorAssetManifest,
        fetchedAt manifestFetchDate: Date,
        reportingTo progress: EditorProgressCallback
    ) async throws -> EditorAssetBundle {
        // Another library can put a bundle for this manifest in storage while this one works: a build
        // under `.ignore` doesn't share this one. What was found or built here is then out of date,
        // and marking or publishing it would put it back in front of the newer bundle. So the
        // manifest's bundle is looked for again: once for each bundle published in the meantime.
        while true {
            let existingBundle = self.existingBundle(forManifestChecksum: manifest.checksum)

            if let existingBundle, self.assetsToTryAgain(of: existingBundle).isEmpty {
                await progress(EditorProgress(completed: 1, total: 1))

                // A `cleanup()` or `purge()` can also delete the bundle after it's found here, in
                // which case there is nothing to reuse after all.
                if let latestBundle = self.markLatest(existingBundle, matchedAt: manifestFetchDate) {
                    return latestBundle
                }

                continue
            }

            // A bundle on disk with assets that failed to download is left as it is: an editor may
            // be reading it. The build takes what that bundle downloaded and tries the rest again.
            let draft = try await self.build(manifest, keepingAssetsOf: existingBundle, reportingTo: progress)

            if let bundle = try self.publish(draft, matchedAt: manifestFetchDate, unlessSameAs: existingBundle) {
                return bundle
            }

            draft.discard()
        }
    }

    /// Builds a bundle for `manifest` with every asset downloaded now, which is what `.ignore` asks for.
    ///
    /// The bundle goes beside the one the manifest already has rather than over it: a bundle on disk is never
    /// changed, because an editor may be reading it. It has no build to join: one under another policy
    /// doesn't download everything, and another under `.ignore` began before this was asked for. Of two
    /// that overlap, the one that finishes last is the site's latest.
    ///
    /// If the assets all come back the same as the manifest's bundle on disk has them, that bundle is still
    /// right, so it's returned instead and the new one is discarded. That keeps a refresh that changed
    /// nothing from costing disk space, or looking like a change to a host comparing dependencies.
    private func buildFreshBundle(
        for manifest: LocalEditorAssetManifest,
        fetchedAt manifestFetchDate: Date,
        reportingTo progress: EditorProgressCallback
    ) async throws -> EditorAssetBundle {
        let draft = try await self.build(manifest, reportingTo: progress)

        // The draft kept nothing from the bundle on disk, so it's as good against whichever bundle the
        // manifest has by now. If another library publishes one in between, it's compared with that.
        while true {
            let existingBundle = self.existingBundle(forManifestChecksum: manifest.checksum)

            if let bundle = try self.publish(draft, matchedAt: manifestFetchDate, unlessSameAs: existingBundle) {
                return bundle
            }
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

        /// The keys of the assets the draft took as they were from the bundle on disk for its manifest,
        /// because the manifest hasn't changed. The build learned nothing about these: each is a copy of
        /// that bundle's file, and that bundle is what knows about it.
        var assetsKeptFromExistingBundle: Set<String> = []

        /// Starts a draft of the bundle for `manifest`, in a temporary directory of its own.
        init(manifest: LocalEditorAssetManifest, downloadDate: Date = Date()) throws {
            self.bundle = try EditorAssetBundle(
                manifest: manifest,
                downloadDate: downloadDate,
                bundleRoot: URL.temporaryDirectory.appending(path: UUID().uuidString)
            )
        }

        /// Writes the draft's manifest again, with what's been learned since it was started: its assets'
        /// headers, which of them failed to download, and, for a draft about to be published, when the
        /// site's manifest last matched it.
        mutating func record(
            assetHeaders: [String: EditorAssetBundle.AssetHeaders],
            assetsNotRefreshed: Set<String>,
            lastCheckedDate: Date? = nil
        ) throws {
            self.bundle = self.bundle.recording(
                lastCheckedDate: lastCheckedDate,
                assetHeaders: assetHeaders,
                assetsNotRefreshed: assetsNotRefreshed
            )
            try self.bundle.writeManifest()
        }

        /// Removes the draft's directory, for a draft that won't be published.
        func discard() {
            try? FileManager.default.removeItem(at: self.bundle.bundleRoot)
        }
    }

    /// Puts `draft` in the library's storage as the site's latest bundle — unless `existingBundle`, the bundle
    /// on disk for the same manifest, already holds the same assets.
    ///
    /// Then that bundle is still right, so it's kept as the latest and the draft is discarded: a build
    /// that changed nothing costs no disk space. What the build learned is still recorded in the bundle
    /// it keeps: the headers its assets come with now, and which of them failed to download.
    ///
    /// `existingBundle` must be the bundle the draft kept assets from, if it kept any. Returns `nil`, with
    /// the draft left as it is, if `existingBundle` is no longer the manifest's latest bundle on disk.
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

    /// Moves `draft` into the library's storage, as one the site's manifest matched at `matchDate` and one
    /// that's been handed out.
    ///
    /// It's all one step for anything else that changes storage: there is no moment when the bundle is there
    /// and a `cleanup()` could take it for one nobody is using. And it's a move, into a directory that didn't
    /// exist, so nothing sees the bundle half there and no bundle on disk is written over.
    ///
    /// `existingBundle` is the manifest's bundle on disk as the build found it, if it found one. Returns
    /// `nil`, with the draft left as it is, if another library has put a bundle for the manifest in storage
    /// since: the draft was made without it.
    private func publish(
        _ draft: Draft,
        matchedAt matchDate: Date,
        keptFrom existingBundle: EditorAssetBundle?
    ) throws -> EditorAssetBundle? {
        var draft = draft

        do {
            return try Self.storageLock.withLock {
                // The manifest's latest bundle on disk, as it's recorded at this moment. If there is
                // one and it isn't `existingBundle`, another library has published it since.
                let recorded = self.existingBundle(forManifestChecksum: draft.bundle.id)

                guard recorded == nil || recorded?.bundleRoot == existingBundle?.bundleRoot else {
                    return nil
                }

                let record = self.assetRecord(from: draft, keptFrom: recorded)

                // The bundle replaces the one the manifest has on disk, so it has to come ahead of it.
                // Another library may have found the manifest to match more recently than this build
                // fetched it, and recorded that in the bundle on disk: this one is dated just after.
                let matchDate = recorded.map { max(matchDate, $0.lastMatchedDate.addingTimeInterval(0.001)) } ?? matchDate

                // Marked before it's moved, while nothing else can see it
                try draft.record(
                    assetHeaders: record.assetHeaders,
                    assetsNotRefreshed: record.assetsNotRefreshed,
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

    /// What a bundle records about its assets: the headers each came with, and which of them failed to
    /// download.
    private typealias AssetRecord = (
        assetHeaders: [String: EditorAssetBundle.AssetHeaders], assetsNotRefreshed: Set<String>
    )

    /// What `draft` gives a bundle to record about its assets.
    ///
    /// The build found that out for every asset but the ones it kept from the bundle on disk for its
    /// manifest, without asking for them. For those it's what that bundle records now, which is `recorded`
    /// — not what it recorded when the build read it, which another library may have changed since.
    private func assetRecord(from draft: Draft, keptFrom recorded: EditorAssetBundle?) -> AssetRecord {
        var assetHeaders = draft.bundle.assetHeaders
        var assetsNotRefreshed = draft.bundle.assetsNotRefreshed

        if let recorded {
            for key in draft.assetsKeptFromExistingBundle {
                assetHeaders[key] = recorded.assetHeaders[key]

                if recorded.assetsNotRefreshed.contains(key) {
                    assetsNotRefreshed.insert(key)
                }
            }
        }

        return (assetHeaders, assetsNotRefreshed)
    }

    /// Moves `draft` into the library's storage as it stands. Call it with `storageLock` held.
    ///
    /// The bundle isn't recorded as handed out: that's for whoever gives it to a caller.
    ///
    /// A copy of `original` in the layout a bundle has now goes in a directory with the original's name and
    /// more: with the same dates, that's what puts the copy first in ``readAssetBundles()``.
    private func place(_ draft: Draft, asCopyOf original: EditorAssetBundle? = nil) throws -> EditorAssetBundle {
        try FileManager.default.createDirectory(at: self.storageRoot, withIntermediateDirectories: true)

        // The manifest's own directory, unless something is already there
        var destination = self.bundleRoot(for: draft.bundle.id)
        if let original {
            let name = "\(original.bundleRoot.lastPathComponent)-\(UUID().uuidString)"
            destination = self.storageRoot.appending(path: name)
        } else if FileManager.default.fileExists(atPath: destination.path) {
            destination = self.storageRoot.appending(path: "\(draft.bundle.id)-\(UUID().uuidString)")
        }

        try FileManager.default.moveItem(at: draft.bundle.bundleRoot, to: destination)

        return try EditorAssetBundle(url: self.bundleManifestPath(relativeTo: destination))
    }

    /// Whether `draft` holds the same assets as `other`, a bundle of the same manifest: each either missing
    /// from both, or identical.
    ///
    /// An asset the draft kept from `other` is a copy of the file there, so it's only looked for.
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

    /// Downloads whichever of `draft`'s assets aren't in it yet: every asset that wasn't carried forward.
    ///
    /// Returns the headers each downloaded asset's server sent with it, by the asset's key.
    private func downloadMissingAssets(
        of draft: Draft,
        unlessSameAsIn sources: [EditorAssetBundle] = [],
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

    /// The assets `bundle` should have that aren't on disk: the ones that failed to download, with no copy on
    /// disk to take their place.
    func missingAssets(of bundle: EditorAssetBundle) -> [URL] {
        self.downloadableAssets(in: bundle.manifest)
            .filter { !FileManager.default.fileExists(at: self.assetPath(for: $0, in: bundle)) }
    }

    /// The assets `bundle` holds an earlier bundle's copy of: the ones that failed to download when it was
    /// built, with a copy on disk to take their place.
    func assetsNotRefreshed(in bundle: EditorAssetBundle) -> [URL] {
        guard !bundle.assetsNotRefreshed.isEmpty else {
            return []
        }

        return self.downloadableAssets(in: bundle.manifest).filter {
            bundle.assetsNotRefreshed.contains(EditorAssetBundle.assetKey(for: $0)) && bundle.hasAssetData(for: $0)
        }
    }

    /// The assets of `bundle` that failed to download, whether or not a copy on disk took their place. A
    /// check of the site's manifest that finds the bundle still matches asks for these again.
    private func assetsToTryAgain(of bundle: EditorAssetBundle) -> [URL] {
        self.missingAssets(of: bundle) + self.assetsNotRefreshed(in: bundle)
    }

    /// Records that the site's manifest matched `bundle` at `matchDate`, and that the bundle has been handed
    /// out. That makes it the site's latest bundle, unless the site has been found to have another manifest
    /// since then, and starts its age for the cache policy from then.
    ///
    /// Returns `nil` if the bundle is no longer on disk, or is no longer its manifest's latest bundle there:
    /// another library has published one since, and marking this one would put it back in front.
    ///
    /// `draft`, if there is one, is a build of the same manifest that came out with the same assets. What it
    /// learned about them is recorded too. Otherwise the bundle keeps what it records on disk at this moment
    /// — not what `bundle` had when it was read, which another library may have changed since.
    private func markLatest(
        _ bundle: EditorAssetBundle,
        matchedAt matchDate: Date,
        recording draft: Draft? = nil
    ) -> EditorAssetBundle? {
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

            let record: AssetRecord =
                draft.map { self.assetRecord(from: $0, keptFrom: recorded) }
                ?? (recorded.assetHeaders, recorded.assetsNotRefreshed)

            // Another library may have found the manifest to match more recently than this one did,
            // and recorded it first
            let latestBundle = bundle.recording(
                lastCheckedDate: max(recorded.lastMatchedDate, matchDate),
                assetHeaders: record.assetHeaders,
                assetsNotRefreshed: record.assetsNotRefreshed
            )

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
    /// ``publish(_:matchedAt:unlessSameAs:)``. A build that fails discards the draft itself.
    ///
    /// `existingBundle` is the bundle on disk for this same manifest, if there is one and the cache policy
    /// isn't `.ignore`: the manifest hasn't changed, so the draft keeps every asset that bundle downloaded.
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
                // Only a versioned URL is taken to mean the same file, and copied without asking. One
                // without a version can change without its URL saying so: the site is asked for it,
                // though only for a newer copy when its server said how to tell one from another.
                //
                // A bundle already on disk for this manifest is the exception: the manifest hasn't
                // changed, so the bundle keeps every asset it downloaded, and only the rest are asked
                // for.
                let assets = self.downloadableAssets(in: manifest)

                if let existingBundle {
                    let unchanged = self.carryForward(assets, from: [existingBundle], into: draft)
                    assetHeaders.merge(unchanged.headers) { $1 }
                    draft.assetsKeptFromExistingBundle = unchanged.keys
                }

                let versioned = self.carryForward(assets.filter { self.isVersioned($0) }, from: sources, into: draft)
                assetHeaders.merge(versioned.headers) { $1 }

                let downloaded = try await self.downloadMissingAssets(
                    of: draft,
                    unlessSameAsIn: sources,
                    reportingTo: progress
                )
                assetHeaders.merge(downloaded) { $1 }
            case .ignore:
                // Takes nothing on disk as valid, so every asset is downloaded in full.
                assetHeaders = try await self.downloadMissingAssets(of: draft, reportingTo: progress)
            }

            // An asset that fails to download has no better copy than one already on disk, which
            // beats a gap. The bundle records that it holds one, so that the failure isn't hidden
            // behind the copy, and the asset is asked for again when the manifest is next checked.
            let failed = self.missingAssets(of: draft.bundle)
            let kept = self.carryForward(failed, from: sources, whetherOrNotRefreshed: true, into: draft)
            assetHeaders.merge(kept.headers) { $1 }

            try draft.record(assetHeaders: assetHeaders, assetsNotRefreshed: kept.keys)
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
    /// The same URL, scheme included: a bundle keeps an asset by its host, path and query, but a copy that
    /// came over `http` isn't one to take in place of asking over `https`.
    private func source(of asset: URL, in sources: [EditorAssetBundle]) -> EditorAssetBundle? {
        sources.first { $0.hasAssetData(for: asset) && $0.manifest.assetUrls.contains(asset) }
    }

    /// Copies into `draft` each of `assets` that one of `sources` has, and returns which it copied.
    ///
    /// A copy that stands in for an asset that failed to download isn't one to carry on as though it had
    /// downloaded: the asset is left for the build to ask for again. `whetherOrNotRefreshed` takes it
    /// anyway, for when asking has failed, or nothing is being asked.
    private func carryForward(
        _ assets: [URL],
        from sources: [EditorAssetBundle],
        whetherOrNotRefreshed: Bool = false,
        into draft: Draft
    ) -> CarriedAssets {
        var carried = CarriedAssets()

        for asset in assets {
            let destination = self.assetPath(for: asset, in: draft.bundle)

            // An asset the draft already has stays as it is
            guard
                !FileManager.default.fileExists(at: destination),
                let source = self.source(of: asset, in: sources),
                whetherOrNotRefreshed || !source.assetsNotRefreshed.contains(EditorAssetBundle.assetKey(for: asset))
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
                // The bundle has been removed since. Leave nothing behind, so that it reads as missing.
                try? FileManager.default.removeItem(at: destination)
            }
        }

        return carried
    }

    /// The assets a carry copied into a draft: their keys, and the headers that came with the ones that
    /// have any.
    private struct CarriedAssets {
        var keys: Set<String> = []
        var headers: [String: EditorAssetBundle.AssetHeaders] = [:]
    }

    /// Whether `url` carries a version the way WordPress adds one: a `ver` in its query.
    private func isVersioned(_ url: URL) -> Bool {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .contains { $0.name == "ver" && $0.value?.isEmpty == false } ?? false
    }

    /// The assets in `manifest` that belong in its bundle: every link that one of its script or stylesheet
    /// tags loads over HTTP. The tag is what makes a link an asset, however its URL ends.
    ///
    /// Each is listed once. A manifest can link one asset twice, or under two URLs that a bundle keeps as
    /// one — over `http` and over `https` — and it's one file to download either way. The `https` link is
    /// the one to ask for: over `http`, the request may not be allowed at all.
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

    /// Downloads `assets` into `draft` concurrently, tolerating any that fail. Returns the headers each
    /// one's server sent with it, by the asset's key.
    private func downloadAssets(
        _ assets: [URL],
        into draft: Draft,
        unlessSameAsIn sources: [EditorAssetBundle],
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
                if let headers {
                    assetHeaders[EditorAssetBundle.assetKey(for: asset)] = headers
                }
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
        unlessSameAsIn sources: [EditorAssetBundle]
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

        let destinationPath = try self.destination(for: url, in: draft)

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

    /// Where `draft` keeps the asset at `url`, in a directory that's there to write it into.
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
