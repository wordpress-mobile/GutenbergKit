import Foundation
import Combine

@MainActor
final class PatternsViewModel: ObservableObject {
    @Published var searchText = ""
    @Published private(set) var sections: [PatternSection] = []

    private let allSections: [PatternSection]
    private var cancellables = Set<AnyCancellable>()

    init(patterns: [Pattern], patternCategories: [PatternCategory] = []) {
        let categoryLabels = Dictionary(
            uniqueKeysWithValues: patternCategories.map { ($0.name, $0.label) }
        )
        // Build a mapping of category -> patterns in input order
        var categoryPatterns: [String: [Pattern]] = [:]
        let uncategorizedKey = "uncategorized"

        for pattern in patterns {
            let patternCategories = pattern.categories?.filter { !$0.isEmpty } ?? []

            if patternCategories.isEmpty {
                // Handle uncategorized patterns
                categoryPatterns[uncategorizedKey, default: []].append(pattern)
            } else {
                // Add pattern to all its categories
                for category in patternCategories {
                    categoryPatterns[category, default: []].append(pattern)
                }
            }
        }

        // Create category sections
        var sections: [PatternSection] = categoryPatterns.map { category, patterns in
            let displayName: String
            if category == uncategorizedKey {
                // TODO: CMM-874 - Localize "Uncategorized"
                displayName = "Uncategorized"
            } else {
                displayName = categoryLabels[category] ?? category.capitalized
            }

            // Separate primary and secondary patterns, then concatenate
            let primaryPatterns = patterns.filter { $0.categories?.first == category }
            let secondaryPatterns = patterns.filter { $0.categories?.first != category }
            let sortedPatterns = primaryPatterns + secondaryPatterns

            return PatternSection(
                category: category,
                name: displayName,
                patterns: sortedPatterns
            )
        }

        // Sort sections alphabetically using localized comparison
        // Uncategorized always goes last
        sections.sort { section1, section2 in
            if section1.category == uncategorizedKey {
                return false
            }
            if section2.category == uncategorizedKey {
                return true
            }
            return section1.name.localizedCompare(section2.name) == .orderedAscending
        }

        // Create "All" section at the top (no previews)
        // TODO: CMM-874 - Localize "All"
        if !patterns.isEmpty {
            sections = [PatternSection(
                category: "all",
                name: "All",
                patterns: patterns,
                showPreviews: false
            )] + sections
        }

        self.allSections = sections
        self.sections = allSections

        setupSearchObserver()
    }

    private func setupSearchObserver() {
        $searchText
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] searchText in
                self?.updateFilteredSections(searchText: searchText)
            }
            .store(in: &cancellables)
    }

    private func updateFilteredSections(searchText: String) {
        if searchText.isEmpty {
            sections = allSections
        } else {
            sections = allSections.compactMap { section in
                let filtered = SearchEngine<Pattern>()
                    .search(query: searchText, in: section.patterns)
                return filtered.isEmpty ? nil : PatternSection(
                    category: section.category,
                    name: section.name,
                    patterns: filtered,
                    showPreviews: section.showPreviews
                )
            }
        }
    }
}
