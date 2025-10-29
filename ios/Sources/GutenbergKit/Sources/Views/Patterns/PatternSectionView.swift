import SwiftUI

struct PatternSectionView: View {
    let section: PatternSection
    let onPatternSelected: (PatternType) -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var columnWidth = 150
    @ScaledMetric(relativeTo: .largeTitle) private var padding = 20
    @State private var isExpanded = false

    private let initialDisplayCount = 12

    private var displayedPatterns: [PatternType] {
        if !isExpanded && section.patterns.count > initialDisplayCount {
            return Array(section.patterns.prefix(initialDisplayCount))
        }
        return section.patterns
    }

    private var hasMorePatterns: Bool {
        section.patterns.count > initialDisplayCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(section.name)
                .font(.headline)
                .foregroundStyle(Color.secondary)
                .padding(.leading, padding)
                .frame(maxWidth: .infinity, alignment: .leading)

            grid

            if hasMorePatterns {
                toggleButton
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 10)
        .cardStyle()
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: columnWidth, maximum: columnWidth * 1.5), spacing: 12)], spacing: 12) {
            ForEach(displayedPatterns) { pattern in
                PatternItemView(pattern: pattern) {
                    onPatternSelected(pattern)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private var toggleButton: some View {
        Button {
            withAnimation {
                isExpanded.toggle()
            }
        } label: {
            HStack {
                Text(isExpanded ? "Show Less" : "Show More")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.secondary)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(Color.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }
}
