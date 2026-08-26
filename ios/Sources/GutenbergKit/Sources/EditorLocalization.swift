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
    case failedToLoadSelectedMedia
    case failedToProcessCapturedMedia

    // MARK: - Common
    case ok

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
public final class EditorLocalization {
    /// This is designed to be overridden by the host app to provide translations.
    ///
    /// Return `nil` for keys the host does not translate; the editor renders its
    /// own string for those and reports the gap. See
    /// ``reportsMissingTranslations``.
    ///
    /// ```swift
    /// EditorLocalization.localize = { key in
    ///     switch key {
    ///     case .showMore: NSLocalizedString("editor.blockInserter.showMore", ...)
    ///     // ...keys the host translates.
    ///     @unknown default: nil
    ///     }
    /// }
    /// ```
    ///
    /// Declining rather than switching exhaustively keeps the host compiling
    /// when the editor adds a string: the new key renders untranslated instead
    /// of breaking the build. `@unknown default` rather than a plain `default`
    /// so a host that covers every case today still compiles without a
    /// "default will never be executed" warning.
    ///
    /// Main-actor isolated because it holds a non-`Sendable` closure. Hosts
    /// assign it during editor setup, which already runs on the main actor.
    @MainActor
    public static var localize: (EditorLocalizableString) -> String? = { key in
        defaultString(for: key)
    }

    /// Whether falling back to a default string is reported to the system log.
    ///
    /// Enabled by default so a host that misses a translation finds out without
    /// having to opt in. Set to `false` in apps that render the editor's own
    /// strings deliberately, where every fallback is expected and the reports
    /// are noise.
    ///
    /// Set this once during app setup, before presenting an editor. It is
    /// deliberately unsynchronized, so toggling it while an editor is on screen
    /// may cost a stray report or drop one.
    public nonisolated(unsafe) static var reportsMissingTranslations = true

    /// Keys already reported, so each is logged once. Guarded rather than
    /// `nonisolated(unsafe)` because `Set` is not safe to mutate concurrently.
    private static let reportedKeys = OSAllocatedUnfairLock<Set<String>>(
        initialState: []
    )

    /// The editor's untranslated strings.
    private static func defaultString(
        for key: EditorLocalizableString
    ) -> String {
        switch key {
        case .showMore: "Show More"
        case .showLess: "Show Less"
        case .search: "Search"
        case .insertBlock: "Insert Block"
        case .failedToInsertMedia: "Failed to insert media"
        case .failedToLoadSelectedMedia: "The selected media could not be loaded. It may not be fully downloaded to this device."
        case .failedToProcessCapturedMedia: "The captured media could not be processed."
        case .ok: "OK"
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
    private static func reportMissingTranslation(
        for key: EditorLocalizableString
    ) {
        guard reportsMissingTranslations else { return }

        // Associated values distinguish cases that share a translation:
        // `patternsCount(3)` and `patternsCount(7)` are one missing string.
        let name = String(String(describing: key).prefix { $0 != "(" })

        guard reportedKeys.withLock({ $0.insert(name).inserted }) else { return }

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
    ///
    /// Falls back to the editor's own string when the host declines a key, and
    /// reports the gap.
    @MainActor
    public static subscript(key: EditorLocalizableString) -> String {
        if let translation = localize(key) {
            return translation
        }

        // Only a host returning `nil` reaches here. The default closure answers
        // every key, so reads before a host installs one are not reported.
        reportMissingTranslation(for: key)

        return defaultString(for: key)
    }

    /// Clears the record of which keys have already been reported so tests do
    /// not leak state into each other.
    static func resetMissingTranslationReportingForTesting() {
        reportsMissingTranslations = true
        reportedKeys.withLock { $0.removeAll() }
    }
}
