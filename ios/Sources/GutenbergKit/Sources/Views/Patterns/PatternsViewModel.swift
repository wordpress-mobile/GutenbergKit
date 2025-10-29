import Foundation
import Combine

@MainActor
final class PatternsViewModel: ObservableObject {
    @Published var searchText = ""
    private let allPatterns: [PatternType]

    init(patterns: [PatternType]) {
        self.allPatterns = patterns
    }

    var sections: [PatternSection] {
        let patterns = filteredPatterns

        // Group patterns by category
        let grouped = Dictionary(grouping: patterns) { pattern in
            pattern.category ?? "other"
        }

        // Create sections sorted by category name
        return grouped.map { category, patterns in
            PatternSection(
                category: category,
                name: category.capitalized,
                patterns: patterns.sorted { $0.title < $1.title }
            )
        }
        .sorted { $0.name < $1.name }
    }

    private var filteredPatterns: [PatternType] {
        guard !searchText.isEmpty else {
            return allPatterns
        }

        return allPatterns.filter { pattern in
//            pattern.matches(query: searchText)

            // TODO: add search
            true
        }
    }
}
