import Foundation
import OSLog
import Testing
@testable import GutenbergKit

/// `EditorLocalization.localize` and its reporting state are process-global, so
/// these tests cannot safely interleave. None of them holds that state across a
/// suspension, where another suite's main-actor test could run against it: each
/// restores it before reading the log store back.
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
    /// covered by the exhaustive switch in `defaultString(for:)`, which fails to
    /// compile if a case has no string.
    @Test
    func defaultsPluralizePatternCounts() {
        withLocalization {
            #expect(EditorLocalization[.patternsCount(1)] == "1 pattern")
            #expect(EditorLocalization[.patternsCount(3)] == "3 patterns")
        }
    }

    @Test
    func subscriptUsesTheDefaultsWithoutAHostOverride() {
        withLocalization {
            #expect(EditorLocalization[.showMore] == "Show More")
        }
    }

    /// The editor reads some strings while building views, which can run before
    /// the host assigns `localize`. Reporting those would name keys the host
    /// does translate, and reports that cry wolf get ignored.
    @Test
    func readsBeforeAHostOverrideAreNotReported() async throws {
        let started = Date()

        withLocalization(reportsMissingTranslations: true) {
            // No host override installed: this is the editor reading its own
            // default, not a gap in anyone's translations.
            _ = EditorLocalization[.loadingEditor]
        }

        let reports = try await missingTranslationReports(
            forKeyNamed: "loadingEditor",
            since: started
        )
        #expect(reports.isEmpty)
    }

    @Test
    func hostTranslationsTakePrecedence() {
        withLocalization {
            EditorLocalization.localize = { key in
                switch key {
                case .showMore: "Mostrar más"
                default: nil
                }
            }

            #expect(EditorLocalization[.showMore] == "Mostrar más")
        }
    }

    @Test
    func declinedKeysFallBackToTheDefaults() {
        withLocalization {
            EditorLocalization.localize = { key in
                switch key {
                case .showMore: "Mostrar más"
                default: nil
                }
            }

            #expect(EditorLocalization[.search] == "Search")
        }
    }

    /// Call sites live in SwiftUI `body` methods that re-run on every render
    /// pass, so repeat lookups of one key must not each write a log entry.
    @Test
    func repeatedFallbacksForOneKeyAreReportedOnce() async throws {
        let started = Date()

        withLocalization(reportsMissingTranslations: true) {
            EditorLocalization.localize = { _ in nil }

            for count in 1...5 {
                _ = EditorLocalization[.patternsCount(count)]
            }
        }

        // One report despite five lookups, and despite the differing
        // associated values, which must not split one key into many.
        let reports = try await missingTranslationReports(
            forKeyNamed: "patternsCount",
            since: started
        )
        #expect(reports.count == 1)
    }

    @Test
    func reportingCanBeDisabled() async throws {
        let started = Date()

        // Enabled by the helper, then turned off here, so the assertion below
        // rests on this property rather than on the helper's default.
        withLocalization(reportsMissingTranslations: true) {
            EditorLocalization.localize = { _ in nil }
            EditorLocalization.reportsMissingTranslations = false

            _ = EditorLocalization[.lockdownModeDismiss]
        }

        let reports = try await missingTranslationReports(
            forKeyNamed: "lockdownModeDismiss",
            since: started
        )
        #expect(reports.isEmpty)
    }

    /// Host apps are not required to configure `EditorLogger`, so the report
    /// has to reach the log store on its own. `debug` messages are held in an
    /// in-memory buffer and would not.
    @Test
    func fallbackReachesTheLogStoreWithoutAHostLogger() async throws {
        let started = Date()

        do {
            let previousShared = EditorLogger.shared
            let previousLevel = EditorLogger.logLevel

            // Explicitly leave `EditorLogger` unconfigured.
            EditorLogger.shared = nil
            EditorLogger.logLevel = .error

            defer {
                EditorLogger.shared = previousShared
                EditorLogger.logLevel = previousLevel
            }

            withLocalization(reportsMissingTranslations: true) {
                EditorLocalization.localize = { key in
                    switch key {
                    case .showMore: "Mostrar más"
                    default: nil
                    }
                }

                _ = EditorLocalization[.lockdownModeLearnMore]
            }
        }

        let reports = try await missingTranslationReports(
            forKeyNamed: "lockdownModeLearnMore",
            since: started
        )
        #expect(!reports.isEmpty)
    }

    /// Reads the reports for one key back out of the system log store, which is
    /// where a host would find them without any configuration on their side.
    ///
    /// Scoped to a single key rather than a time window because
    /// `OSLogStore.position(date:)` resolves coarsely enough that entries from
    /// earlier tests fall inside the range.
    ///
    /// The read is a synchronous round trip to the log daemon, which answers
    /// when it's ready: on a loaded machine that has taken minutes. So it runs
    /// on a thread of its own rather than the main actor's, where every other
    /// main-actor test in the run would wait behind it, and gives up after
    /// `timeout`.
    private nonisolated func missingTranslationReports(
        forKeyNamed name: String,
        since start: Date,
        timeout: TimeInterval = 30
    ) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let answer = FirstAnswer(continuation)

            DispatchQueue.global(qos: .userInitiated).async {
                answer.resume(with: Result { try Self.readMissingTranslationReports(forKeyNamed: name, since: start) })
            }

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                answer.resume(with: .failure(LogStoreTimedOut(seconds: timeout)))
            }
        }
    }

    private nonisolated static func readMissingTranslationReports(
        forKeyNamed name: String,
        since start: Date
    ) throws -> [String] {
        dispatchPrecondition(condition: .notOnQueue(.main))

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

/// The log daemon didn't answer a read of the log store in time.
private struct LogStoreTimedOut: Error, CustomStringConvertible {
    let seconds: TimeInterval

    var description: String {
        "The log store didn't answer within \(Int(seconds)) seconds"
    }
}

/// Resumes a continuation with the first answer it's given, and drops any later one.
private final class FirstAnswer<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, any Error>?

    init(_ continuation: CheckedContinuation<Value, any Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<Value, any Error>) {
        let continuation = lock.withLock {
            defer { self.continuation = nil }
            return self.continuation
        }

        continuation?.resume(with: result)
    }
}
