import Foundation
import CryptoKit
import SwiftSoup
import OSLog

/// Service for fetching the editor settings and other parts of the enrvironment
/// required to launch the editor.
actor EditorService {
    enum EditorServiceError: Error {
        case invalidResponseData
        case manifestUnavailable
        case invalidServerResponse
    }

    struct State: Codable {
        let refreshDate: Date
    }

    @MainActor private static var instances: [String: EditorService] = [:]

    private let siteURL: String
    private let urlSession: URLSession
    private let logLevel: LogLevel
    private let logger: Logger

    private let storeURL: URL
    private var editorSettingsFileURL: URL { storeURL.appendingPathComponent("settings.json") }
    private var manifestFileURL: URL { storeURL.appendingPathComponent("manifest.json") }
    private var stateFileURL: URL { storeURL.appendingPathComponent("state.json") }
    private var assetsDirectoryURL: URL { storeURL.appendingPathComponent("assets", isDirectory: true) }

    private var refreshTask: Task<Void, Never>?

    /// Returns the shared EditorService instance for the given siteURL
    @MainActor
    static func shared(for siteURL: String, logLevel: LogLevel = .error, urlSession: URLSession = .shared) -> EditorService {
        if let existing = instances[siteURL] {
            return existing
        }
        let service = EditorService(siteURL: siteURL, logLevel: logLevel, urlSession: urlSession)
        instances[siteURL] = service
        return service
    }

    /// Creates a new EditorService instance
    /// - Parameters:
    ///   - siteURL: Unique identifier for the site (used for caching)
    ///   - logLevel: Minimum log level for messages (defaults to .error)
    ///   - urlSession: URLSession to use for network requests (defaults to .shared)
    private init(siteURL: String, logLevel: LogLevel = .error, urlSession: URLSession = .shared) {
        self.siteURL = siteURL
        self.logLevel = logLevel
        self.urlSession = urlSession
        self.logger = Logger(subsystem: "com.gutenbergkit.editor", category: "EditorService")

        self.storeURL = URL.documentsDirectory
            .appendingPathComponent("GutenbergKit", isDirectory: true)
            .appendingPathComponent(siteURL.safeFilename, isDirectory: true)
    }

    /// Set up the editor for the given site.
    ///
    /// - warning: The request make take a significant amount of time the first
    /// time you open the editor.
    func setup(_ configuration: inout EditorConfiguration) async throws {
        var builder = configuration.toBuilder()

        if !isEditorLoaded {
            await refresh(configuration: configuration)
        }

        if let data = try? Data(contentsOf: editorSettingsFileURL),
           let settings = String(data: data, encoding: .utf8) {
            builder = builder.setEditorSettings(settings)
        }

        if let manifestString = try? getManifestForEditor(siteURL: configuration.siteURL) {
            builder = builder.setManifest(manifestString)
        }

        return configuration = builder.build()
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

        guard case .success(let manifestData) = manifestResult else {
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
            try await fetchAssets(manifestData: manifestData)
        } catch {
            log(.error, "Failed to fetch assets: \(error)")
            log(.error, "Editor refresh aborted: asset fetching failed")
            return
        }
        let assetsTime = CFAbsoluteTimeGetCurrent() - assetsStartTime

        // Only write manifest to disk after all assets are successfully fetched
        do {
            createStoreDirectoryIfNeeded()
            try manifestData.write(to: manifestFileURL)
            log(.info, "Manifest saved to disk")
        } catch {
            log(.error, "Failed to save manifest: \(error)")
            return
        }

        // Save state to indicate successful refresh
        do {
            let state = State(refreshDate: Date())
            let stateData = try JSONEncoder().encode(state)
            try stateData.write(to: stateFileURL)
            log(.info, "State saved to disk")
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
            createStoreDirectoryIfNeeded()
            try data.write(to: editorSettingsFileURL)
        } catch {
            assertionFailure("Failed to save settings: \(error)")
        }
        return data
    }

    // MARK: - Manifest

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
    /// Verifies that all required assets are cached before returning the manifest.
    ///
    /// - Parameter siteURL: The site URL to extract the scheme for scheme-less links
    /// - Returns: JSON string of the processed manifest
    /// - Throws: `EditorServiceError` if assets are missing or manifest processing fails
    private func getManifestForEditor(siteURL: String) throws -> String {
        // For scheme-less links (i.e. '//stats.wp.com/w.js'), use the scheme in `siteURL`.
        let siteURLScheme = URL(string: siteURL)?.scheme
        let data = try Data(contentsOf: manifestFileURL)
        let manifest = try JSONDecoder().decode(EditorAssetsManifest.self, from: data)
        let assetLinks = try manifest.parseAssetLinks()

        // Verify all assets are cached
        let fileManager = FileManager.default
        var missingAssets: [String] = []

        for urlString in assetLinks {
            let filename = cachedFilename(for: urlString)
            let localURL = assetsDirectoryURL.appendingPathComponent(filename)

            if !fileManager.fileExists(atPath: localURL.path) {
                missingAssets.append(urlString)
            }
        }

        if !missingAssets.isEmpty {
            log(.error, "Missing \(missingAssets.count) asset(s) from cache")
            for (index, asset) in missingAssets.prefix(5).enumerated() {
                log(.error, "  [\(index + 1)] \(asset)")
            }
            if missingAssets.count > 5 {
                log(.error, "  ... and \(missingAssets.count - 5) more")
            }
            throw EditorServiceError.manifestUnavailable
        }

        log(.info, "All \(assetLinks.count) manifest assets verified in cache")

        // Process manifest for editor
        let processedData = try manifest.renderForEditor(defaultScheme: siteURLScheme)
        guard let jsonString = String(data: processedData, encoding: .utf8) else {
            throw EditorServiceError.invalidResponseData
        }
        return jsonString
    }

    // MARK: - Assets

    /// Fetches all assets from the manifest and stores them on the device
    private func fetchAssets(manifestData: Data) async throws {
        let manifest = try JSONDecoder().decode(EditorAssetsManifest.self, from: manifestData)
        let assetLinks = try manifest.parseAssetLinks()

        log(.info, "Found \(assetLinks.count) assets to fetch")

        // Create assets directory if needed
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: assetsDirectoryURL.path) {
            try fileManager.createDirectory(at: assetsDirectoryURL, withIntermediateDirectories: true)
        }

        // Track statistics
        var fetchedCount = 0
        var cachedCount = 0
        var totalSize: Int64 = 0

        // Fetch all assets in parallel
        try await withThrowingTaskGroup(of: (Bool, Int64).self) { group in
            for link in assetLinks {
                group.addTask {
                    try await self.fetchAsset(from: link)
                }
            }

            for try await (wasCached, size) in group {
                if wasCached {
                    cachedCount += 1
                } else {
                    fetchedCount += 1
                }
                totalSize += size
            }
        }

        let totalSizeMB = Double(totalSize) / (1024 * 1024)
        log(.info, "Assets loaded: \(fetchedCount) fetched, \(cachedCount) cached, total size: \(String(format: "%.2f", totalSizeMB)) MB")
    }

    /// Fetches a single asset and stores it on disk
    /// - Returns: A tuple indicating (wasCached, fileSize)
    private func fetchAsset(from urlString: String) async throws -> (Bool, Int64) {
        guard let url = URL(string: urlString) else {
            log(.warn, "Malformed asset link: \(urlString)")
            return (false, 0)
        }

        guard url.scheme == "http" || url.scheme == "https" else {
            log(.warn, "Unexpected asset link: \(urlString)")
            return (false, 0)
        }

        let supportedResourceSuffixes = [".js", ".css", ".js.map"]
        guard supportedResourceSuffixes.contains(where: { url.lastPathComponent.hasSuffix($0) }) else {
            log(.warn, "Unsupported asset URL: \(url)")
            return (false, 0)
        }

        let localURL = assetsDirectoryURL.appendingPathComponent(cachedFilename(for: urlString))

        // Check if already cached
        if FileManager.default.fileExists(atPath: localURL.path) {
            let size = try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64 ?? 0
            return (true, size ?? 0)
        }

        let (downloadedURL, response) = try await urlSession.download(from: url)
        if let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) {
            let size = try? FileManager.default.attributesOfItem(atPath: downloadedURL.path)[.size] as? Int64 ?? 0
            do {
                try FileManager.default.moveItem(at: downloadedURL, to: localURL)
            } catch {
                log(.error, "Failed to move downloaded assets \(downloadedURL) \(localURL)")
            }
            log(.debug, "Downloaded asset: \(url.lastPathComponent) (\(size ?? 0) bytes)")
            return (false, size ?? 0)
        } else {
            log(.error, "Received unexpected HTTP response for URL: \(url)")
            return (false, 0)
        }
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

    // MARK: - Data Management

    /// Deletes all cached editor data for all sites
    public static func deleteAllData() throws {
        let rootURL = URL.documentsDirectory.appendingPathComponent("GutenbergKit", isDirectory: true)
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: rootURL)
    }

    // MARK: - Helpers

    /// Generates a cached filename from an asset URL using SHA256 hash
    private func cachedFilename(for urlString: String) -> String {
        let hash = SHA256.hash(data: Data(urlString.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()

        // Preserve file extension if present
        if let url = URL(string: urlString) {
            let ext = url.pathExtension
            return ext.isEmpty ? hash : "\(hash).\(ext)"
        }
        return hash
    }

    private func createStoreDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: storeURL.path) {
            try? FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: true)
        }
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

    // MARK: - Logging

    /// Logs a message at the specified level
    private func log(_ level: LogLevel, _ message: String) {
        guard level.rawValue >= logLevel.rawValue else { return }
        switch level {
        case .debug: logger.debug("\(message)")
        case .info: logger.info("\(message)")
        case .warn: logger.warning("\(message)")
        case .error: logger.error("\(message)")
        }
    }
}

// MARK: - Result Extension

private extension Result {
    init(catching body: () async throws -> Success) async where Failure == Error {
        do {
            self = .success(try await body())
        } catch {
            self = .failure(error)
        }
    }
}

