import Foundation
import Testing
@testable import GutenbergKit

/// Captures log messages so the fallback reporting can be inspected.
private final class SpyLogger: EditorLogging, @unchecked Sendable {
    private let lock = NSLock()
    private var _messages: [(EditorLogLevel, String)] = []

    var messages: [(EditorLogLevel, String)] {
        lock.withLock { _messages }
    }

    func log(_ level: EditorLogLevel, _ message: String) {
        lock.withLock { _messages.append((level, message)) }
    }
}

@MainActor
struct EditorLocalizationTests {

    /// Restores the global localization and logging state around each test.
    private func withLocalization(
        _ body: (SpyLogger) throws -> Void
    ) rethrows {
        let previousLocalize = EditorLocalization.localize
        let previousLogger = EditorLogger.shared
        let previousLevel = EditorLogger.logLevel

        let spy = SpyLogger()
        EditorLogger.shared = spy
        EditorLogger.logLevel = .debug

        defer {
            EditorLocalization.localize = previousLocalize
            EditorLogger.shared = previousLogger
            EditorLogger.logLevel = previousLevel
            EditorLocalization.resetHostTranslationsForTesting()
        }

        try body(spy)
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
        withLocalization { _ in
            #expect(EditorLocalization[.showMore] == "Show More")
        }
    }

    @Test
    func hostTranslationsTakePrecedence() {
        withLocalization { _ in
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
        withLocalization { _ in
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
        withLocalization { spy in
            _ = EditorLocalization[.showMore]

            #expect(spy.messages.isEmpty)
        }
    }

    @Test
    func fallbackIsReportedOnceAHostTranslates() {
        withLocalization { spy in
            EditorLocalization.localize = { key in
                switch key {
                case .showMore: "Mostrar más"
                default: EditorLocalization.defaultLocalize(key)
                }
            }

            _ = EditorLocalization[.showMore]
            #expect(spy.messages.isEmpty)

            _ = EditorLocalization[.search]
            #expect(spy.messages.count == 1)
            #expect(spy.messages.first?.0 == .debug)
            #expect(spy.messages.first?.1.contains("search") == true)
        }
    }
}
