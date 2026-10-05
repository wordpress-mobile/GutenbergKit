import Foundation
import SwiftSoup

/// A raw manifest response from the WordPress editor-assets API endpoint.
///
/// This struct represents the unprocessed server response containing HTML script and style
/// tags as raw strings. It computes a checksum of the original data to detect changes.
///
/// Use `LocalEditorAssetManifest` for a processed version with parsed URLs.
struct RemoteEditorAssetManifest: Codable, Equatable {

    /// The JSON structure returned by the server.
    struct RawManifest: Codable, Equatable {
        let scripts: String
        let styles: String
        let allowedBlockTypes: [String]

        enum CodingKeys: String, CodingKey {
            case scripts
            case styles
            case allowedBlockTypes = "allowed_block_types"
        }

        static let empty = RawManifest(scripts: "", styles: "", allowedBlockTypes: [])
    }

    /// The raw HTML containing `<script>` tags from the server.
    let scripts: String

    /// The raw HTML containing `<link>` stylesheet tags from the server.
    let styles: String

    /// The list of block type identifiers allowed by the site (e.g., "core/paragraph").
    let allowedBlockTypes: [String]

    /// A SHA-256 checksum of the original JSON data.
    ///
    /// Used to detect when the manifest has changed and assets need to be re-downloaded.
    let checksum: String

    /// Creates a remote manifest from raw JSON data.
    ///
    /// - Parameter data: The JSON response from the editor-assets endpoint.
    /// - Throws: A decoding error if the JSON is malformed.
    init(data: Data) throws {
        self.checksum = data.hash()
        let rawManifest = try JSONDecoder().decode(RawManifest.self, from: data)
        self.scripts = rawManifest.scripts
        self.styles = rawManifest.styles
        self.allowedBlockTypes = rawManifest.allowedBlockTypes
    }
}

/// A processed editor asset manifest with parsed URLs ready for downloading.
///
/// This struct transforms a `RemoteEditorAssetManifest` by parsing the raw HTML
/// to extract individual script and stylesheet URLs. It preserves the original
/// HTML for later injection into the editor WebView.
///
/// The manifest is used to:
/// 1. Determine which assets need to be downloaded and cached
/// 2. Provide the raw HTML for rendering in the editor (with URL rewriting)
/// 3. Specify which block types are allowed for this site
public struct LocalEditorAssetManifest: Sendable, Codable, Equatable, Hashable {

    /// URLs of all external scripts that need to be cached locally.
    ///
    /// Extracted from `<script src="...">` tags in the manifest.
    let scripts: [URL]

    /// URLs of all external stylesheets that need to be cached locally.
    ///
    /// Extracted from `<link rel="stylesheet" href="...">` tags in the manifest.
    let styles: [URL]

    /// The block type identifiers that can be used in the editor (e.g., "core/paragraph").
    let allowedBlockTypes: [String]

    /// The original HTML containing `<script>` tags from the server.
    ///
    /// Preserved because it may contain inline scripts that cannot be cached.
    /// URLs are rewritten at render time to use the local cache.
    let rawScripts: String

    /// The original HTML containing `<link>` stylesheet tags from the server.
    ///
    /// Preserved because it may contain inline styles that cannot be cached.
    /// URLs are rewritten at render time to use the local cache.
    let rawStyles: String

    /// A SHA-256 checksum used to detect when assets need to be re-downloaded.
    let checksum: String

    /// All asset URLs (scripts and styles) that need to be cached.
    var assetUrls: [URL] {
        scripts + styles
    }

    private init(
        scripts: [URL],
        styles: [URL],
        allowedBlockTypes: [String],
        rawScripts: String,
        rawStyles: String,
        checksum: String
    ) {
        self.scripts = scripts
        self.styles = styles
        self.allowedBlockTypes = allowedBlockTypes
        self.rawScripts = rawScripts
        self.rawStyles = rawStyles
        self.checksum = checksum
    }

    /// Creates a local manifest by parsing a remote manifest's HTML.
    ///
    /// This operation involves HTML parsing and is expensive. The results
    /// should be cached.
    ///
    /// - Parameter remoteManifest: The raw manifest from the server.
    /// - Throws: An error if HTML parsing fails.
    init(remoteManifest: RemoteEditorAssetManifest) throws {
        self.allowedBlockTypes = remoteManifest.allowedBlockTypes

        let html = """
      <html>
          <head>
          \(remoteManifest.scripts)
          \(remoteManifest.styles)
          </head>
          <body></body>
      </html>
      """

        let document = try SwiftSoup.parse(html)
        self.rawScripts = remoteManifest.scripts
        self.rawStyles = remoteManifest.styles
        self.checksum = remoteManifest.checksum

        self.scripts = try document.select("script[src]").map {
            Self.normalizeAssetLink(try $0.attr("src"))
        }.compactMap { URL(string: $0) }

        self.styles = try document.select(#"link[rel="stylesheet"][href]"#).map {
            Self.normalizeAssetLink(try $0.attr("href"))
        }.compactMap { URL(string: $0) }
    }

    /// Normalizes protocol-relative URLs (e.g., `//example.com/script.js`) to use HTTPS.
    ///
    /// - Parameter link: The URL string to normalize.
    /// - Returns: The normalized URL string with an explicit scheme.
    private static func normalizeAssetLink(_ link: String) -> String {
        if link.starts(with: "//") {
            return "https:\(link)"
        }

        return link
    }

    /// Renders the manifest's scripts and styles as HTML with rewritten URLs that reference the application's custom URL scheme.
    ///
    /// - Parameter configuration: The editor configuration specifying the site scheme.
    /// - Returns: HTML <script> and <style> tags
    /// - Throws: An error if HTML parsing fails.
    func buildEditorRepresentation(
        for configuration: EditorConfiguration
    ) throws -> RemoteEditorAssetManifest.RawManifest {

        // If this site doesn't use plugins or theme styles, there's no work to do here.
        guard configuration.shouldUsePlugins || configuration.shouldUseThemeStyles else {
            return .empty
        }

        let html = """
      <html>
          <head>\(self.rawStyles)</head>
          <body>\(self.rawScripts)</body>
      </html>
      """
        let document = try SwiftSoup.parse(html)

        for script in try document.select("script[src]") {
            if let src = try? script.attr("src") {
                let link = self.resolveAssetLink(src, scheme: Constants.EditorAssetLibrary.urlScheme)
                try script.attr("src", link)
            }
        }

        for stylesheet in try document.select(#"link[rel="stylesheet"][href]"#) {
            if let href = try? stylesheet.attr("href") {
                let link = self.resolveAssetLink(href, scheme: Constants.EditorAssetLibrary.urlScheme)
                try stylesheet.attr("href", link)
            }
        }

        let scripts = try document.head()?.html() ?? ""
        let styles = try document.body()?.html() ?? ""

        return RemoteEditorAssetManifest.RawManifest(
            scripts: scripts,
            styles: styles,
            allowedBlockTypes: self.allowedBlockTypes
        )
    }

    /// Rewrites an asset URL to use the specified scheme.
    ///
    /// - Parameters:
    ///   - link: The original asset URL string.
    ///   - scheme: The scheme to use (e.g., "https"). Defaults to "https".
    /// - Returns: The URL string with the new scheme, or the original if parsing fails.
    func resolveAssetLink(_ link: String, scheme: String) -> String {

        var components = URLComponents(string: link)

        // If this is a nonsense link, don't try to process it further
        if components?.host == nil || components?.path == nil {
            return link
        }

        components?.scheme = scheme

        guard let url = components?.url else {
            return link
        }

        return url.absoluteString
    }

    /// An empty manifest for sites that don't support the editor-assets endpoint.
    static let empty = LocalEditorAssetManifest(
        scripts: [],
        styles: [],
        allowedBlockTypes: [],
        rawScripts: "",
        rawStyles: "",
        checksum: "empty"
    )
}
