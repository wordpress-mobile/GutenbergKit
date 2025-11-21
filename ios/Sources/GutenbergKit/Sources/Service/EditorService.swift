import Foundation
import CryptoKit
import SwiftSoup
import OSLog

/// Service for fetching the editor settings and other parts of the environment
/// required to launch the editor.
actor EditorService {
    struct State: Codable {
        let refreshDate: Date
    }

    @MainActor private static var instances: [String: EditorService] = [:]

    private let siteURL: String
    private let urlSession: URLSession

    private let storeURL: URL
    private var editorSettingsFileURL: URL { storeURL.appendingPathComponent("settings.json") }
    private var manifestFileURL: URL { storeURL.appendingPathComponent("manifest.json") }
    private var stateFileURL: URL { storeURL.appendingPathComponent("state.json") }
    private var assetsDirectoryURL: URL { storeURL.appendingPathComponent("assets", isDirectory: true) }

    private var refreshTask: Task<Void, Never>?

    /// Returns the shared EditorService instance for the given siteURL
    @MainActor
    static func shared(for siteURL: String) -> EditorService {
        if let existing = instances[siteURL] {
            return existing
        }
        let service = EditorService(siteURL: siteURL, urlSession: .shared)
        instances[siteURL] = service
        return service
    }

    /// Creates a new EditorService instance
    /// - Parameters:
    ///   - siteURL: Unique identifier for the site (used for caching)
    ///   - urlSession: URLSession to use for network requests (defaults to .shared)
    private init(siteURL: String, urlSession: URLSession = .shared) {
        self.siteURL = siteURL
        self.urlSession = urlSession

        self.storeURL = EditorService.rootURL
            .appendingPathComponent(siteURL.sha1, isDirectory: true)
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
                log(.info, "Registering background refresh to be performed later")
                if !isWarmup {
                    try? await Task.sleep(for: .seconds(7))
                }
                await refresh(configuration: configuration)
            }
        }

        var dependencies = EditorDependencies()
        if let data = try? Data(contentsOf: editorSettingsFileURL),
           let settings = String(data: data, encoding: .utf8) {
            dependencies.editorSettings = settings
        }
        dependencies.manifest = try? getManifestForEditor(siteURL: configuration.siteURL)
        let loadTime = CFAbsoluteTimeGetCurrent() - startTime
        log(.info, "Loaded dependencies in \(String(format: "%.3f", loadTime))s")

        return dependencies
    }

    /// Returns `true` if the resources required for the editor already exist.
    private var isEditorLoaded: Bool {
        FileManager.default.fileExists(atPath: stateFileURL.path)
    }

    /// Refresh the editor resources.
    /// Will not refresh more often than once every 30 seconds.
    private func refresh(configuration: EditorConfiguration) async {
        if let task = refreshTask {
            return await task.value
        }

        // Check if we refreshed recently (within the last 30 seconds)
        if let data = try? Data(contentsOf: stateFileURL),
           let state = try? JSONDecoder().decode(State.self, from: data) {
            let timeSinceLastRefresh = Date().timeIntervalSince(state.refreshDate)
            if timeSinceLastRefresh < 30 {
                log(.info, "Skipping refresh - last refresh was \(String(format: "%.1f", timeSinceLastRefresh))s ago")
                return
            }
        }

        let task = Task {
            defer { refreshTask = nil }
            await actuallyRefresh(configuration: configuration)
        }
        refreshTask = task
        return await task.value
    }

    private func actuallyRefresh(configuration: EditorConfiguration) async {
        let startTime = CFAbsoluteTimeGetCurrent()
        log(.info, "Starting editor resources refresh")

        guard let baseURL = URL(string: configuration.siteApiRoot) else {
            log(.error, "Invalid siteApiRoot URL: \(configuration.siteApiRoot)")
            return
        }

        // Fetch settings and manifest in parallel
        async let settingsFuture = Result { try await fetchEditorSettings(baseURL: baseURL, authHeader: configuration.authHeader) }
        async let manifestFuture = Result { try await fetchManifestData(baseURL: baseURL, authHeader: configuration.authHeader) }

        let (settingsResult, manifestResult) = await (settingsFuture, manifestFuture)

        // Log errors but continue
        if case .failure(let error) = settingsResult {
            log(.error, "Failed to fetch editor settings: \(error)")
        }

        guard case .success(let manifest) = manifestResult else {
            if case .failure(let error) = manifestResult {
                log(.error, "Failed to fetch manifest: \(error)")
            }
            log(.error, "Editor refresh aborted: manifest fetch failed")
            return
        }

        let fetchTime = CFAbsoluteTimeGetCurrent() - startTime
        log(.info, "Fetched settings and manifest in \(String(format: "%.2f", fetchTime))s")

        // Fetch all assets for the new manifest
        let assetsStartTime = CFAbsoluteTimeGetCurrent()
        do {
            try await fetchAssets(manifestData: manifest)
        } catch {
            log(.error, "Failed to fetch assets: \(error)")
            log(.error, "Editor refresh aborted: asset fetching failed")
            return
        }
        let assetsTime = CFAbsoluteTimeGetCurrent() - assetsStartTime

        // Only write manifest to disk after all assets are successfully fetched
        do {
            FileManager.default.createDirectoryIfNeeded(at: storeURL)
            try manifest.write(to: manifestFileURL)
            log(.info, "Manifest saved to disk")
        } catch {
            log(.error, "Failed to save manifest: \(error)")
            return
        }

        // Save state to indicate successful refresh
        do {
            let state = State(refreshDate: Date())
            try JSONEncoder().encode(state).write(to: stateFileURL)
        } catch {
            log(.error, "Failed to save state: \(error)")
        }

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        log(.info, "Editor refresh completed in \(String(format: "%.2f", totalTime))s (assets: \(String(format: "%.2f", assetsTime))s)")
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
    private func fetchManifestData(baseURL: URL, authHeader: String) async throws -> Data {
        let excludeParam = URLQueryItem(name: "exclude", value: "core,gutenberg")
        let endpoint = baseURL
            .appendingPathComponent("/wpcom/v2/editor-assets")
            .appending(queryItems: [excludeParam])

        let data = try await fetchData(for: endpoint, authHeader: authHeader)
        return data
    }

    /// Returns the editor assets manifest as a JSON string, with JavaScript and stylesheet links
    /// modified so that their content can be cached and reused by the editor.
    ///
    /// - Parameter siteURL: The site URL to extract the scheme for scheme-less links
    /// - Returns: JSON string of the processed manifest
    private func getManifestForEditor(siteURL: String) throws -> String {
        // For scheme-less links (i.e. '//stats.wp.com/w.js'), use the scheme in `siteURL`.
        let siteURLScheme = URL(string: siteURL)?.scheme
        let data = try Data(contentsOf: manifestFileURL)
        let manifest = try JSONDecoder().decode(EditorAssetsManifest.self, from: data)

        // Process manifest for editor
        let processedData = try manifest.renderForEditor(defaultScheme: siteURLScheme)
        guard let jsonString = String(data: processedData, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return jsonString
    }

    // MARK: - Assets

    /// Fetches all assets from the manifest and stores them on the device
    private func fetchAssets(manifestData: Data) async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        let manifest = try JSONDecoder().decode(EditorAssetsManifest.self, from: manifestData)
        let assetLinks = try manifest.parseAssetLinks()
            .filter { isSupportedAsset($0) }

        log(.info, "Found \(assetLinks.count) assets to fetch")

        FileManager.default.createDirectoryIfNeeded(at: assetsDirectoryURL)

        // Track statistics
        var fetchedCount = 0
        var cachedCount = 0
        var assetURLs: [URL] = []

        // Fetch all assets in parallel
        await withTaskGroup(of: Result<(Bool, URL), Error>.self) { group in
            for link in assetLinks {
                group.addTask {
                    await Result { try await self.fetchAsset(from: link) }
                }
            }

            for await result in group {
                switch result {
                case .success(let (wasCached, url)):
                    if wasCached {
                        cachedCount += 1
                    } else {
                        fetchedCount += 1
                    }
                    assetURLs.append(url)
                case .failure(let error):
                    log(.error, "Failed to fetch asset: \(error)")
                }
            }
        }

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        log(.info, "Assets loaded: \(fetchedCount) fetched, \(cachedCount) cached, total size: \(assetURLs.reduce(0) { $0 + $1.fileSize }.formatted) in \(String(format: "%.2f", totalTime))s")
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
    /// - Returns: A tuple indicating (wasCached, fileURL)
    private func fetchAsset(from urlString: String) async throws -> (Bool, URL) {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let localURL = assetsDirectoryURL.appendingPathComponent(cachedFilename(for: urlString))

        if FileManager.default.fileExists(atPath: localURL.path) {
            return (true, localURL)
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let (downloadedURL, response) = try await urlSession.download(from: url)
        let downloadTime = CFAbsoluteTimeGetCurrent() - startTime

        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw URLError(.badServerResponse)
        }

        try FileManager.default.moveItem(at: downloadedURL, to: localURL)

        log(.debug, "Downloaded asset: \(url.lastPathComponent) (\(localURL.fileSize.formatted)) in \(String(format: "%.2f", downloadTime))s")
        return (false, localURL)
    }

    /// Loads a cached asset from disk
    func loadCachedAsset(from httpURL: URL, webViewURL: URL) throws -> (URLResponse, Data) {
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
        let response = URLResponse(url: webViewURL, mimeType: mimeType, expectedContentLength: content.count, textEncodingName: nil)
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
    private func cachedFilename(for urlString: String) -> String {
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

        let (data, response) = try await urlSession.data(for: request)
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
