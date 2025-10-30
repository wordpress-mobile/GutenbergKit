import SwiftUI

struct PatternItemView: View {
    let pattern: PatternType
    let onSelected: () -> Void

    var body: some View {
        Button(action: onSelected) {
            VStack(alignment: .leading, spacing: 8) {
                BlockPreviewView(
                    html: pattern.previewHTML,
                    viewportWidth: pattern.viewportWidth
                )
                .frame(height: 120)
                .cornerRadius(8)
                .clipped()

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
            .background(Color(uiColor: .systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}
