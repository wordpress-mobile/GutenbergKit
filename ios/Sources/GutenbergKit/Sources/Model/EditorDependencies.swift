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

  /// Changes the host has to the post that the server doesn't, which the editor opens with as
  /// unsaved edits. See ``withPostEdits(_:)``.
  let postEdits: Data?

    init(
        editorSettings: EditorSettings,
        assetBundle: EditorAssetBundle,
        preloadList: EditorPreloadList?,
        postEdits: Data? = nil
    ) {
        self.editorSettings = editorSettings
        self.assetBundle = assetBundle
        self.preloadList = preloadList
        self.postEdits = postEdits
    }

    /// A copy of these dependencies with `post` as the preloaded post `postID`. See
    /// ``EditorPreloadList/withPost(id:post:)``. Without a preload list, they're returned as
    /// they are.
    public func withPost(id postID: Int, post: Data) -> EditorDependencies {
        EditorDependencies(
            editorSettings: editorSettings,
            assetBundle: assetBundle,
            preloadList: preloadList?.withPost(id: postID, post: post),
            postEdits: postEdits
        )
    }

    /// A copy of these dependencies with `edits` as changes the host has to the post that the
    /// server doesn't.
    ///
    /// The editor opens with them as unsaved edits over the post's saved version, outside the
    /// undo history. When the editor later takes in another copy of the post from the server,
    /// they stay.
    ///
    /// - Parameter edits: A JSON object, in the shape the REST API takes in a write, such as
    ///   `{"excerpt": "Written offline"}`.
    public func withPostEdits(_ edits: Data) -> EditorDependencies {
        EditorDependencies(
            editorSettings: editorSettings,
            assetBundle: assetBundle,
            preloadList: preloadList,
            postEdits: edits
        )
    }
}
