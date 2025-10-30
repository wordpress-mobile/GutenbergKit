import SwiftUI
import UIKit

/// A view that displays a block pattern preview using HTMLPreviewRenderer
struct BlockPreviewView: View {
    let pattern: PatternType

    private let previewHeight: CGFloat = 120

    @State private var previewImage: UIImage?
    @State private var isLoadingPreview = false
    @State private var previewError = false

    var body: some View {
        Group {
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: previewHeight)
                    .background(Color.white)
                    .cornerRadius(8)
                    .clipped()
            } else if isLoadingPreview {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(uiColor: .tertiarySystemBackground))
                    .frame(height: previewHeight)
                    .overlay {
                        ProgressView()
                    }
            } else if previewError {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(uiColor: .tertiarySystemBackground))
                    .frame(height: previewHeight)
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "square.grid.2x2")
                                .font(.title2)
                                .foregroundStyle(Color.secondary)
                            Text("Preview unavailable")
                                .font(.caption2)
                                .foregroundStyle(Color.secondary)
                        }
                    }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(uiColor: .tertiarySystemBackground))
                    .frame(height: previewHeight)
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
            let image = try await HTMLPreviewRenderer.shared.render(
                html: pattern.previewHTML,
                viewportWidth: pattern.viewportWidth ?? 1200,
                maxHeight: previewHeight,
                cacheKey: pattern.name
            )
            previewImage = image
        } catch {
            print("Failed to render pattern preview: \(error)")
            previewError = true
        }
    }
}
