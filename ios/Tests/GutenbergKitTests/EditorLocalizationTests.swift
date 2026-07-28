import Foundation
import OSLog
import Testing
@testable import GutenbergKit

/// `EditorLocalization.localize` and its reporting state are process-global, so
/// these tests cannot safely interleave.
@MainActor
@Suite(.serialized)
struct EditorLocalizationTests {

    /// Restores the global localization state around each test.
    ///
    /// Reporting is off unless a test asks for it, so that tests incidentally
    /// hitting the default table do not write entries the reporting tests would
    /// then read back — `OSLogStore.position(date:)` resolves too coarsely to
    /// keep those windows apart.
    private func withLocalization(
        reportsMissingTranslations: Bool = false,
        _ body: () throws -> Void
    ) rethrows {
        let previousLocalize = EditorLocalization.localize

        defer {
            EditorLocalization.localize = previousLocalize
            EditorLocalization.resetMissingTranslationReportingForTesting()
        }

        EditorLocalization.reportsMissingTranslations = reportsMissingTranslations

        try body()
    }

    /// The only default that is computed rather than a literal. The rest are
    /// covered by the exhaustive switch in `defaultLocalize`, which fails to
    /// compile if a case has no string.
    @Test
    func defaultLocalizePluralizesPatternCounts() {
        withLocalization {
            #expect(EditorLocalization.defaultLocalize(.patternsCount(1)) == "1 pattern")
            #expect(EditorLocalization.defaultLocalize(.patternsCount(3)) == "3 patterns")
        }
    }

    @Test
    func subscriptUsesTheDefaultsWithoutAHostOverride() {
        withLocalization {
            #expect(EditorLocalization[.showMore] == "Show More")
        }
    }

    @Test
    func hostTranslationsTakePrecedence() {
        withLocalization {
            EditorLocalization.localize = { key in
                switch key {
                case .showMore: "Mostrar más"
                default: EditorLocalization.defaultLocalize(key)
                }
            }

            #expect(EditorLocalization[.showMore] == "Mostrar más")
        }
    }

    @Test
    func unhandledKeysFallBackToTheDefaults() {
        withLocalization {
            EditorLocalization.localize = { key in
                switch key {
                case .showMore: "Mostrar más"
                default: EditorLocalization.defaultLocalize(key)
                }
            }

            #expect(EditorLocalization[.search] == "Search")
        }
    }

    /// Call sites live in SwiftUI `body` methods that re-run on every render
    /// pass, so repeat lookups of one key must not each write a log entry.
    @Test
    func repeatedFallbacksForOneKeyAreReportedOnce() throws {
        try withLocalization(reportsMissingTranslations: true) {
            let started = Date()

            for count in 1...5 {
                _ = EditorLocalization.defaultLocalize(.patternsCount(count))
            }

            // One report despite five lookups, and despite the differing
            // associated values, which must not split one key into many.
            let reports = try missingTranslationReports(
                forKeyNamed: "patternsCount",
                since: started
            )
            #expect(reports.count == 1)
        }
    }

    @Test
    func reportingCanBeDisabled() throws {
        // Enabled by the helper, then turned off here, so the assertion below
        // rests on this property rather than on the helper's default.
        try withLocalization(reportsMissingTranslations: true) {
            EditorLocalization.reportsMissingTranslations = false

            let started = Date()
            _ = EditorLocalization.defaultLocalize(.lockdownModeDismiss)

            let reports = try missingTranslationReports(
                forKeyNamed: "lockdownModeDismiss",
                since: started
            )
            #expect(reports.isEmpty)
        }
    }

    /// Host apps are not required to configure `EditorLogger`, so the report
    /// has to reach the log store on its own. `debug` messages are held in an
    /// in-memory buffer and would not.
    @Test
    func fallbackReachesTheLogStoreWithoutAHostLogger() throws {
        let previousShared = EditorLogger.shared
        let previousLevel = EditorLogger.logLevel

        // Explicitly leave `EditorLogger` unconfigured.
        EditorLogger.shared = nil
        EditorLogger.logLevel = .error

        defer {
            EditorLogger.shared = previousShared
            EditorLogger.logLevel = previousLevel
        }

        try withLocalization(reportsMissingTranslations: true) {
            EditorLocalization.localize = { key in
                switch key {
                case .showMore: "Mostrar más"
                default: EditorLocalization.defaultLocalize(key)
                }
            }

            let started = Date()
            _ = EditorLocalization[.lockdownModeLearnMore]

            let reports = try missingTranslationReports(
                forKeyNamed: "lockdownModeLearnMore",
                since: started
            )
            #expect(!reports.isEmpty)
        }
    }

    /// Reads the reports for one key back out of the system log store, which is
    /// where a host would find them without any configuration on their side.
    ///
    /// Scoped to a single key rather than a time window because
    /// `OSLogStore.position(date:)` resolves coarsely enough that entries from
    /// earlier tests fall inside the range.
    private func missingTranslationReports(
        forKeyNamed name: String,
        since start: Date
    ) throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(
            at: store.position(date: start),
            matching: NSPredicate(format: "subsystem == %@", "GutenbergKit")
        )

        return entries
            .compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
            .filter { $0.contains("Missing host translation for \(name),") }
    }
}
