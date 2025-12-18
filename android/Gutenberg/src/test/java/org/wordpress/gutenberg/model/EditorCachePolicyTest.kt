package org.wordpress.gutenberg.model

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Date

class EditorCachePolicyTest {

    // Test Fixtures
    private val referenceDate = Date(0) // Unix epoch

    // MARK: - ignore Policy Tests

    @Test
    fun `ignore policy always returns false`() {
        val policy = EditorCachePolicy.Ignore

        // Even a response cached just now should not be allowed
        assertFalse(policy.allowsResponseWith(date = referenceDate, currentDate = referenceDate))
    }

    // MARK: - always Policy Tests

    @Test
    fun `always policy always returns true`() {
        val policy = EditorCachePolicy.Always

        // Even an extremely old response should be allowed
        assertTrue(policy.allowsResponseWith(date = referenceDate, currentDate = referenceDate))
    }

    // MARK: - maxAge Policy Tests

    @Test
    fun `maxAge policy returns true for response cached just now`() {
        val policy = EditorCachePolicy.MaxAge(60_000) // 60 seconds

        assertTrue(policy.allowsResponseWith(date = referenceDate, currentDate = referenceDate))
    }

    @Test
    fun `maxAge policy returns true for fresh response within interval`() {
        val policy = EditorCachePolicy.MaxAge(60_000) // 60 seconds
        val thirtySecondsAgo = Date(referenceDate.time - 30_000)

        assertTrue(policy.allowsResponseWith(date = thirtySecondsAgo, currentDate = referenceDate))
    }

    @Test
    fun `maxAge policy returns false for expired response`() {
        val policy = EditorCachePolicy.MaxAge(60_000) // 60 seconds
        val twoMinutesAgo = Date(referenceDate.time - 120_000)

        assertFalse(policy.allowsResponseWith(date = twoMinutesAgo, currentDate = referenceDate))
    }

    @Test
    fun `maxAge policy returns false for response just past expiry`() {
        val policy = EditorCachePolicy.MaxAge(60_000) // 60 seconds
        val sixtyOneSecondsAgo = Date(referenceDate.time - 61_000)

        assertFalse(policy.allowsResponseWith(date = sixtyOneSecondsAgo, currentDate = referenceDate))
    }

    @Test
    fun `maxAge policy returns true for future-dated response`() {
        val policy = EditorCachePolicy.MaxAge(60_000) // 60 seconds
        val tenMinutesFromNow = Date(referenceDate.time + 600_000)

        // A future-dated response is definitely not expired
        assertTrue(policy.allowsResponseWith(date = tenMinutesFromNow, currentDate = referenceDate))
    }

    // MARK: - maxAge Policy with Different Intervals

    @Test
    fun `maxAge policy works with zero interval`() {
        val policy = EditorCachePolicy.MaxAge(0)

        // With zero interval, only future-dated responses are valid
        assertFalse(policy.allowsResponseWith(date = referenceDate, currentDate = referenceDate))
        assertFalse(
            policy.allowsResponseWith(
                date = Date(referenceDate.time - 1),
                currentDate = referenceDate
            )
        )
    }

    @Test
    fun `maxAge policy works with one hour interval`() {
        val policy = EditorCachePolicy.MaxAge(3_600_000) // 1 hour

        val thirtyMinutesAgo = Date(referenceDate.time - 1_800_000)
        val twoHoursAgo = Date(referenceDate.time - 7_200_000)

        assertTrue(policy.allowsResponseWith(date = thirtyMinutesAgo, currentDate = referenceDate))
        assertFalse(policy.allowsResponseWith(date = twoHoursAgo, currentDate = referenceDate))
    }

    @Test
    fun `maxAge policy works with one day interval`() {
        val policy = EditorCachePolicy.MaxAge(86_400_000) // 24 hours

        val twelveHoursAgo = Date(referenceDate.time - 43_200_000)
        val twoDaysAgo = Date(referenceDate.time - 172_800_000)

        assertTrue(policy.allowsResponseWith(date = twelveHoursAgo, currentDate = referenceDate))
        assertFalse(policy.allowsResponseWith(date = twoDaysAgo, currentDate = referenceDate))
    }

    @Test
    fun `maxAge policy works with very large interval`() {
        val oneYearMillis = 365L * 24 * 60 * 60 * 1000
        val policy = EditorCachePolicy.MaxAge(oneYearMillis)

        val sixMonthsAgo = Date(referenceDate.time - (182L * 24 * 60 * 60 * 1000))
        val twoYearsAgo = Date(referenceDate.time - (730L * 24 * 60 * 60 * 1000))

        assertTrue(policy.allowsResponseWith(date = sixMonthsAgo, currentDate = referenceDate))
        assertFalse(policy.allowsResponseWith(date = twoYearsAgo, currentDate = referenceDate))
    }
}
