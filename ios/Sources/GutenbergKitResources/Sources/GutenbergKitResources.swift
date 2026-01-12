import Foundation

public struct GutenbergKitResources {

    public static func resourcesURL() -> URL {
        Bundle.module.resourceURL!
    }

    public static func indexURL() -> URL {
        Bundle.module.url(forResource: "index", withExtension: "html")!
    }

    /// Loads the Gutenberg CSS from the bundled assets.
    public static func loadGutenbergCSS() -> String? {
        let assetsDirectory = resourcesURL().appendingPathComponent("assets")
        guard let files = try? FileManager.default.contentsOfDirectory(at: assetsDirectory, includingPropertiesForKeys: nil),
              let cssURL = files.first(where: { $0.lastPathComponent.hasPrefix("index-") && $0.lastPathComponent.hasSuffix(".css") }),
              let css = try? String(contentsOf: cssURL, encoding: .utf8) else {
            assertionFailure("Failed to load Gutenberg CSS from bundle")
            return nil
        }
        return css
    }
}
