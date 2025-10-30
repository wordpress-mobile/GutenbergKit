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
            let image = try await HTMLPreviewRenderer.shared.render(
                html: pattern.previewHTML,
                viewportWidth: pattern.viewportWidth ?? 1200,
                maxHeight: previewHeight
            )
            previewImage = image
        } catch {
            print("Failed to render pattern preview: \(error)")
            previewError = true
        }
    }
}
