import Foundation
import OSLog

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
    ///
    /// Host apps are encouraged to delegate unhandled keys to
    /// ``defaultLocalize`` rather than switching exhaustively:
    ///
    /// ```swift
    /// EditorLocalization.localize = { key in
    ///     switch key {
    ///     case .showMore: NSLocalizedString("editor.blockInserter.showMore", ...)
    ///     // ...keys the host translates.
    ///     default: EditorLocalization.defaultLocalize(key)
    ///     }
    /// }
    /// ```
    ///
    /// An exhaustive switch stops compiling whenever the editor adds a string,
    /// which blocks the host from adopting unrelated changes until someone
    /// writes a translation. Delegating instead renders the untranslated
    /// default for new strings and logs at the `debug` level, so a missing
    /// translation degrades the string rather than the build.
    public static var localize: (EditorLocalizableString) -> String = { key in
        defaultLocalize(key)
    } {
        didSet { setShouldReportFallback(true) }
    }

    /// Whether falling back to a default string is worth reporting.
    ///
    /// True once a host app installs its own ``localize`` and thereby takes
    /// responsibility for translations. Without an override every string comes
    /// from the default table by design, and reporting each one would be noise.
    ///
    /// ``defaultLocalize`` reads this, and host apps call that from whatever
    /// context their own localization runs in, so it cannot be isolated to the
    /// main actor. Guarded by a lock rather than declared `nonisolated(unsafe)`
    /// so the access is actually free of races instead of merely asserted to be.
    nonisolated static var shouldReportFallback: Bool {
        fallbackReportingLock.withLock { _shouldReportFallback }
    }

    private nonisolated static let fallbackReportingLock = NSLock()
    nonisolated(unsafe) private static var _shouldReportFallback = false

    private nonisolated static func setShouldReportFallback(_ newValue: Bool) {
        fallbackReportingLock.withLock { _shouldReportFallback = newValue }
    }

    /// The editor's untranslated strings.
    ///
    /// Exposed so host apps can fall back to it for keys they do not translate.
    /// See ``localize``.
    ///
    /// Deliberately `nonisolated`: host apps delegate to this from their own
    /// localization functions, which are ordinarily not main-actor isolated.
    /// Isolating it would force that annotation onto every host.
    public nonisolated static func defaultLocalize(
        _ key: EditorLocalizableString
    ) -> String {
        if shouldReportFallback {
            // Logged through `OSLog` rather than `EditorLogger`, which reaches
            // only hosts that install a logger and raise the log level. This
            // message is for whoever integrates the library, and the hosts most
            // likely to miss a translation are the ones least likely to have
            // configured logging.
            //
            // Logged at `notice` rather than `debug` so it persists to the log
            // store. `debug` is held in an in-memory buffer that requires
            // enabling debug logging for the subsystem to read, which defeats
            // the point of reporting something the host is unaware of.
            Logger.localization.notice(
                "Missing host translation for \(String(describing: key), privacy: .public), using the editor default."
            )
        }

        return switch key {
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

    /// Clears the record of a host override so tests can restore the initial
    /// state after assigning ``localize``.
    static func resetFallbackReportingForTesting() {
        setShouldReportFallback(false)
    }
}
