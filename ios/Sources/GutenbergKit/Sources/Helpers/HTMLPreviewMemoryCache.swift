import UIKit
import SwiftUI

/// Memory cache for HTML preview thumbnails.
///
/// Stores resized thumbnails keyed by pattern name and target size.
/// This cache is designed to be created at the view level and will
/// automatically deallocate when the view is dismissed, conserving resources.
@MainActor
public final class HTMLPreviewMemoryCache: ObservableObject {
    private let cache = NSCache<NSString, UIImage>()

    public init(countLimit: Int = 50) {
        cache.countLimit = countLimit
    }

    /// Generates a cache key from pattern name and size
    private func cacheKey(patternName: String, size: CGSize) -> String {
        return "\(patternName)-\(Int(size.width))x\(Int(size.height))"
    }

    /// Retrieves an image from the cache
    public func image(for patternName: String, size: CGSize) -> UIImage? {
        let key = cacheKey(patternName: patternName, size: size)
        return cache.object(forKey: key as NSString)
    }

    /// Stores an image in the cache
    public func setImage(_ image: UIImage, for patternName: String, size: CGSize) {
        let key = cacheKey(patternName: patternName, size: size)
        cache.setObject(image, forKey: key as NSString)
    }
}

// MARK: - Environment Key

private struct HTMLPreviewMemoryCacheKey: EnvironmentKey {
    static let defaultValue: HTMLPreviewMemoryCache? = nil
}

extension EnvironmentValues {
    var htmlPreviewMemoryCache: HTMLPreviewMemoryCache? {
        get { self[HTMLPreviewMemoryCacheKey.self] }
        set { self[HTMLPreviewMemoryCacheKey.self] = newValue }
    }
}
