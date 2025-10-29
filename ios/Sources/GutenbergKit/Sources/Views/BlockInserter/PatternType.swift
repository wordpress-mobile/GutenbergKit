import Foundation

struct PatternType: Decodable, Identifiable {
    let id: String
    let name: String
    let title: String
    let description: String?
    let category: String?
    let keywords: [String]?
    let content: String
    let patternType: PatternSource
    let syncStatus: SyncStatus?
    let viewportWidth: Int

    enum PatternSource: String, Decodable {
        case user
        case theme
        case directory
    }

    enum SyncStatus: String, Decodable {
        case synced = "fully"
        case unsynced
    }
}

extension PatternType: Searchable {
    /// Sets the searchable fields in the order of priority
    func searchableFields() -> [SearchableField] {
        var fields: [SearchableField] = []

        fields.append(SearchableField(content: title, weight: 10.0, allowFuzzyMatch: true))
        fields.append(SearchableField(content: name, weight: 8.0, allowFuzzyMatch: false))

        (keywords ?? []).forEach { keyword in
            fields.append(SearchableField(content: keyword, weight: 5.0, allowFuzzyMatch: true))
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
