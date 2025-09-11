import Foundation
import GutenbergKit
import SwiftSoup

public struct GutenbergKitAssetManifestParser: EditorAssetManifestParser {

    public init(){}

    public func extractStyleURLs(from html: String) throws -> [String] {
        let html = """
            <html>
                <head>
                \(html)
                </head>
                <body></body>
            </html>
            """
        let document = try SwiftSoup.parse(html)

        return try document.select(#"link[rel="stylesheet"][href]"#).map {
            try $0.attr("href")
        }
    }

    public func extractScriptURLs(from html: String) throws -> [String] {
        let html = """
            <html>
                <head>
                \(html)
                </head>
                <body></body>
            </html>
            """
        let document = try SwiftSoup.parse(html)

        return try document.select(#"script[src]"#).map {
            try $0.attr("src")
        }
    }
}
