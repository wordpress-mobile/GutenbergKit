import Foundation

struct PatternType: Decodable, Identifiable {
    let name: String
    let title: String
    let content: String
    let previewHTML: String
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

extension PatternType: Searchable {
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
    let patterns: [PatternType]
}
