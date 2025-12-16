import Foundation

/// A collection of data fetched from the WordPress REST API required to initialize the editor.
///
/// This struct bundles together all the pre-fetched dependencies needed before the editor
/// can be displayed. Fetching these dependencies ahead of time allows the editor to load
/// quickly without blocking on network requests.
///
/// Dependencies include:
/// - Editor settings (theme styles, colors, typography, etc.)
/// - Cached plugin/theme assets (JavaScript and CSS files)
/// - Preloaded API responses (post types, taxonomies, etc.)
public struct EditorDependencies: Sendable, Equatable, Hashable {
  /// Configuration and styling information for the editor.
  public let editorSettings: EditorSettings

  /// Cached JavaScript and CSS assets for plugins and themes.
  public let assetBundle: EditorAssetBundle

  /// Pre-fetched API responses to avoid network requests during editor initialization.
  ///
  /// This is `nil` if preloading is disabled or no preload data is available.
  public let preloadList: EditorPreloadList?

    init(
        editorSettings: EditorSettings,
        assetBundle: EditorAssetBundle,
        preloadList: EditorPreloadList?
    ) {
        self.editorSettings = editorSettings
        self.assetBundle = assetBundle
        self.preloadList = preloadList
    }
}
