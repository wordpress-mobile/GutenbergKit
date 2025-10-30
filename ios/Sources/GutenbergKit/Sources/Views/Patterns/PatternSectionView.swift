import SwiftUI

struct PatternSectionView: View {
    let section: PatternSection
    let onPatternSelected: (PatternType) -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var columnWidth = 150
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
        VStack(alignment: .leading, spacing: 16) {
            Text(section.name)
                .font(.headline)
                .foregroundStyle(Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            grid

            if hasMorePatterns {
                toggleButton
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: columnWidth, maximum: columnWidth * 1.5), spacing: 12)], spacing: 12) {
            ForEach(displayedPatterns) { pattern in
                PatternItemView(pattern: pattern) {
                    onPatternSelected(pattern)
                }
            }
        }
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
    }
}
