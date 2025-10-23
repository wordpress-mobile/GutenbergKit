import Foundation

struct EditorBlock: Decodable, Identifiable {
    var id: String { name }

    let name: String
    let title: String?
    let description: String?
    let category: String?
    let keywords: [String]?
    var icon: String?
}

public struct EditorTitleAndContent: Decodable {
    public let title: String
    public let content: String
    public let changed: Bool
}

extension EditorBlock: Searchable {
    /// Sets the searchable fields in the order of priority
    func searchableFields() -> [SearchableField] {
        var fields: [SearchableField] = []

        if let title, !title.isEmpty {
            fields.append(SearchableField(content: title, weight: 10.0, allowFuzzyMatch: true))
        }

        fields.append(SearchableField(content: name, weight: 8.0, allowFuzzyMatch: false))

        (keywords ?? []).forEach { keyword in
            fields.append(SearchableField( content: keyword, weight: 5.0, allowFuzzyMatch: true))
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
