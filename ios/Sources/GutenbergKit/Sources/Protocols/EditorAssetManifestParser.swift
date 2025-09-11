import Foundation
import RegexBuilder
import OSLog

public protocol EditorAssetManifestParser {
    func extractStyleURLs(from html: String) throws -> [String]
    func extractScriptURLs(from html: String) throws -> [String]
}

// A default dependency-free manifest transformer that uses Regex. For better performance and error-handling,
// use a real HTML parser (included in this package)
@available(iOS 16.0, *)
public class DefaultEditorAssetManifestParser: EditorAssetManifestParser {

    static let styles = #/<link[^>]+href=['"](?'url'[^'"]+)['"]/#
    static let scripts = #/<script[^>]+src=['"](?'url'[^'"]+)['"]/#

    public func extractStyleURLs(from html: String) throws -> [String] {
        return html.matches(of: Self.styles).map { String($0.output.url) }
    }

    public func extractScriptURLs(from html: String) throws -> [String] {
        return html.matches(of: Self.scripts).map { String($0.output.url) }
    }
}

public struct AssetManifestParserProvider {
    public static var `default`: EditorAssetManifestParser {
        if #available(iOS 16.0, *) {
            Logger.gbkit.warning("Warning: using the default `AssetManifestParser` – this is not recommended. You can use the included `SwiftSoupAssetManifestParser` or create your own.")

            return DefaultEditorAssetManifestParser()
        } else {
            preconditionFailure("You must provide an implementation of `EditorAssetManifestParser`. You can use the included `SwiftSoupAssetManifestParser` or create your own.")
        }
    }
}
