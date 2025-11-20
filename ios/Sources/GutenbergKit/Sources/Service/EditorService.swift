import Foundation

/// Service for fetching the editor settings and other parts of the enrvironment
/// required to launch the editor.
public actor EditorService {
    enum EditorServiceError: Error {
        case invalidResponseData
    }

    private let siteID: String
    private let baseURL: URL
    private let authHeader: String
    private let urlSession: URLSession

    private let storeURL: URL
    private var editorSettingsFileURL: URL { storeURL.appendingPathComponent("settings.json") }

    private var refreshTask: Task<Void, Error>?

    /// Creates a new EditorService instance
    /// - Parameters:
    ///   - siteID: Unique identifier for the site (used for caching)
    ///   - baseURL: Root URL for the site API
    ///   - authHeader: Authorization header value
    ///   - urlSession: URLSession to use for network requests (defaults to .shared)
    public init(siteID: String, baseURL: URL, authHeader: String, urlSession: URLSession = .shared) {
        self.siteID = siteID
        self.baseURL = baseURL
        self.authHeader = authHeader
        self.urlSession = urlSession

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

    /// Returns `true` is the resources requied for the editor already exist.
    private var isEditorLoaded: Bool {
        FileManager.default.fileExists(atPath: editorSettingsFileURL.path())
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
        try await fetchEditorSettings()
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
}
