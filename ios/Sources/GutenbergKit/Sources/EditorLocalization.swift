import Foundation

/// Enum representing all localizable strings in the editor.
public enum EditorLocalizableString {
    // MARK: - Block Inserter
    case showMore
    case showLess
    case search
    case insertBlock

    // MARK: - Media
    case failedToInsertMedia

    // MARK: - Patterns
    case patterns
    case noPatternsFound
    case insertPattern
    case patternsCategoryUncategorized
    case patternsCategoryAll
}

/// Provides localized strings for the editor.
///
/// Usage:
/// ```swift
/// let text = EditorLocalization[.showMore]
/// ```
@MainActor
public final class EditorLocalization {
    /// This is designed to be overridden by the host app to provide translations.
    public static var localize: (EditorLocalizableString) -> String = { key in
        switch key {
        case .showMore: "Show More"
        case .showLess: "Show Less"
        case .search: "Search"
        case .insertBlock: "Insert Block"
        case .failedToInsertMedia: "Failed to insert media"
        case .patterns: "Patterns"
        case .noPatternsFound: "No Patterns Found"
        case .insertPattern: "Insert Pattern"
        case .patternsCategoryUncategorized: "Uncategorized"
        case .patternsCategoryAll: "All"
        }
    }

    /// Convenience subscript for accessing localized strings.
    public static subscript(key: EditorLocalizableString) -> String {
         localize(key)
    }
}
