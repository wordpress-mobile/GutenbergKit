import Foundation
import CryptoKit
import SwiftSoup
import OSLog

/// Service for fetching the editor settings and other parts of the enrvironment
/// required to launch the editor.
public actor EditorService {
    enum EditorServiceError: Error {
        case invalidResponseData
        case manifestUnavailable
        case invalidServerResponse
    }

    private let siteID: String
    private let baseURL: URL
    private let authHeader: String
    private let urlSession: URLSession
    private let logLevel: LogLevel
    private let logger: Logger

    private let storeURL: URL
    private var editorSettingsFileURL: URL { storeURL.appendingPathComponent("settings.json") }
    private var manifestFileURL: URL { storeURL.appendingPathComponent("manifest.json") }
    private var assetsDirectoryURL: URL { storeURL.appendingPathComponent("assets", isDirectory: true) }

    private var refreshTask: Task<Void, Error>?

    /// Creates a new EditorService instance
    /// - Parameters:
    ///   - siteID: Unique identifier for the site (used for caching)
    ///   - baseURL: Root URL for the site API
    ///   - authHeader: Authorization header value
    ///   - logLevel: Minimum log level for messages (defaults to .error)
    ///   - urlSession: URLSession to use for network requests (defaults to .shared)
    public init(siteID: String, baseURL: URL, authHeader: String, logLevel: LogLevel = .error, urlSession: URLSession = .shared) {
        self.siteID = siteID
        self.baseURL = baseURL
        self.authHeader = authHeader
        self.logLevel = logLevel
        self.urlSession = urlSession
        self.logger = Logger(subsystem: "com.gutenbergkit.editor", category: "EditorService")

        self.storeURL = URL.documentsDirectory
            .appendingPathComponent("GutenbergKit", isDirectory: true)
            .appendingPathComponent(siteID.safeFilename, isDirectory: true)
    }

    /// Set up the editor for the given site.
    ///
    /// - warning: The request make take a significant amount of time the first
    /// time you open the editor.
    public func setup(_ configuration: inout EditorConfiguration) async throws {
        var builder = configuration.toBuilder()

        if !isEditorLoaded {
            try await refresh()
        }

        if let data = try? Data(contentsOf: editorSettingsFileURL),
           let settings = String(data: data, encoding: .utf8) {
            builder = builder.setEditorSettings(settings)
        }

        return configuration = builder.build()
    }

    /// Returns `true` if the resources required for the editor already exist.
    private var isEditorLoaded: Bool {
        FileManager.default.fileExists(atPath: editorSettingsFileURL.path()) &&
        FileManager.default.fileExists(atPath: manifestFileURL.path())
    }

    /// Refresh the editor resources.
    public func refresh() async throws {
        if let task = refreshTask {
            return try await task.value
        }
        let task = Task {
            defer { refreshTask = nil }
            try await actuallyRefresh()
        }
        refreshTask = task
        return try await task.value
    }

    private func actuallyRefresh() async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        log(.info, "Starting editor resources refresh")

        // Fetch settings and manifest in parallel
        async let settingsData = fetchEditorSettings()
        async let manifestData = fetchManifest()

        let (_, manifest) = try await (settingsData, manifestData)
        let fetchTime = CFAbsoluteTimeGetCurrent() - startTime
        log(.info, "Fetched settings and manifest in \(String(format: "%.2f", fetchTime))s")

        // After manifest is fetched, fetch all assets in parallel
        let assetsStartTime = CFAbsoluteTimeGetCurrent()
        try await fetchAssets(manifestData: manifest)
        let assetsTime = CFAbsoluteTimeGetCurrent() - assetsStartTime

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        log(.info, "Editor refresh completed in \(String(format: "%.2f", totalTime))s (assets: \(String(format: "%.2f", assetsTime))s)")
    }

    // MARK: – Editor Settings

    /// Fetches block editor settings from the WordPress REST API
    ///
    /// - Returns: Raw settings data from the API
    @discardableResult
    private func fetchEditorSettings() async throws -> Data {
        let data = try await getData(for: baseURL.appendingPathComponent("/wp-block-editor/v1/settings"))
        do {
            createStoreDirectoryIfNeeded()
            try data.write(to: editorSettingsFileURL)
        } catch {
            assertionFailure("Failed to save settings: \(error)")
        }
        return data
    }

    // MARK: - Private Helpers

    private func createStoreDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: storeURL.path) {
            try? FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: true)
        }
    }

    private func getData(for requestURL: URL) async throws -> Data {
        var request = URLRequest(url: requestURL)
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode,
              (200..<300).contains(status) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    // MARK: - Manifest

    /// Fetches the editor assets manifest from the WordPress REST API
    @discardableResult
    private func fetchManifest() async throws -> Data {
        let excludeParam = URLQueryItem(name: "exclude", value: "core,gutenberg")
        let endpoint = baseURL
            .appendingPathComponent("/wpcom/v2/editor-assets")
            .appending(queryItems: [excludeParam])

        let data = try await getData(for: endpoint)
        do {
            createStoreDirectoryIfNeeded()
            try data.write(to: manifestFileURL)
        } catch {
            assertionFailure("Failed to save manifest: \(error)")
        }
        return data
    }

    /// Returns the stored manifest data
    func getManifestData() throws -> Data {
        try Data(contentsOf: manifestFileURL)
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

        let localURL = assetsDirectoryURL.appendingPathComponent(url.uniqueFilename)

        // Check if already cached
        if FileManager.default.fileExists(atPath: localURL.path) {
            let size = try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64 ?? 0
            return (true, size ?? 0)
        }

        let (downloadedURL, response) = try await urlSession.download(from: url)
        if let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) {
            let size = try? FileManager.default.attributesOfItem(atPath: downloadedURL.path)[.size] as? Int64 ?? 0
            try FileManager.default.moveItem(at: downloadedURL, to: localURL)
            log(.debug, "Downloaded asset: \(url.lastPathComponent) (\(size ?? 0) bytes)")
            return (false, size ?? 0)
        } else {
            log(.error, "Received unexpected HTTP response for URL: \(url)")
            return (false, 0)
        }
    }

    /// Returns the local file URL for a cached asset
    func getCachedAssetURL(for httpURL: URL) -> URL? {
        let localURL = assetsDirectoryURL.appendingPathComponent(httpURL.uniqueFilename)
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            return nil
        }
        return localURL
    }

    /// Loads a cached asset from disk
    func loadCachedAsset(from httpURL: URL, webViewURL: URL) async throws -> (URLResponse, Data) {
        let localURL = assetsDirectoryURL.appendingPathComponent(httpURL.uniqueFilename)

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

// MARK: - URL Extension

private extension URL {
    var uniqueFilename: String {
        var filename = path

        if filename.hasPrefix("/") {
            filename.removeFirst()
        }

        filename.removeLast(pathExtension.count)

        let hash = SHA256.hash(data: Data(absoluteString.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()

        filename += hash

        if pathExtension.isEmpty {
            return filename
        } else {
            return filename + "." + pathExtension
        }
    }
}

