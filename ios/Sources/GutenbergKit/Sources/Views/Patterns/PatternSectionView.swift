import SwiftUI

/// Displays a category section with horizontal scrolling pattern previews
struct PatternGridSection: View {
    let section: PatternSection
    let onPatternSelected: (PatternType) -> Void

    private let previewCount = 6

    private var displayedPatterns: [PatternType] {
        Array(section.patterns.prefix(previewCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category header with navigation
            NavigationLink {
                PatternListView(section: section, onPatternSelected: onPatternSelected)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.name)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.primary)

                        Text("\(section.patterns.count) patterns")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Horizontal scrolling previews
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(displayedPatterns) { pattern in
                        PatternCardView(
                            pattern: pattern,
                            onSelected: {
                                onPatternSelected(pattern)
                            },
                            style: .horizontal(height: 140)
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
