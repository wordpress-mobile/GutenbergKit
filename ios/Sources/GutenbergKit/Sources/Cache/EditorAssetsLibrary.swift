import Foundation
import CryptoKit

public actor EditorAssetsLibrary {
    enum ManifestError: Error {
        case unavailable
        case invalidServerResponse
        case invalidSiteUrl
    }

    let urlSession: URLSession
    let configuration: EditorConfiguration
    let assetsDirectory: URL

    public init(configuration: EditorConfiguration) {
        self.configuration = configuration
        self.assetsDirectory = configuration.cachedEditorAssetsDirectory
        self.urlSession = URLSession(configuration: .default)
    }

    /// Returns the `EditorConfiguration.editorAssetsEndpoint` manifest content. The manifest content is cached and
    /// reused on future calls.
    func loadManifestContent() async throws -> Data {
        let endpoint: URL
        if let url = configuration.editorAssetsEndpoint {
            endpoint = url
        } else if !configuration.siteApiRoot.isEmpty, let apiRoot = URL(string: configuration.siteApiRoot) {
            endpoint = apiRoot.appendingPathComponent("wpcom/v2/editor-assets")
        } else {
            throw ManifestError.unavailable
        }

        var request = URLRequest(url: endpoint)
        request.setValue(configuration.authHeader, forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) {
            return data
        } else {
            throw ManifestError.invalidServerResponse
        }
    }

    /// Returns the `EditorConfiguration.editorAssetsEndpoint` manifest content, with JavaScript and stylesheet links
    /// modified so that their content can be cached and reused by the editor.
    ///
    /// - SeeAlso: `CachedAssetSchemeHandler`
    /// - SeeAlso: `EditorAssetsLibrary.addAsset`
    func manifestContentForEditor() async throws -> Data {
        // For scheme-less links (i.e. '//stats.wp.com/w.js'), use the scheme in `siteURL`.
        guard let siteURLScheme = URL(string: configuration.siteURL)?.scheme else {
            throw ManifestError.invalidSiteUrl
        }

        let data = try await loadManifestContent()
        let manifest = try EditorAssetManifest(data: data)

        return try JSONEncoder().encode(manifest.applyingUrlScheme(siteURLScheme, using: configuration.assetManifestParser))
    }

    /// Fetches all assets in the `EditorConfiguration.editorAssetsEndpoint` manifest and stores them on the device.
    ///
    /// - SeeAlso: CachedAssetSchemeHandler
    public func fetchAssets() async throws {
        // For scheme-less links (i.e. '//stats.wp.com/w.js'), use the scheme in `siteURL`.
        let siteURLScheme = URL(string: configuration.siteURL)?.scheme

        let data = try await loadManifestContent()
        let manifest = try EditorAssetManifest(data: data)
            .applyingUrlScheme(siteURLScheme, using: configuration.assetManifestParser)
        let assetUrls = try manifest.getAllAssetUrls(using: configuration.assetManifestParser)

        for url in assetUrls {
            guard url.scheme == "http" || url.scheme == "https" else {
                NSLog("Unexpected asset link: \(url)")
                continue
            }

            try await cacheAsset(from: url)
        }
        NSLog("\(assetUrls.count) resources processed.")
    }

    /// Fetches one asset (JavaScript or stylesheet) and caches its content on the device.
    ///
    /// - Parameters:
    ///   - httpURL: The javascript or css URL.
    ///   - webViewURL: The corresponding URL requested by web view, which should the "GBK cache prefix" (`gbk-cache-https://`)
    @discardableResult
    func cacheAsset(from httpURL: URL, webViewURL: URL? = nil) async throws -> (URLResponse, Data) {
        // The Web Inspector automatically requests ".js.map" files, we'll support it here for debugging purpose.
        let supportedResourceSuffixes = [".js", ".css", ".js.map"]
        guard httpURL.scheme?.starts(with: "http") == true,
              supportedResourceSuffixes.contains(where: { httpURL.lastPathComponent.hasSuffix($0) }) else {
            NSLog("Attemps to cache an unsupported URL: \(httpURL)")
            throw URLError(.unsupportedURL)
        }

        let fileManager = FileManager.default

        let localURL = assetsDirectory.appendingPathComponent(httpURL.uniqueFilename)

        if !fileManager.fileExists(atPath: localURL.path) {
            if !fileManager.fileExists(atPath: localURL.deletingLastPathComponent().path) {
                try fileManager.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            }

            let (downloaded, response) = try await urlSession.download(from: httpURL)
            if let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) {
                try fileManager.moveItem(at: downloaded, to: localURL)
            } else {
                NSLog("Received an unexpected HTTP response for URL: \(httpURL)")
                var cacheResponse = response
                // When loading the asset for web view, we need to make sure the return URLResponse.url matches the
                // asset url in the web view.
                if let webViewURL {
                    cacheResponse = URLResponse(
                        url: webViewURL,
                        mimeType: response.mimeType,
                        expectedContentLength: Int(response.expectedContentLength),
                        textEncodingName: response.textEncodingName
                    )
                }
                return try (cacheResponse, Data(contentsOf: downloaded))
            }
        }

        let content = try Data(contentsOf: localURL)
        let mimeType: String = switch httpURL.pathExtension {
        case "js": "application/javascript"
        case "css": "text/css"
        default: "application/octet-stream"
        }
        let response = URLResponse(url: webViewURL ?? httpURL, mimeType: mimeType, expectedContentLength: content.count, textEncodingName: nil)
        return (response, content)
    }
}

private extension EditorConfiguration {
    var cachedEditorAssetsDirectory: URL {
        var siteName = "shared"

        if !siteURL.isEmpty, var url = URLComponents(string: siteURL) {
            url.scheme = nil
            url.query = nil
            url.fragment = nil

            if let dirname = url.url?.absoluteString {
                let illegalChars = CharacterSet(charactersIn: "/:\\?%*|\"<>").union(.newlines).union(.controlCharacters)
                siteName = dirname.trimmingCharacters(in: illegalChars).components(separatedBy: illegalChars).joined(separator: "-")
            }
        }

        return FileManager.default
            // Use the app cache directory to prevent editor assets from being backed up to iCloud.
            // Set `isExcludedFromBackup = true` if this directory is changed in the future.
            .urls(for: .cachesDirectory, in:.userDomainMask)
            .last!
            .appendingPathComponent("editor-caches")
            .appendingPathComponent(siteName)
    }
}

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

private extension String {
    var sha256: String {
        SHA256.hash(data: Data(utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
    }
}

public struct EditorAssetSchemeResolver {
    // Takes a URL string and applies the given scheme to it.
    //
    // If there is no scheme present, the `defaultScheme` will be applied to it. If no `defaultScheme` is
    // provided, `https` will be used.
    public static func resolveSchemeFor(_ link: String, defaultScheme: String?) -> String {
        if link.starts(with: "//") {
            return "\(defaultScheme ?? "https"):\(link)"
        }

        return link
    }
}


// An object representing the JSON response we receive from the server
//
public struct EditorAssetManifest: Codable {
    public let scripts: String
    public let styles: String
    public let allowedBlockTypes: [String]

    enum CodingKeys: String, CodingKey {
        case scripts
        case styles
        case allowedBlockTypes = "allowed_block_types"
    }

    init(data: Data) throws {
        self = try JSONDecoder().decode(EditorAssetManifest.self, from: data)
    }

    init(scripts: String, styles: String, allowedBlockTypes: [String]) {
        self.scripts = scripts
        self.styles = styles
        self.allowedBlockTypes = allowedBlockTypes
    }

    func getScriptUrlStrings(using parser: EditorAssetManifestParser) throws -> [String] {
        try parser.extractScriptURLs(from: self.scripts)
    }

    func getScriptUrls(using parser: EditorAssetManifestParser) throws -> [URL] {
        try getScriptUrlStrings(using: parser).compactMap(URL.init)
    }

    func getStyleUrlStrings(using parser: EditorAssetManifestParser) throws -> [String] {
        try parser.extractStyleURLs(from: self.styles)
    }

    func getStyleUrls(using parser: EditorAssetManifestParser) throws -> [URL] {
        try getStyleUrlStrings(using: parser).compactMap(URL.init)
    }

    func getAllAssetUrls(applyingDefaultScheme scheme: String? = nil, using parser: EditorAssetManifestParser) throws -> [URL] {
        let scriptUrls = try self.getScriptUrls(using: parser)
        let styleUrls = try self.getStyleUrls(using: parser)

        return scriptUrls + styleUrls
    }

    func applyingUrlScheme(_ newScheme: String?, using manifestParser: EditorAssetManifestParser) throws -> Self {
        var mutableStyles = self.styles
        var mutableScripts = self.scripts

        for rawLink in try getStyleUrlStrings(using: manifestParser) {
            let resolvedLink = EditorAssetSchemeResolver.resolveSchemeFor(rawLink, defaultScheme: newScheme)
            mutableStyles = mutableStyles.replacingOccurrences(of: rawLink, with: resolvedLink)
        }

        for rawLink in try getScriptUrlStrings(using: manifestParser) {
            let resolvedLink = EditorAssetSchemeResolver.resolveSchemeFor(rawLink, defaultScheme: newScheme)
            mutableScripts = mutableScripts.replacingOccurrences(of: rawLink, with: resolvedLink)
        }

        return EditorAssetManifest(
            scripts: mutableScripts,
            styles: mutableStyles,
            allowedBlockTypes: self.allowedBlockTypes
        )
    }

    func resolvingCachedUrls(using manifestParser: EditorAssetManifestParser) throws -> Self {
        var mutableStyles = self.styles
        var mutableScripts = self.scripts

        for url in try getStyleUrls(using: manifestParser) {
            let cachedLink = CachedAssetSchemeHandler.cachedURL(for: url)
            mutableStyles = mutableStyles.replacingOccurrences(of: url.absoluteString, with: cachedLink.absoluteString)
        }

        for url in try getScriptUrls(using: manifestParser) {
            let cachedLink = CachedAssetSchemeHandler.cachedURL(for: url)
            mutableScripts = mutableScripts.replacingOccurrences(of: url.absoluteString, with: cachedLink.absoluteString)
        }

        return EditorAssetManifest(
            scripts: mutableScripts,
            styles: mutableStyles,
            allowedBlockTypes: self.allowedBlockTypes
        )
    }
}
