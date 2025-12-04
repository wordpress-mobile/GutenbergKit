#if canImport(UIKit)
import SwiftUI
import UIKit

/// A view that displays a block pattern preview using HTMLPreviewRenderer
struct HTMLPreviewView: View {
    let pattern: Pattern
    let targetSize: CGSize?
    let viewportWidth: Int?

    @State private var previewImage: UIImage?
    @State private var isLoadingFailed = false
    @State private var cachedAspectRatio: CGFloat?
    @Environment(\.htmlPreviewMemoryCache) private var memoryCache
    @EnvironmentObject private var htmlPreviewManager: HTMLPreviewManager
    @Environment(\.displayScale) private var displayScale

    init(pattern: Pattern, targetSize: CGSize?, viewportWidth: Int? = nil) {
        self.pattern = pattern
        self.targetSize = targetSize
        self.viewportWidth = viewportWidth
    }

    var body: some View {
        ZStack {
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .background(Color.white)
                    .clipped()
            } else if isLoadingFailed {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(uiColor: .tertiarySystemBackground))
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "square.grid.2x2")
                                .font(.title2)
                                .foregroundStyle(Color.secondary)
                        }
                    }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .aspectRatio(cachedAspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(pattern.id)-\(viewportWidth?.description ?? "default")") {
            await loadPreview()
        }
    }

    private func loadPreview() async {
        let effectiveViewportWidth = viewportWidth ?? pattern.viewportWidth ?? 1200

        // Load cached aspect ratio to prevent layout jumps
        if cachedAspectRatio == nil {
            cachedAspectRatio = AspectRatioCache.shared.aspectRatio(for: pattern.name, viewportWidth: effectiveViewportWidth)
        }

        do {
            let cacheSize = targetSize ?? .zero
            if let cachedImage = memoryCache?.image(for: pattern.name, size: cacheSize, viewportWidth: viewportWidth) {
                previewImage = cachedImage
                updateAspectRatio(from: cachedImage, viewportWidth: effectiveViewportWidth)
                return
            }
            let fullSizeImage = try await htmlPreviewManager.render(
                html: pattern.content,
                viewportWidth: effectiveViewportWidth
            )
            try Task.checkCancellation()

            let processedImage: UIImage
            if let targetSize {
                processedImage = await createThumbnail(
                    from: fullSizeImage,
                    targetSize: targetSize,
                    scale: displayScale
                )
            } else {
                processedImage = await fullSizeImage.byPreparingForDisplay() ?? fullSizeImage
            }
            memoryCache?.setImage(processedImage, for: pattern.name, size: cacheSize, viewportWidth: viewportWidth)

            try Task.checkCancellation()
            updateAspectRatio(from: processedImage, viewportWidth: effectiveViewportWidth)

            withAnimation {
                previewImage = processedImage
            }
        } catch is CancellationError {
            return // Task was cancelled, don't show error
        } catch {
            isLoadingFailed = true
        }
    }

    /// Updates the cached aspect ratio from an image
    private func updateAspectRatio(from image: UIImage, viewportWidth: Int) {
        let aspectRatio = image.size.width / image.size.height
        cachedAspectRatio = aspectRatio
        AspectRatioCache.shared.setAspectRatio(aspectRatio, for: pattern.name, viewportWidth: viewportWidth)
    }

    /// Creates a thumbnail from an image using preparingThumbnail
    /// The thumbnail will fit within targetSize while maintaining aspect ratio (aspect fit)
    private func createThumbnail(from image: UIImage, targetSize: CGSize, scale: CGFloat) async -> UIImage {
        // Calculate the thumbnail size in points maintaining aspect ratio
        // Scale so that the image fits within both width and height constraints
        let aspectRatio = image.size.width / image.size.height
        let targetAspectRatio = targetSize.width / targetSize.height

        let thumbnailSize: CGSize

        if aspectRatio > targetAspectRatio {
            // Image is wider than target - constrain by width
            let width = min(targetSize.width, image.size.width)
            thumbnailSize = CGSize(width: width, height: width / aspectRatio)
        } else {
            // Image is taller than target - constrain by height
            let height = min(targetSize.height, image.size.height)
            thumbnailSize = CGSize(width: height * aspectRatio, height: height)
        }

        let thumbnail = await image.byPreparingThumbnail(ofSize: CGSize(
            width: thumbnailSize.width * scale,
            height: thumbnailSize.height * scale,
        ))
        return thumbnail ?? image
    }
}

// MARK: - Aspect Ratio Cache

/// Manages aspect ratio caching for pattern previews.
@MainActor
private class AspectRatioCache: ObservableObject {
    static let shared = AspectRatioCache()

    private static let cacheKey = "com.gutenbergkit.preview.aspectRatios"
    private var cache: [String: CGFloat] = [:]

    private init() {
        // Load from UserDefaults
        if let stored = UserDefaults.standard.dictionary(forKey: Self.cacheKey) as? [String: CGFloat] {
            cache = stored
        }
    }

    private func key(for patternName: String, viewportWidth: Int) -> String {
        "\(patternName)-vw\(viewportWidth)"
    }

    func aspectRatio(for patternName: String, viewportWidth: Int) -> CGFloat? {
        return cache[key(for: patternName, viewportWidth: viewportWidth)]
    }

    func setAspectRatio(_ aspectRatio: CGFloat, for patternName: String, viewportWidth: Int) {
        let cacheKey = key(for: patternName, viewportWidth: viewportWidth)
        // Only persist if the value changed
        if cache[cacheKey] != aspectRatio {
            cache[cacheKey] = aspectRatio
            UserDefaults.standard.set(cache, forKey: Self.cacheKey)
        }
    }
}
#endif
