import Foundation
import Combine

@MainActor
final class PatternsViewModel: ObservableObject {
    @Published var searchText = ""
    @Published private(set) var sections: [PatternSection] = []

    private let allSections: [PatternSection]
    private var cancellables = Set<AnyCancellable>()

    init(patterns: [PatternType]) {
        // Group patterns by category to create sections
        let grouped = Dictionary(grouping: patterns) { pattern in
            pattern.category ?? "other"
        }

        // Create sections sorted by category name
        self.allSections = grouped.map { category, patterns in
            PatternSection(
                category: category,
                name: category.capitalized,
                patterns: patterns.sorted { $0.title < $1.title }
            )
        }
        .sorted { $0.name < $1.name }

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
                let filtered = SearchEngine<PatternType>()
                    .search(query: searchText, in: section.patterns)
                return filtered.isEmpty ? nil : PatternSection(
                    category: section.category,
                    name: section.name,
                    patterns: filtered
                )
            }
        }
    }
}
