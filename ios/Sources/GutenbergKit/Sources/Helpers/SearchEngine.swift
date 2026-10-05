import Foundation

/// A protocol for items that can be searched
protocol Searchable {
    /// Extract searchable fields with their weights
    func searchableFields() -> [SearchableField]
}

/// A field that can be searched with an associated weight
struct SearchableField {
    let content: String
    let weight: Double
    let allowFuzzyMatch: Bool

    init(content: String, weight: Double, allowFuzzyMatch: Bool = true) {
        self.content = content
        self.weight = weight
        self.allowFuzzyMatch = allowFuzzyMatch
    }
}

/// Configuration for the search engine
struct SearchConfiguration {
    /// Maximum allowed edit distance for fuzzy matching
    let maxEditDistance: Int

    /// Minimum similarity threshold (0-1) for fuzzy matches
    let minSimilarityThreshold: Double

    /// Multiplier for exact matches
    let exactMatchMultiplier: Double

    /// Multiplier for prefix matches
    let prefixMatchMultiplier: Double

    /// Multiplier for word prefix matches
    let wordPrefixMatchMultiplier: Double

    /// Multiplier for fuzzy matches (applied to similarity score)
    let fuzzyMatchMultiplier: Double

    static let `default` = SearchConfiguration(
        maxEditDistance: 2,
        minSimilarityThreshold: 0.7,
        exactMatchMultiplier: 2.0,
        prefixMatchMultiplier: 1.5,
        wordPrefixMatchMultiplier: 0.8,
        fuzzyMatchMultiplier: 0.6
    )
}

/// A generic search engine that performs weighted fuzzy search
struct SearchEngine<Item: Searchable> {

    /// Search result with relevance score
    struct SearchResult {
        let item: Item
        let score: Double
    }

    let configuration: SearchConfiguration

    init(configuration: SearchConfiguration = .default) {
        self.configuration = configuration
    }

    /// Search items with weighted fuzzy matching
    func search(query: String, in items: [Item]) -> [Item] {
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty query returns all items
        guard !normalizedQuery.isEmpty else {
            return items
        }

        // Calculate scores for all items
        let results: [SearchResult] = items.compactMap { item in
            let score = calculateScore(for: item, query: normalizedQuery)
            return score > 0 ? SearchResult(item: item, score: score) : nil
        }

        // Sort by score (highest first) and return items
        return results
            .sorted { $0.score > $1.score }
            .map { $0.item }
    }

    /// Calculate weighted score for an item based on query match
    private func calculateScore(for item: Item, query: String) -> Double {
        let fields = item.searchableFields()

        return fields.reduce(0.0) { totalScore, field in
            // Skip empty fields
            guard !field.content.isEmpty else {
                return totalScore
            }

            return totalScore + calculateFieldScore(
                field: field.content.lowercased(),
                query: query,
                weight: field.weight,
                allowFuzzy: field.allowFuzzyMatch
            )
        }
    }

    /// Calculate score for a single field
    private func calculateFieldScore(field: String, query: String, weight: Double, allowFuzzy: Bool) -> Double {
        // Defensive check: skip empty field or query
        guard !field.isEmpty, !query.isEmpty else {
            return 0
        }

        // Exact match
        if field == query {
            return weight * configuration.exactMatchMultiplier
        }

        // Contains match
        if field.contains(query) {
            // Higher score if it starts with the query
            if field.hasPrefix(query) {
                return weight * configuration.prefixMatchMultiplier
            }
            return weight
        }

        // Fuzzy match if allowed
        if allowFuzzy {
            // Check each word in the field
            let fieldWords = field.split(separator: " ").map(String.init)
            for word in fieldWords {
                // Word starts with query
                if word.hasPrefix(query) {
                    return weight * configuration.wordPrefixMatchMultiplier
                }

                // Calculate similarity
                let similarity = calculateSimilarity(word, query)
                if similarity >= configuration.minSimilarityThreshold {
                    return weight * similarity * configuration.fuzzyMatchMultiplier
                }
            }

            // Try full field fuzzy match for short queries
            if query.count <= 10 {
                let similarity = calculateSimilarity(field, query)
                if similarity >= configuration.minSimilarityThreshold {
                    return weight * similarity * configuration.fuzzyMatchMultiplier * 0.7
                }
            }
        }

        return 0
    }

    /// Calculate similarity between two strings using normalized edit distance
    private func calculateSimilarity(_ str1: String, _ str2: String) -> Double {
        // Defensive check: return 0 for empty strings
        guard !str1.isEmpty, !str2.isEmpty else {
            return 0
        }

        let distance = levenshteinDistance(str1, str2)
        let maxLength = max(str1.count, str2.count)

        // Don't allow too many edits relative to string length
        if distance > min(configuration.maxEditDistance, maxLength / 3) {
            return 0
        }

        return 1.0 - (Double(distance) / Double(maxLength))
    }

    /// Calculate Levenshtein edit distance between two strings
    private func levenshteinDistance(_ str1: String, _ str2: String) -> Int {
        let str1Array = Array(str1)
        let str2Array = Array(str2)

        // Handle empty strings
        guard !str1Array.isEmpty else {
            return str2Array.count
        }
        guard !str2Array.isEmpty else {
            return str1Array.count
        }

        // Create matrix
        var matrix = Array(repeating: Array(repeating: 0, count: str2Array.count + 1), count: str1Array.count + 1)

        // Initialize first row and column
        for i in 0...str1Array.count {
            matrix[i][0] = i
        }
        for j in 0...str2Array.count {
            matrix[0][j] = j
        }

        // Fill matrix
        for i in 1...str1Array.count {
            for j in 1...str2Array.count {
                let cost = str1Array[i - 1] == str2Array[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,     // deletion
                    matrix[i][j - 1] + 1,     // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }

        return matrix[str1Array.count][str2Array.count]
    }
}
