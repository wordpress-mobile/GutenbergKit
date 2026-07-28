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
    /// default for new strings and reports the gap through ``Logger``, so a
    /// missing translation degrades the string rather than the build. See
    /// ``reportsMissingTranslations``.
    ///
    /// Until a host installs its own closure this renders the defaults without
    /// reporting them. Reporting here would fire for strings the host does
    /// translate, because the editor reads some of them — `loadingEditor` among
    /// them — while building views, which can run before the host assigns this.
    public static var localize: (EditorLocalizableString) -> String = { key in
        defaultString(for: key)
    }

    /// Whether falling back to a default string is reported to the system log.
    ///
    /// Enabled by default so a host that misses a translation finds out without
    /// having to opt in. Set to `false` in apps that render the editor's own
    /// strings deliberately — the demo app, say — where every fallback is
    /// expected and the reports are noise.
    ///
    /// ``defaultLocalize`` reads this, and host apps call that from whatever
    /// context their own localization runs in, so it cannot be isolated to the
    /// main actor. Guarded by the same lock as the reported-key set below.
    public nonisolated static var reportsMissingTranslations: Bool {
        get { reportingLock.withLock { _reportsMissingTranslations } }
        set { reportingLock.withLock { _reportsMissingTranslations = newValue } }
    }

    private nonisolated static let reportingLock = NSLock()
    nonisolated(unsafe) private static var _reportsMissingTranslations = true
    nonisolated(unsafe) private static var reportedKeys: Set<String> = []

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
        // Only the host delegating an unhandled key reaches here, so this is
        // where a gap in the host's translations is genuinely observable. The
        // editor's own reads go through `defaultString(for:)` instead.
        reportMissingTranslation(for: key)

        return defaultString(for: key)
    }

    /// The editor's untranslated strings, without reporting.
    private nonisolated static func defaultString(
        for key: EditorLocalizableString
    ) -> String {
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

    /// Reports a missing translation the first time each key falls back.
    ///
    /// Every call site sits inside a SwiftUI `body`, which re-evaluates on each
    /// render pass, so logging unconditionally would write an entry per row per
    /// frame while a list scrolls. Reporting once per key tells the integrator
    /// the same thing without the volume.
    private nonisolated static func reportMissingTranslation(
        for key: EditorLocalizableString
    ) {
        // Associated values distinguish cases that share a translation:
        // `patternsCount(3)` and `patternsCount(7)` are one missing string.
        let name = String(String(describing: key).prefix { $0 != "(" })

        let shouldReport = reportingLock.withLock {
            _reportsMissingTranslations && reportedKeys.insert(name).inserted
        }
        guard shouldReport else { return }

        // Logged through `OSLog` rather than `EditorLogger`, which reaches only
        // hosts that install a logger and raise the log level. This message is
        // for whoever integrates the library, and the hosts most likely to miss
        // a translation are the ones least likely to have configured logging.
        //
        // Logged at `notice` rather than `debug` so it persists to the log
        // store. `debug` is held in an in-memory buffer that requires enabling
        // debug logging for the subsystem to read, which defeats the point of
        // reporting something the host is unaware of.
        Logger.localization.notice(
            "Missing host translation for \(name, privacy: .public), using the editor default."
        )
    }

    /// Convenience subscript for accessing localized strings.
    public static subscript(key: EditorLocalizableString) -> String {
         localize(key)
    }

    /// Clears the record of which keys have already been reported so tests do
    /// not leak state into each other.
    static func resetMissingTranslationReportingForTesting() {
        reportingLock.withLock {
            _reportsMissingTranslations = true
            reportedKeys.removeAll()
        }
    }
}
