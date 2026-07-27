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
    case patternsCount(Int)

    // MARK: - Editor Loading
    case loadingEditor
    case editorError

    // MARK: - Lockdown Mode
    case lockdownModeTitle
    case lockdownModeWarning
    case lockdownModeExcludeHint
    case lockdownModeLearnMore
    case lockdownModeDismiss
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
        case .patternsCount(let count): count == 1 ? "1 pattern" : "\(count) patterns"
        case .loadingEditor: "Loading Editor"
        case .editorError: "Editor Error"
        case .lockdownModeTitle: "Lockdown Mode Detected"
        case .lockdownModeWarning: "Lockdown Mode is enabled. The editor may not work correctly."
        case .lockdownModeExcludeHint: "You can exclude this app from Lockdown Mode in Settings, then re-open the editor to restore full functionality."
        case .lockdownModeLearnMore: "Learn More"
        case .lockdownModeDismiss: "Dismiss"
        }
    }

    /// Convenience subscript for accessing localized strings.
    public static subscript(key: EditorLocalizableString) -> String {
         localize(key)
    }
}
