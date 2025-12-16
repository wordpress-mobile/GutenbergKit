import Foundation

public struct Paths {
    public static let defaultStorageRoot = URL.applicationSupportDirectory.appending(path: "GutenbergKit")

    public static func storageRoot(for configuration: EditorConfiguration) -> URL {
        defaultStorageRoot.appending(path: configuration.siteId)
    }

    public static let defaultCacheRoot = URL.cachesDirectory.appending(path: "GutenbergKit")

    public static func cacheRoot(for configuration: EditorConfiguration) -> URL {
        defaultCacheRoot.appending(path: configuration.siteId)
    }
}
