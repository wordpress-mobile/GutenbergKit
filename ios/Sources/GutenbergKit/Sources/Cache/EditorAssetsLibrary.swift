import Foundation
import CryptoKit
import SwiftSoup

public actor EditorAssetsLibrary {
    enum ManifestError: Error {
        case unavailable
        case invalidServerResponse
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
        let siteURLScheme = URL(string: configuration.siteURL)?.scheme
        let data = try await loadManifestContent()
        let manifest = try JSONDecoder().decode(EditorAssetsMainifest.self, from: data)
        return try manifest.renderForEditor(defaultScheme: siteURLScheme)
    }

    /// Fetches all assets in the `EditorConfiguration.editorAssetsEndpoint` manifest and stores them on the device.
    ///
    /// - SeeAlso: CachedAssetSchemeHandler
    public func fetchAssets() async throws {
        // For scheme-less links (i.e. '//stats.wp.com/w.js'), use the scheme in `siteURL`.
        let siteURLScheme = URL(string: configuration.siteURL)?.scheme

        let data = try await loadManifestContent()
        let manifest = try JSONDecoder().decode(EditorAssetsMainifest.self, from: data)
        let assetLinks = try manifest.parseAssetLinks(defaultScheme: siteURLScheme)

        for link in assetLinks {
            guard let url = URL(string: link) else {
                NSLog("Malformed asset link: \(link)")
                continue
            }

            guard url.scheme == "http" || url.scheme == "https" else {
                NSLog("Unexpected asset link: \(link)")
                continue
            }

            _ = try await cacheAsset(from: url)
        }
        NSLog("\(assetLinks.count) resources processed.")
    }

    /// Fetches one asset (JavaScript or stylesheet) and caches its content on the device.
    ///
    /// - Parameters:
    ///   - httpURL: The javascript or css URL.
    ///   - webViewURL: The corresponding URL requested by web view, which should the "GBK cache prefix" (`gbk-cache-https://`)
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

struct EditorAssetsMainifest: Codable {
    var scripts: String
    var styles: String
    var allowedBlockTypes: [String]

    enum CodingKeys: String, CodingKey {
        case scripts
        case styles
        case allowedBlockTypes = "allowed_block_types"
    }

    func parseAssetLinks(defaultScheme: String?) throws -> [String] {
        let html = """
            <html>
                <head>
                \(scripts)
                \(styles)
                </head>
                <body></body>
            </html>
            """
        let document = try SwiftSoup.parse(html)

        var assetLinks: [String] = []
        assetLinks += try document.select("script[src]").map {
            Self.resolveAssetLink(try $0.attr("src"), defaultScheme: defaultScheme)
        }
        assetLinks += try document.select(#"link[rel="stylesheet"][href]"#).map {
            Self.resolveAssetLink(try $0.attr("href"), defaultScheme: defaultScheme)
        }
        return assetLinks
    }

    func renderForEditor(defaultScheme: String?) throws -> Data {
        var rendered = self
        rendered.scripts = try Self.renderForEditor(scripts: self.scripts, defaultScheme: defaultScheme)
        rendered.styles = try Self.renderForEditor(styles: self.styles, defaultScheme: defaultScheme)
        return try JSONEncoder().encode(rendered)
    }

    private static func renderForEditor(scripts: String, defaultScheme: String?) throws -> String {
        let html = """
            <html>
                <head>
                \(scripts)
                </head>
                <body></body>
            </html>
            """
        let document = try SwiftSoup.parse(html)

        for script in try document.select("script[src]") {
            if let src = try? script.attr("src") {
                let link = Self.resolveAssetLink(src, defaultScheme: defaultScheme)
                #if canImport(UIKit)
                let newLink = CachedAssetSchemeHandler.cachedURL(forWebLink: link) ?? link
                #else
                let newLink = link
                #endif
                try script.attr("src", newLink)
            }
        }

        let head = document.head()!
        return try head.html()
    }

    private static func renderForEditor(styles: String, defaultScheme: String?) throws -> String {
        let html = """
            <html>
                <head>
                \(styles)
                </head>
                <body></body>
            </html>
            """
        let document = try SwiftSoup.parse(html)

        for stylesheet in try document.select(#"link[rel="stylesheet"][href]"#) {
            if let href = try? stylesheet.attr("href") {
                let link = Self.resolveAssetLink(href, defaultScheme: defaultScheme)
                #if canImport(UIKit)
                let newLink = CachedAssetSchemeHandler.cachedURL(forWebLink: link) ?? link
                #else
                let newLink = link
                #endif
                try stylesheet.attr("href", newLink)
            }
        }

        let head = document.head()!
        return try head.html()
    }

    private static func resolveAssetLink(_ link: String, defaultScheme: String?) -> String {
        if link.starts(with: "//") {
            return "\(defaultScheme ?? "https"):\(link)"
        }

        return link
    }
}
