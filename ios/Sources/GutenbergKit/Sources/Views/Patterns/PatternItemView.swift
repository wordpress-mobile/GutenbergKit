import SwiftUI

struct PatternItemView: View {
    let pattern: PatternType
    let onSelected: () -> Void

    @State private var previewImage: UIImage?
    @State private var isLoadingPreview = false
    @State private var previewError = false

    var body: some View {
        Button(action: onSelected) {
            VStack(alignment: .leading, spacing: 8) {
                preview

                Text(pattern.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let description = pattern.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var preview: some View {
        if let previewImage {
            Image(uiImage: previewImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .background(Color.white)
                .cornerRadius(8)
                .clipped()
        } else if isLoadingPreview {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(uiColor: .tertiarySystemBackground))
                .frame(height: 120)
                .overlay {
                    ProgressView()
                }
        } else if previewError {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(uiColor: .tertiarySystemBackground))
                .frame(height: 120)
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
                .frame(height: 120)
                .task {
                    await loadPreview()
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
            let image = try await PatternPreviewLoader.shared.loadPreview(for: pattern)
            previewImage = image
        } catch {
            print("Failed to load pattern preview: \(error)")
            previewError = true
        }
    }
}
