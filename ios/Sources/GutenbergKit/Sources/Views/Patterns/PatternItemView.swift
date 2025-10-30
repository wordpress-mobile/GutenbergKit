import SwiftUI

struct PatternItemView: View {
    let pattern: PatternType
    let onSelected: () -> Void

    // Reserve space for uniform layout
    private let titleHeight: CGFloat = 40  // 2 lines of subheadline text
    private let descriptionHeight: CGFloat = 32  // 2 lines of caption text

    var body: some View {
        Button(action: onSelected) {
            VStack(alignment: .leading, spacing: 8) {
                // Preview
                BlockPreviewView(pattern: pattern)

                // Title - always reserve space
                Text(pattern.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity, minHeight: titleHeight, alignment: .topLeading)

                // Description - always reserve space for uniform height
                Group {
                    if let description = pattern.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(Color.secondary)
                    } else {
                        Text(" ")
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: descriptionHeight, alignment: .topLeading)
            }
            .padding(12)
            .background(Color(uiColor: .systemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}
