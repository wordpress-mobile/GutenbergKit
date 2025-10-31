import SwiftUI
import UIKit

/// A view that displays a block pattern preview using HTMLPreviewRenderer
struct BlockPreviewView: View {
    let pattern: Pattern
    let maximumDimension: CGFloat

    @State private var previewImage: UIImage?
    @State private var isLoadingFailed = false
    @Environment(\.htmlPreviewMemoryCache) private var memoryCache
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .cornerRadius(10)
                    .padding(8)
                    .clipped()
            } else if isLoadingFailed {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(uiColor: .tertiarySystemBackground))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await loadPreview()
        }
    }

    private func loadPreview() async {
        guard previewImage == nil, !isLoadingFailed else {
            return
        }
        do {
            let targetSize = CGSize(width: maximumDimension, height: maximumDimension)
            if let cachedImage = memoryCache?.image(for: pattern.name, size: targetSize) {
                previewImage = cachedImage
                return
            }
            let fullSizeImage = try await HTMLPreviewRenderer.shared.render(
                html: pattern.content,
                viewportWidth: pattern.viewportWidth ?? 1200
            )
            try Task.checkCancellation()

            let thumbnail = await createThumbnail(
                from: fullSizeImage,
                maximumDimension: maximumDimension,
                scale: displayScale
            )

            memoryCache?.setImage(thumbnail, for: pattern.name, size: targetSize)
            previewImage = thumbnail
        } catch is CancellationError {
            return // Task was cancelled, don't show error
        } catch {
            print("Failed to render pattern preview: \(error)")
            isLoadingFailed = true
        }
    }

    /// Creates a thumbnail from an image using preparingThumbnail
    private func createThumbnail(from image: UIImage, maximumDimension: CGFloat, scale: CGFloat) async -> UIImage {
        // Calculate the thumbnail size in points maintaining aspect ratio
        // Scale so that the larger dimension fits within maximumDimension
        let aspectRatio = image.size.width / image.size.height
        let thumbnailSizePoints: CGSize

        if image.size.width > image.size.height {
            // Width is larger - constrain by width
            let width = min(maximumDimension, image.size.width)
            thumbnailSizePoints = CGSize(width: width, height: width / aspectRatio)
        } else {
            // Height is larger - constrain by height
            let height = min(maximumDimension, image.size.height)
            thumbnailSizePoints = CGSize(width: height * aspectRatio, height: height)
        }

        // Convert to pixel dimensions for preparingThumbnail
        let thumbnailSizePixels = CGSize(
            width: thumbnailSizePoints.width * scale,
            height: thumbnailSizePoints.height * scale
        )

        let thumbnail = await image.byPreparingThumbnail(ofSize: thumbnailSizePixels)
        return thumbnail ?? image
    }
}
