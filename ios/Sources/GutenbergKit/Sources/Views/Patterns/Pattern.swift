import Foundation

struct PatternCategory: Decodable {
    /// Category slug/identifier (e.g., "gallery")
    let name: String
    /// Localized display name (e.g., "Galerie" in French)
    let label: String
}

struct Pattern: Decodable, Identifiable {
    /// Example: `"core/query-standard-posts"`
    let name: String
    let title: String
    /// Containts HTML with Gutenberg blocks.
    let content: String
    let blockTypes: [String]?
    let categories: [String]?
    let description: String?
    let keywords: [String]?
    let source: String?
    let viewportWidth: Int?

    // Computed property for Identifiable
    var id: String { name }

    // Get primary category for display
    var category: String? {
        categories?.first
    }
}

extension Pattern: Searchable {
    /// Sets the searchable fields in the order of priority
    func searchableFields() -> [SearchableField] {
        var fields: [SearchableField] = []

        if !title.isEmpty {
            fields.append(SearchableField(content: title, weight: 10.0, allowFuzzyMatch: true))
        }

        if !name.isEmpty {
            fields.append(SearchableField(content: name, weight: 8.0, allowFuzzyMatch: false))
        }

        (keywords ?? []).forEach { keyword in
            if !keyword.isEmpty {
                fields.append(SearchableField(content: keyword, weight: 5.0, allowFuzzyMatch: true))
            }
        }

        if let description, !description.isEmpty {
            fields.append(SearchableField(content: description, weight: 2.0, allowFuzzyMatch: false))
        }

        if let category, !category.isEmpty {
            fields.append(SearchableField(content: category, weight: 2.0, allowFuzzyMatch: true))
        }

        return fields
    }
}

struct PatternSection: Identifiable, Decodable {
    var id: String { category }
    let category: String
    let name: String
    let patterns: [Pattern]
    let showPreviews: Bool

    init(category: String, name: String, patterns: [Pattern], showPreviews: Bool = true) {
        self.category = category
        self.name = name
        self.patterns = patterns
        self.showPreviews = showPreviews
    }
}
