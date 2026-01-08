import Foundation

public struct GutenbergKitResources {

    /// Loads the Gutenberg CSS from the bundled assets.
    public static func loadGutenbergCSS() -> String? {
        guard let assetsURL = Bundle.module.url(forResource: "Gutenberg", withExtension: nil) else {
            assertionFailure("Gutenberg resource not found in bundle")
            return nil
        }

        let assetsDirectory = assetsURL.appendingPathComponent("assets")
        guard let files = try? FileManager.default.contentsOfDirectory(at: assetsDirectory, includingPropertiesForKeys: nil),
              let cssURL = files.first(where: { $0.lastPathComponent.hasPrefix("index-") && $0.lastPathComponent.hasSuffix(".css") }),
              let css = try? String(contentsOf: cssURL, encoding: .utf8) else {
            assertionFailure("Failed to load Gutenberg CSS from bundle")
            return nil
        }
        return css
    }
}
