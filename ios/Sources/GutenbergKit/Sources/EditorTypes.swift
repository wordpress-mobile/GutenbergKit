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
    func searchableFields() -> [SearchableField] {
        var fields: [SearchableField] = []

        // Title - highest weight
        if let title = title {
            fields.append(SearchableField(content: title, weight: 10.0, allowFuzzyMatch: true))
        }

        // Name - high weight, strip namespace for better matching
        let simplifiedName = name.components(separatedBy: "/").last ?? name
        fields.append(SearchableField(content: simplifiedName, weight: 8.0, allowFuzzyMatch: true))

        // Keywords - medium weight
        if let keywords = keywords {
            keywords.forEach { keyword in
                fields.append(SearchableField( content: keyword, weight: 5.0, allowFuzzyMatch: true))
            }
        }

        // Description - lower weight, no fuzzy matching
        if let description = description {
            fields.append(SearchableField(content: description, weight: 3.0, allowFuzzyMatch: false))
        }

        // Category - lowest weight
        if let category = category {
            fields.append(SearchableField(content: category, weight: 2.0, allowFuzzyMatch: true))
        }

        return fields
    }
}
