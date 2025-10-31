import SwiftUI

/// Displays a category section with horizontal scrolling pattern previews
struct PatternGridSection: View {
    let section: PatternSection
    let onPatternSelected: (Pattern) -> Void

    @Environment(\.htmlPreviewMemoryCache) private var memoryCache

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category header with navigation
            NavigationLink {
                PatternListView(section: section, onPatternSelected: onPatternSelected)
                    .environment(\.htmlPreviewMemoryCache, memoryCache) // Important
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
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

            // Horizontal scrolling previews - shows all patterns
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(section.patterns) { pattern in
                        PatternCardView(
                            pattern: pattern,
                            onSelected: {
                                onPatternSelected(pattern)
                            },
                            style: .horizontal(height: 140, maxWidth: 240)
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
