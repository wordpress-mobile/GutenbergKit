import UIKit
import SwiftUI

/// Memory cache for HTML preview thumbnails.
///
/// Stores resized thumbnails keyed by pattern name and target size.
/// This cache is designed to be created at the view level and will
/// automatically deallocate when the view is dismissed, conserving resources.
@MainActor
final class HTMLPreviewMemoryCache: ObservableObject {
    private let cache = NSCache<NSString, UIImage>()

    init(countLimit: Int = 200) {
        cache.countLimit = countLimit
    }

    /// Generates a cache key from pattern name and size
    private func cacheKey(patternName: String, size: CGSize) -> String {
        "\(patternName)-\(Int(size.width))x\(Int(size.height))"
    }

    /// Retrieves an image from the cache
    func image(for patternName: String, size: CGSize) -> UIImage? {
        let key = cacheKey(patternName: patternName, size: size)
        return cache.object(forKey: key as NSString)
    }

    /// Stores an image in the cache
    func setImage(_ image: UIImage, for patternName: String, size: CGSize) {
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
