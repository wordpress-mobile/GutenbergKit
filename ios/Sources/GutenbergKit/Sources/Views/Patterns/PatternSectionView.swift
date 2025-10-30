import SwiftUI

/// Displays patterns in a List with 2 items per row for proper cell reuse
struct PatternGridSection: View {
    let section: PatternSection
    let onPatternSelected: (PatternType) -> Void

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

    /// Groups patterns into rows of 2
    private var patternRows: [[PatternType]] {
        var rows: [[PatternType]] = []
        var currentRow: [PatternType] = []

        for pattern in displayedPatterns {
            currentRow.append(pattern)
            if currentRow.count == 2 {
                rows.append(currentRow)
                currentRow = []
            }
        }

        // Add remaining pattern(s) in the last row
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }

    var body: some View {
        ForEach(Array(patternRows.enumerated()), id: \.offset) { index, rowPatterns in
            PatternRowView(
                patterns: rowPatterns,
                onPatternSelected: onPatternSelected
            )
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }

        if hasMorePatterns {
            toggleButton
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
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
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }
}

/// A row containing 1 or 2 pattern items
struct PatternRowView: View {
    let patterns: [PatternType]
    let onPatternSelected: (PatternType) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(patterns) { pattern in
                PatternItemView(
                    pattern: pattern,
                    onSelected: {
                        onPatternSelected(pattern)
                    }
                )
                .frame(maxWidth: .infinity)
            }

            // Add spacer if only one pattern in row to maintain layout
            if patterns.count == 1 {
                Color.clear
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
