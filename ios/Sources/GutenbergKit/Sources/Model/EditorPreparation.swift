import Foundation

/// What preparing an editor's dependencies came to: the dependencies, and whatever went wrong getting them.
///
/// The two always come together. A dependency that couldn't be fetched isn't withheld — the copy on disk
/// stands in for it where there is one, however old — and the failure to fetch it isn't hidden behind the copy.
/// So there is always something to give an editor, and always a way to tell that it isn't what was asked for.
public struct EditorPreparation: Sendable {

    /// The best dependencies available: each one fetched as the cache policy asked where that worked, from
    /// disk where it didn't, and empty where there was nothing on disk either.
    public let dependencies: EditorDependencies

    /// Everything about ``dependencies`` that isn't as the cache policy asked. Empty when nothing is.
    public let failures: [Failure]

    /// One of the things an editor's dependencies are made of.
    public enum Dependency: Sendable, Hashable, CaseIterable {
        /// The editor settings: theme styles, colors, typography and so on.
        case editorSettings
        /// The plugin and theme assets.
        case assetBundle
        /// The post being edited.
        case post
        /// The schema of the post's type.
        case postType
        /// The site's post types.
        case postTypes
        /// The active theme.
        case activeTheme
        /// The schema of the site's settings.
        case settingsOptions
    }

    /// One way ``dependencies`` fall short of what the cache policy asked for.
    public enum Failure: Sendable {
        /// A dependency couldn't be fetched.
        ///
        /// - Parameters:
        ///   - error: Why not.
        ///   - usingCopyOnDisk: Whether ``dependencies`` hold the copy on disk in its place, however old. If
        ///     not, there was none, and they hold nothing for it.
        case notFetched(Dependency, error: any Error, usingCopyOnDisk: Bool)

        /// The asset bundle is missing assets that the site's manifest lists: these failed to download. The
        /// editor loads without them, and they're tried again the next time dependencies are prepared.
        case assetsMissing([URL])

        /// These assets failed to download, and the asset bundle holds the copy an earlier bundle had of each
        /// in its place. The editor loads those copies, and the assets are asked for again the next time the
        /// site's asset manifest is checked.
        case assetsNotRefreshed([URL])

        /// The dependency the failure is about.
        public var dependency: Dependency {
            switch self {
            case .notFetched(let dependency, _, _): dependency
            case .assetsMissing, .assetsNotRefreshed: .assetBundle
            }
        }
    }

    /// Whether every dependency is as the cache policy asked.
    public var isComplete: Bool {
        failures.isEmpty
    }
}
