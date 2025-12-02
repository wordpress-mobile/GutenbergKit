import Foundation
import CryptoKit
import SwiftSoup
import OSLog

/// Service for fetching the editor settings and other parts of the environment
/// required to launch the editor.
actor EditorService {
    internal struct State: Codable {
        let refreshDate: Date
    }

    @MainActor private static var instances: [String: EditorService] = [:]

    private let siteURL: String
    private let networkSession: URLSessionProtocol

    private let storeURL: URL
    private var editorSettingsFileURL: URL { storeURL.appendingPathComponent("settings.json") }
    private var manifestOriginalFileURL: URL { storeURL.appendingPathComponent("manifest-original.json") }
    private var manifestProcessedFileURL: URL { storeURL.appendingPathComponent("manifest-processed.json") }
    private var stateFileURL: URL { storeURL.appendingPathComponent("state.json") }
    private var assetsDirectoryURL: URL { storeURL.appendingPathComponent("assets", isDirectory: true) }

    private var refreshTask: Task<Void, Never>?

    /// Returns the shared EditorService instance for the given siteURL
    @MainActor
    static func shared(for siteURL: String) -> EditorService {
        if let existing = instances[siteURL] {
            return existing
        }
        let service = EditorService(siteURL: siteURL, networkSession: URLSession.shared)
        instances[siteURL] = service
        return service
    }

    /// Creates a new EditorService instance for testing
    /// - Parameters:
    ///   - siteURL: Unique identifier for the site (used for caching)
    ///   - storeURL: Custom store URL for testing
    ///   - networkSession: Network session to use for network requests
    init(siteURL: String, storeURL: URL? = nil, networkSession: URLSessionProtocol) {
        self.siteURL = siteURL
        self.networkSession = networkSession
        self.storeURL = storeURL ?? EditorService.rootURL
            .appendingPathComponent(siteURL.sha1, isDirectory: true)

        Task {
            await scheduleAutomaticCleanup()
        }
    }

    /// Schedules automatic cleanup of orphaned assets after a brief delay.
    ///
    /// This is safe to call during initialization because:
    /// - No previous editor instance can be accessing orphaned files at this point
    /// - The delay ensures initialization completes before cleanup starts
    /// - Any errors are caught and logged, preventing initialization failures
    private func scheduleAutomaticCleanup() {
        Task {
            // Brief delay to allow service initialization to complete
            try? await Task.sleep(for: .seconds(5))

            do {
                try await cleanupOrphanedAssets()
            } catch {
                log(.error, "Automatic cleanup failed: \(error)")
            }
        }
    }

    private static var rootURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("GutenbergKit", isDirectory: true)
    }

    /// Returns the editor dependencies for the given configuration.
    ///
    /// - warning: The request may take a significant amount of time the first
    /// time you open the editor.
    func dependencies(for configuration: EditorConfiguration, isWarmup: Bool = false) async -> EditorDependencies {
        let startTime = CFAbsoluteTimeGetCurrent()

        if !isEditorLoaded {
            await refresh(configuration: configuration)
        } else {
            // Trigger a background refresh after a delay to avoid interfering with editor loading
            Task {
                if !isWarmup {
                    try? await Task.sleep(for: .seconds(7))
                }
                if isRefreshNeeded() {
                    log(.info, "Refresh scheduled for later")
                    await refresh(configuration: configuration)
                } else {
                    log(.info, "Skipping refresh – data is fresh")
                }
            }
        }

        log(.info, "Prepping local dependencies")
        var dependencies = EditorDependencies()
        if let data = try? Data(contentsOf: editorSettingsFileURL),
           let settings = String(data: data, encoding: .utf8) {
            dependencies.editorSettings = settings
        }
        let loadTime = CFAbsoluteTimeGetCurrent() - startTime
        log(.info, "Loaded dependencies in \(String(format: "%.3f", loadTime))s")

        return dependencies
    }

    /// Returns `true` if the resources required for the editor already exist.
    private var isEditorLoaded: Bool {
        FileManager.default.fileExists(atPath: stateFileURL.path)
    }

    /// Refresh the editor resources.
    func refresh(configuration: EditorConfiguration) async {
        if let task = refreshTask {
            return await task.value
        }
        let task = Task {
            defer { refreshTask = nil }
            await actuallyRefresh(configuration: configuration)
        }
        refreshTask = task
        return await task.value
    }

    private func isRefreshNeeded() -> Bool {
        guard let data = try? Data(contentsOf: stateFileURL),
              let state = try? JSONDecoder().decode(State.self, from: data) else {
            return true
        }
        let timeSinceLastRefresh = Date().timeIntervalSince(state.refreshDate)
        return timeSinceLastRefresh > 30
    }

    private func actuallyRefresh(configuration: EditorConfiguration) async {
        let startTime = CFAbsoluteTimeGetCurrent()
        log(.info, "Starting editor resources refresh")

        guard let baseURL = URL(string: configuration.siteApiRoot) else {
            log(.error, "Invalid siteApiRoot URL: \(configuration.siteApiRoot)")
            return
        }

        // Fetch settings and manifest in parallel
        async let settingsFuture = Result {
            try await fetchEditorSettings(baseURL: baseURL, authHeader: configuration.authHeader)
        }
        async let manifestFuture = Result {
            try await fetchManifestData(configuration: configuration)
        }

        let (settingsResult, manifestResult) = await (settingsFuture, manifestFuture)

        let fetchTime = CFAbsoluteTimeGetCurrent() - startTime
        log(.info, "Fetched settings and manifest in \(String(format: "%.2f", fetchTime))s")

        if case .failure(let error) = settingsResult {
            log(.error, "Failed to fetch editor settings: \(error)")
        }

        switch manifestResult {
        case .success(let manifest):
            // Fetch all assets for the new manifest
            do {
                try await fetchAssets(manifestData: manifest)

                // Only write both manifest versions to disk after all assets are successfully fetched
                FileManager.default.createDirectoryIfNeeded(at: storeURL)
                try saveManifest(originalData: manifest)
                log(.info, "Saved manifest")
            } catch {
                log(.error, "Failed to fetch assets: \(error) – skipping the manifest")
            }
        case .failure(let error):
            log(.error, "Failed to fetch manifest: \(error)")
        }

        // Save state to indicate completed refresh (even if it fails)
        do {
            let state = State(refreshDate: Date())
            try JSONEncoder().encode(state).write(to: stateFileURL)
        } catch {
            log(.error, "Failed to save state: \(error)")
        }

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        log(.info, "Editor refresh completed in \(String(format: "%.2f", totalTime))s")
    }

    // MARK: – Editor Settings

    /// Fetches block editor settings from the WordPress REST API
    ///
    /// - Returns: Raw settings data from the API
    @discardableResult
    private func fetchEditorSettings(baseURL: URL, authHeader: String) async throws -> Data {
        let data = try await fetchData(for: baseURL.appendingPathComponent("/wp-block-editor/v1/settings"), authHeader: authHeader)
        do {
            FileManager.default.createDirectoryIfNeeded(at: storeURL)
            try data.write(to: editorSettingsFileURL)
        } catch {
            assertionFailure("Failed to save settings: \(error)")
        }
        return data
    }

    // MARK: - Assets Manifest

    /// Fetches the editor assets manifest from the WordPress REST API
    /// Does not write to disk - use this to get manifest data without persisting it
    private func fetchManifestData(configuration: EditorConfiguration) async throws -> Data {
        let endpoint = try configuration.editorAssetsManifestEndpoint()
        let data = try await fetchData(for: endpoint, authHeader: configuration.authHeader)
        return data
    }

    /// Saves both original and processed manifest to disk
    private func saveManifest(originalData: Data) throws {
        // Save original manifest
        try originalData.write(to: manifestOriginalFileURL)

        // Process and save processed manifest
        let manifest = try JSONDecoder().decode(EditorAssetsManifest.self, from: originalData)
        let siteURLScheme = URL(string: siteURL)?.scheme
        let processedData = try manifest.renderForEditor(defaultScheme: siteURLScheme)
        try processedData.write(to: manifestProcessedFileURL)
    }

    /// Loads the processed manifest from disk
    private func loadProcessedManifest() throws -> String {
        let data = try Data(contentsOf: manifestProcessedFileURL)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return jsonString
    }

    /// Returns the processed manifest for use by the editor
    func getProcessedManifest() throws -> String {
        try loadProcessedManifest()
    }

    // MARK: - Assets

    /// Removes assets that are no longer referenced in the current manifest.
    ///
    /// This method is safe to call at any time, but is typically called automatically
    /// shortly after service initialization. At that point, no previous editor instance
    /// can be referencing orphaned files, making it safe to delete them immediately.
    func cleanupOrphanedAssets() async throws {
        // Load current manifest to determine which assets should be retained
        guard FileManager.default.fileExists(atPath: manifestOriginalFileURL.path) else {
            log(.warn, "No manifest found, skipping cleanup")
            return
        }

        let manifestData = try Data(contentsOf: manifestOriginalFileURL)
        let manifest = try JSONDecoder().decode(EditorAssetsManifest.self, from: manifestData)
        let currentAssetLinks = try manifest.parseAssetLinks()
            .filter { isSupportedAsset($0) }

        // Build set of expected filenames
        let expectedFilenames = Set(currentAssetLinks.map { cachedFilename(for: $0) })

        // Get all files in assets directory
        guard FileManager.default.fileExists(atPath: assetsDirectoryURL.path) else {
            log(.debug, "Assets directory doesn't exist, nothing to clean up")
            return
        }

        let filesOnDisk = try FileManager.default.contentsOfDirectory(
            at: assetsDirectoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        // Identify and delete orphaned files
        var deletedCount = 0
        var deletedSize: Int64 = 0

        for fileURL in filesOnDisk {
            let filename = fileURL.lastPathComponent

            // Skip if file is referenced in current manifest
            if expectedFilenames.contains(filename) {
                continue
            }

            // Delete orphaned asset
            try? FileManager.default.removeItem(at: fileURL)
            deletedCount += 1
            deletedSize += fileURL.fileSize
        }

        if deletedCount > 0 {
            log(.info, "Cleaned up \(deletedCount) orphaned assets (\(deletedSize.formatted))")
        } else {
            log(.debug, "No orphaned assets to clean up")
        }
    }

    /// Fetches all assets from the manifest and stores them on the device
    private func fetchAssets(manifestData: Data) async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        let manifest = try JSONDecoder().decode(EditorAssetsManifest.self, from: manifestData)
        let assetLinks = try manifest.parseAssetLinks()
            .filter { isSupportedAsset($0) }

        log(.info, "Found \(assetLinks.count) assets to fetch")

        FileManager.default.createDirectoryIfNeeded(at: assetsDirectoryURL)

        var assetURLs: [URL] = []
        var lastError: Error?

        // Fetch all assets in parallel
        await withTaskGroup(of: Result<URL, Error>.self) { group in
            for link in assetLinks {
                group.addTask {
                    await Result { try await self.fetchAsset(from: link) }
                }
            }

            for await result in group {
                switch result {
                case .success(let url):
                    assetURLs.append(url)
                case .failure(let error):
                    log(.error, "Failed to fetch asset: \(error)")
                    lastError = error
                }
            }
        }

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        let totalSize = assetURLs.reduce(0) { $0 + $1.fileSize }
        log(.info, "Assets loaded: \(assetURLs.count) assets, \(totalSize.formatted) in \(String(format: "%.2f", totalTime))s")

        if let lastError {
            throw lastError
        }
    }

    /// Checks if an asset URL is supported
    private func isSupportedAsset(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else {
            log(.warn, "Malformed asset link: \(urlString)")
            return false
        }

        guard url.scheme == "http" || url.scheme == "https" else {
            log(.warn, "Unexpected asset link: \(urlString)")
            return false
        }

        let supportedResourceSuffixes = [".js", ".css", ".js.map"]
        guard supportedResourceSuffixes.contains(where: { url.lastPathComponent.hasSuffix($0) }) else {
            log(.warn, "Unsupported asset URL: \(url)")
            return false
        }

        return true
    }

    /// Fetches a single asset and stores it on disk
    /// - Returns: The local file URL where the asset is stored
    private func fetchAsset(from urlString: String) async throws -> URL {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let localURL = assetsDirectoryURL.appendingPathComponent(cachedFilename(for: urlString))

        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let request = URLRequest(url: url)
        let (downloadedURL, response) = try await networkSession.download(for: request, delegate: nil)
        let downloadTime = CFAbsoluteTimeGetCurrent() - startTime

        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw URLError(.badServerResponse)
        }

        try FileManager.default.moveItem(at: downloadedURL, to: localURL)

        log(.debug, "Downloaded asset: \(url.lastPathComponent) (\(localURL.fileSize.formatted)) in \(String(format: "%.2f", downloadTime))s")
        return localURL
    }

    /// Loads a cached asset from disk
    func getCachedAsset(from assetsURL: URL) throws -> (URLResponse, Data) {
        guard let httpURL = CachedAssetSchemeHandler.originalHTTPURL(from: assetsURL) else {
            throw URLError(.badURL)
        }

        let localURL = assetsDirectoryURL.appendingPathComponent(cachedFilename(for: httpURL.absoluteString))

        guard FileManager.default.fileExists(atPath: localURL.path) else {
            throw URLError(.fileDoesNotExist)
        }

        let content = try Data(contentsOf: localURL)
        let mimeType: String = switch httpURL.pathExtension {
        case "js": "application/javascript"
        case "css": "text/css"
        default: "application/octet-stream"
        }
        let response = URLResponse(url: assetsURL, mimeType: mimeType, expectedContentLength: content.count, textEncodingName: nil)
        return (response, content)
    }

    // MARK: - Helpers

    /// Deletes all cached editor data for all sites
    static func deleteAllData() throws {
        if FileManager.default.fileExists(atPath: EditorService.rootURL.path()) {
            try FileManager.default.removeItem(at: EditorService.rootURL)
        }
    }

    /// Generates a cached filename from an asset URL using SHA256 hash
    nonisolated func cachedFilename(for urlString: String) -> String {
        let hash = urlString.sha1
        // Preserve file extension if present
        if let url = URL(string: urlString) {
            let ext = url.pathExtension
            return ext.isEmpty ? hash : "\(hash).\(ext)"
        }
        return hash
    }

    private func fetchData(for requestURL: URL, authHeader: String) async throws -> Data {
        var request = URLRequest(url: requestURL)
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        let (data, response) = try await networkSession.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode,
              (200..<300).contains(status) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

private extension Result {
    init(catching body: () async throws -> Success) async where Failure == Error {
        do {
            self = .success(try await body())
        } catch {
            self = .failure(error)
        }
    }
}

private extension URL {
    var fileSize: Int64 {
        (try? FileManager.default.attributesOfItem(atPath: path())[.size] as? Int64) ?? 0
    }
}

private extension Int64 {
    var formatted: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

private extension FileManager {
    func createDirectoryIfNeeded(at url: URL) {
        if !fileExists(atPath: url.path) {
            try? createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

private extension EditorConfiguration {
    /// Returns the endpoint URL for fetching the editor assets manifest
    func editorAssetsManifestEndpoint() throws -> URL {
        if let customEndpoint = editorAssetsEndpoint {
            return customEndpoint
        }
        // Fall back to constructing endpoint from siteApiRoot
        guard let baseURL = URL(string: siteApiRoot) else {
            throw URLError(.badURL)
        }
        let excludeParam = URLQueryItem(name: "exclude", value: "core,gutenberg")
        return baseURL
            .appendingPathComponent("/wpcom/v2/editor-assets")
            .appending(queryItems: [excludeParam])
    }
}
