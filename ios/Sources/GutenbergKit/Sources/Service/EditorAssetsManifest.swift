import Foundation
import CryptoKit
import SwiftSoup

struct EditorAssetsManifest: Codable {
    var scripts: String
    var styles: String
    var allowedBlockTypes: [String]

    enum CodingKeys: String, CodingKey {
        case scripts
        case styles
        case allowedBlockTypes = "allowed_block_types"
    }

    func parseAssetLinks(defaultScheme: String? = nil) throws -> [String] {
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
