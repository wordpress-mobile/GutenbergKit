import SwiftUI

/// Displays a category section with horizontal scrolling pattern previews
struct PatternGridSection: View {
    let section: PatternSection
    let onPatternSelected: (Pattern) -> Void
    let viewportWidth: Int?

    @Environment(\.htmlPreviewMemoryCache) private var memoryCache

    init(section: PatternSection, onPatternSelected: @escaping (Pattern) -> Void, viewportWidth: Int? = nil) {
        self.section = section
        self.onPatternSelected = onPatternSelected
        self.viewportWidth = viewportWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
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
            if section.showPreviews {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(section.patterns) { pattern in
                            PatternCardView(
                                pattern: pattern,
                                onSelected: {
                                    onPatternSelected(pattern)
                                },
                                style: .horizontal(height: 140, maxWidth: 240),
                                viewportWidth: viewportWidth
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}
