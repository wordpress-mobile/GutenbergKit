import Testing
import GutenbergKit

struct LogLevelTests {

    @Test func `test error level comparisons`() async throws {
        #expect(LogLevel.error == LogLevel.error)
        #expect(LogLevel.error > LogLevel.warn)
        #expect(LogLevel.error > LogLevel.info)
        #expect(LogLevel.error > LogLevel.debug)
    }

    @Test func `test warn comparisons`() async throws {
        #expect(LogLevel.warn == LogLevel.warn)
        #expect(LogLevel.warn > LogLevel.info)
        #expect(LogLevel.warn > LogLevel.debug)
    }

    @Test func `test info comparisons`() async throws {
        #expect(LogLevel.info == LogLevel.info)
        #expect(LogLevel.info > LogLevel.debug)
    }

    @Test func `test debug comparison`() async throws {
        #expect(LogLevel.debug == LogLevel.debug)
    }
}
