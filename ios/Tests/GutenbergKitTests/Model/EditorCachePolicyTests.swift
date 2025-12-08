import Foundation
import Testing

@testable import GutenbergKit

@Suite
struct EditorCachePolicyTests {

    // MARK: - Test Fixtures

    /// A fixed reference date for deterministic testing.
    static let referenceDate = Date(timeIntervalSinceReferenceDate: 0)

    // MARK: - ignore Policy Tests

    @Test("ignore policy always returns false")
    func ignorePolicyAlwaysReturnsFalse() {
        let policy = EditorCachePolicy.ignore

        // Even a response cached just now should not be allowed
        #expect(policy.allowsResponseWith(date: Self.referenceDate, currentDate: Self.referenceDate) == false)
    }

    // MARK: - always Policy Tests
    @Test("always policy always returns true")
    func alwaysPolicyAlwaysReturnsTrue() {
        let policy = EditorCachePolicy.always

        // Even an extremely old response should be allowed
        #expect(policy.allowsResponseWith(date: Self.referenceDate, currentDate: Self.referenceDate) == true)
    }

    // MARK: - maxAge Policy Tests
    @Test("maxAge policy returns true for response cached just now")
    func maxAgePolicyReturnsTrueForJustCached() {
        let policy = EditorCachePolicy.maxAge(60)  // 60 seconds

        #expect(policy.allowsResponseWith(date: Self.referenceDate, currentDate: Self.referenceDate) == true)
    }

    @Test("maxAge policy returns true for fresh response within interval")
    func maxAgePolicyReturnsTrueForFreshResponse() {
        let policy = EditorCachePolicy.maxAge(60)  // 60 seconds
        let thirtySecondsAgo = Self.referenceDate.addingTimeInterval(-30)

        #expect(policy.allowsResponseWith(date: thirtySecondsAgo, currentDate: Self.referenceDate) == true)
    }

    @Test("maxAge policy returns false for expired response")
    func maxAgePolicyReturnsFalseForExpiredResponse() {
        let policy = EditorCachePolicy.maxAge(60)  // 60 seconds
        let twoMinutesAgo = Self.referenceDate.addingTimeInterval(-120)

        #expect(policy.allowsResponseWith(date: twoMinutesAgo, currentDate: Self.referenceDate) == false)
    }

    @Test("maxAge policy returns false for response just past expiry")
    func maxAgePolicyReturnsFalseForJustPastExpiry() {
        let policy = EditorCachePolicy.maxAge(60)  // 60 seconds
        let sixtyOneSecondsAgo = Self.referenceDate.addingTimeInterval(-61)

        #expect(policy.allowsResponseWith(date: sixtyOneSecondsAgo, currentDate: Self.referenceDate) == false)
    }

    @Test("maxAge policy returns true for future-dated response")
    func maxAgePolicyReturnsTrueForFutureResponse() {
        let policy = EditorCachePolicy.maxAge(60)  // 60 seconds
        let tenMinutesFromNow = Self.referenceDate.addingTimeInterval(600)

        // A future-dated response is definitely not expired
        #expect(policy.allowsResponseWith(date: tenMinutesFromNow, currentDate: Self.referenceDate) == true)
    }

    // MARK: - maxAge Policy with Different Intervals

    @Test("maxAge policy works with zero interval")
    func maxAgePolicyWorksWithZeroInterval() {
        let policy = EditorCachePolicy.maxAge(0)

        // With zero interval, only future-dated responses are valid
        #expect(policy.allowsResponseWith(date: Self.referenceDate, currentDate: Self.referenceDate) == false)
        #expect(
            policy.allowsResponseWith(
                date: Self.referenceDate.addingTimeInterval(-1), currentDate: Self.referenceDate) == false)
    }

    @Test("maxAge policy works with one hour interval")
    func maxAgePolicyWorksWithOneHourInterval() {
        let policy = EditorCachePolicy.maxAge(3600)  // 1 hour

        let thirtyMinutesAgo = Self.referenceDate.addingTimeInterval(-1800)
        let twoHoursAgo = Self.referenceDate.addingTimeInterval(-7200)

        #expect(policy.allowsResponseWith(date: thirtyMinutesAgo, currentDate: Self.referenceDate) == true)
        #expect(policy.allowsResponseWith(date: twoHoursAgo, currentDate: Self.referenceDate) == false)
    }

    @Test("maxAge policy works with one day interval")
    func maxAgePolicyWorksWithOneDayInterval() {
        let policy = EditorCachePolicy.maxAge(86400)  // 24 hours

        let twelveHoursAgo = Self.referenceDate.addingTimeInterval(-43200)
        let twoDaysAgo = Self.referenceDate.addingTimeInterval(-172800)

        #expect(policy.allowsResponseWith(date: twelveHoursAgo, currentDate: Self.referenceDate) == true)
        #expect(policy.allowsResponseWith(date: twoDaysAgo, currentDate: Self.referenceDate) == false)
    }

    @Test("maxAge policy works with very large interval")
    func maxAgePolicyWorksWithVeryLargeInterval() {
        let policy = EditorCachePolicy.maxAge(365 * 24 * 60 * 60)  // 1 year

        let sixMonthsAgo = Self.referenceDate.addingTimeInterval(-182 * 24 * 60 * 60)
        let twoYearsAgo = Self.referenceDate.addingTimeInterval(-730 * 24 * 60 * 60)

        #expect(policy.allowsResponseWith(date: sixMonthsAgo, currentDate: Self.referenceDate) == true)
        #expect(policy.allowsResponseWith(date: twoYearsAgo, currentDate: Self.referenceDate) == false)
    }
}
