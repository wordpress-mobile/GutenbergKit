import SwiftUI
import UIKit

/// Maximum dimension constraint for thumbnail generation
enum MaximumDimension {
    case width(CGFloat)
    case height(CGFloat)
}

/// A view that displays a block pattern preview using HTMLPreviewRenderer
struct BlockPreviewView: View {
    let pattern: Pattern
    let maximumDimension: MaximumDimension

    @State private var previewImage: UIImage?
    @State private var isLoadingPreview = false
    @State private var previewError = false
    @Environment(\.htmlPreviewMemoryCache) private var memoryCache
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(8)
                    .cornerRadius(8)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color(uiColor: .separator).opacity(0.2), lineWidth: 0.5)
                    }
                    .clipped()
            } else if isLoadingPreview {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(uiColor: .tertiarySystemBackground))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if previewError {
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
                    .fill(Color(uiColor: .tertiarySystemBackground))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task {
                        await loadPreview()
                    }
            }
        }
    }

    private func loadPreview() async {
        guard !isLoadingPreview, previewImage == nil, !previewError else {
            return
        }

        isLoadingPreview = true
        defer { isLoadingPreview = false }

        do {
            // Calculate target thumbnail size for cache lookup
            let targetSize = calculateTargetSize(maximumDimension: maximumDimension)

            // Check memory cache first
            if let cachedImage = memoryCache?.image(for: pattern.name, size: targetSize) {
                previewImage = cachedImage
                return
            }

            // Render full-size image
            let fullSizeImage = try await HTMLPreviewRenderer.shared.render(
                html: pattern.content,
                viewportWidth: pattern.viewportWidth ?? 1200
            )

            // Create thumbnail from full-size image
            let thumbnail = createThumbnail(from: fullSizeImage, maximumDimension: maximumDimension, scale: displayScale)

            // Store thumbnail in memory cache
            memoryCache?.setImage(thumbnail, for: pattern.name, size: targetSize)

            previewImage = thumbnail
        } catch {
            print("Failed to render pattern preview: \(error)")
            previewError = true
        }
    }

    /// Calculates the target thumbnail size based on maximum dimension constraint
    private func calculateTargetSize(maximumDimension: MaximumDimension) -> CGSize {
        // Use a standardized size for cache lookup
        // The actual thumbnail will be created to fit this constraint
        switch maximumDimension {
        case .width(let maxWidth):
            return CGSize(width: maxWidth, height: maxWidth)
        case .height(let maxHeight):
            return CGSize(width: maxHeight, height: maxHeight)
        }
    }

    /// Creates a thumbnail from an image using preparingThumbnail
    private func createThumbnail(from image: UIImage, maximumDimension: MaximumDimension, scale: CGFloat) -> UIImage {
        // Calculate the thumbnail size in points maintaining aspect ratio
        let aspectRatio = image.size.width / image.size.height

        let thumbnailSizePoints: CGSize
        switch maximumDimension {
        case .width(let maxWidth):
            let thumbnailWidthPoints = min(maxWidth, image.size.width)
            let thumbnailHeightPoints = thumbnailWidthPoints / aspectRatio
            thumbnailSizePoints = CGSize(width: thumbnailWidthPoints, height: thumbnailHeightPoints)
        case .height(let maxHeight):
            let thumbnailHeightPoints = min(maxHeight, image.size.height)
            let thumbnailWidthPoints = thumbnailHeightPoints * aspectRatio
            thumbnailSizePoints = CGSize(width: thumbnailWidthPoints, height: thumbnailHeightPoints)
        }

        // Convert to pixel dimensions for preparingThumbnail
        let thumbnailSizePixels = CGSize(
            width: thumbnailSizePoints.width * scale,
            height: thumbnailSizePoints.height * scale
        )

        // Use preparingThumbnail for efficient thumbnail generation
        if let thumbnailCGImage = image.preparingThumbnail(of: thumbnailSizePixels)?.cgImage {
            return UIImage(cgImage: thumbnailCGImage, scale: scale, orientation: image.imageOrientation)
        }

        // Return original image if thumbnail generation fails
        return image
    }
}
