import Foundation

struct BlockType: Decodable, Identifiable {
    /// Unique identifier for this block variant. Note that this is NOT the same as `name`.
    /// Multiple blocks can share the same `name` but have different `id` values to represent
    /// different variants with different initial attributes (e.g., core/embed variants for
    /// YouTube, Vimeo, etc.).
    let id: String
    let name: String
    let title: String?
    let description: String?
    let category: String?
    let keywords: [String]?
    var icon: String?
    var iconForeground: String?
    var frecency: Double = 0.0
    var isDisabled = false
    var isSearchOnly = false
    var parents: [String] = []
}

extension BlockType: Searchable {
    /// Sets the searchable fields in the order of priority
    func searchableFields() -> [SearchableField] {
        var fields: [SearchableField] = []

        if let title, !title.isEmpty {
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
