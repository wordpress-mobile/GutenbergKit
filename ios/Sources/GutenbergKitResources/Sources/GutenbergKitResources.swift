import Foundation

/// Provides access to the bundled Gutenberg editor resources (HTML, CSS, JS).
///
/// In local development builds (`GUTENBERGKIT_SWIFT_USE_LOCAL_RESOURCES=1`),
/// resources are loaded from the source target's `Resources/` directory.
/// In release builds, they come from the pre-built `GutenbergKitResources` XCFramework.
public enum GutenbergKitResources {

    /// URL to the editor's `index.html` entry point.
    public static var editorIndexURL: URL {
        guard let url = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Resources") else {
            fatalError("GutenbergKitResources: index.html not found in bundle")
        }
        return url
    }

    /// Base URL for the resources directory.
    ///
    /// Used as the `allowingReadAccessTo:` parameter when loading
    /// the editor HTML into a WKWebView, so the web view can access
    /// sibling assets (JS, CSS) on the local filesystem.
    public static var resourcesDirectoryURL: URL {
        guard let url = Bundle.module.url(forResource: "Resources", withExtension: nil) else {
            fatalError("GutenbergKitResources: Resources directory not found in bundle")
        }
        return url
    }

    /// Loads the Gutenberg CSS from the bundled assets.
    ///
    /// Scans the `Resources/assets/` directory for the Vite-generated
    /// CSS file (`index-<hash>.css`) and returns its contents.
    ///
    /// - Returns: The CSS string, or `nil` if the file could not be loaded.
    public static func loadGutenbergCSS() -> String? {
        guard let assetsURL = Bundle.module.url(forResource: "Resources", withExtension: nil) else {
            assertionFailure("GutenbergKitResources: Resources directory not found in bundle")
            return nil
        }

        let assetsDirectory = assetsURL.appendingPathComponent("assets")
        guard let files = try? FileManager.default.contentsOfDirectory(at: assetsDirectory, includingPropertiesForKeys: nil),
              let cssURL = files.first(where: { $0.lastPathComponent.hasPrefix("index-") && $0.lastPathComponent.hasSuffix(".css") }),
              let css = try? String(contentsOf: cssURL, encoding: .utf8) else {
            assertionFailure("GutenbergKitResources: Failed to load Gutenberg CSS")
            return nil
        }
        return css
    }
}
