import Foundation
import Combine

@MainActor
final class PatternsViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var error: Error?
    @Published private var allPatterns: [PatternType] = []

    init() {}

    func loadPatterns(using loader: () async throws -> [PatternType]) async {
        // Don't reload if already loaded or loading
        guard !isLoading && allPatterns.isEmpty else {
            return
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let patterns = try await loader()
            self.allPatterns = patterns
        } catch {
            self.error = error
            print("Failed to load patterns: \(error)")
        }
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
