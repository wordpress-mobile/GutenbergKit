import Foundation
import OSLog
import Testing
@testable import GutenbergKit

@MainActor
struct EditorLocalizationTests {

    /// Restores the global localization state around each test.
    private func withLocalization(_ body: () throws -> Void) rethrows {
        let previousLocalize = EditorLocalization.localize

        defer {
            EditorLocalization.localize = previousLocalize
            EditorLocalization.resetFallbackReportingForTesting()
        }

        try body()
    }

    @Test
    func defaultLocalizeProvidesEveryString() {
        #expect(EditorLocalization.defaultLocalize(.showMore) == "Show More")
        #expect(EditorLocalization.defaultLocalize(.patterns) == "Patterns")
        #expect(EditorLocalization.defaultLocalize(.patternsCount(1)) == "1 pattern")
        #expect(EditorLocalization.defaultLocalize(.patternsCount(3)) == "3 patterns")
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

    // Without a host override every string comes from the default table by
    // design, so reporting each one would be noise.
    @Test
    func fallbackIsNotReportedWithoutAHostOverride() {
        withLocalization {
            #expect(EditorLocalization.shouldReportFallback == false)
        }
    }

    @Test
    func fallbackIsReportedOnceAHostTranslates() {
        withLocalization {
            EditorLocalization.localize = { key in
                switch key {
                case .showMore: "Mostrar más"
                default: EditorLocalization.defaultLocalize(key)
                }
            }

            #expect(EditorLocalization.shouldReportFallback)
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

        try withLocalization {
            EditorLocalization.localize = { key in
                switch key {
                case .showMore: "Mostrar más"
                default: EditorLocalization.defaultLocalize(key)
                }
            }

            let started = Date()
            _ = EditorLocalization[.patternsCount(3)]

            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let entries = try store.getEntries(
                at: store.position(date: started),
                matching: NSPredicate(format: "subsystem == %@", "GutenbergKit")
            )

            let messages = entries.compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
            #expect(messages.contains { $0.contains("Missing host translation") })
        }
    }
}
