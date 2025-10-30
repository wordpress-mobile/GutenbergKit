import SwiftUI

struct PatternItemView: View {
    let pattern: PatternType
    let onSelected: () -> Void

    private let previewWidth: CGFloat = 140

    var body: some View {
        Button(action: onSelected) {
            HStack(alignment: .top, spacing: 16) {
                // Preview on the left
                BlockPreviewView(pattern: pattern)
                    .frame(width: previewWidth)

                // Title and description on the right
                VStack(alignment: .leading, spacing: 8) {
                    Text(pattern.title)
                        .font(.body)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(Color.primary)

                    if let description = pattern.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(Color.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(12)
            .background(Color(uiColor: .systemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}
