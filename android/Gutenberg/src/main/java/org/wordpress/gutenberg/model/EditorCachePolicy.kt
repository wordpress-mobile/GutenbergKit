package org.wordpress.gutenberg.model

import java.util.Date

/**
 * A policy that determines how cached responses should be validated and used.
 *
 * `EditorCachePolicy` provides three caching strategies that control when cached
 * HTTP responses are considered valid. This is used by `EditorURLCache` to decide
 * whether to return a cached response or require a fresh network request.
 *
 * ## Choosing a Policy
 *
 * - Use [Ignore] during development or when debugging to ensure fresh data.
 * - Use [MaxAge] for production scenarios where data freshness matters.
 * - Use [Always] for offline-first scenarios or when network availability is limited.
 */
sealed class EditorCachePolicy {

    /**
     * Ignores the cache and always requires fresh data from the network.
     *
     * When this policy is active, all cached responses are considered invalid,
     * forcing new network requests for every operation.
     *
     * Use this policy when:
     * - Debugging caching issues
     * - Testing network behavior
     * - Data must always be fresh
     */
    data object Ignore : EditorCachePolicy()

    /**
     * Uses cached responses only if they are younger than the specified age.
     *
     * @property intervalMillis The maximum age in milliseconds for valid cached responses.
     *
     * Example usage:
     * ```kotlin
     * // Cache responses for up to 5 minutes
     * val policy = EditorCachePolicy.MaxAge(300_000)
     *
     * // Cache responses for up to 1 hour
     * val policy = EditorCachePolicy.MaxAge(3_600_000)
     *
     * // Cache responses for up to 1 day
     * val policy = EditorCachePolicy.MaxAge(86_400_000)
     * ```
     */
    data class MaxAge(val intervalMillis: Long) : EditorCachePolicy()

    /**
     * Always uses cached responses regardless of their age.
     *
     * When this policy is active, any cached response is considered valid,
     * no matter how old it is. This provides maximum cache utilization
     * at the expense of data freshness.
     *
     * Use this policy when:
     * - Operating in offline-first mode
     * - Network connectivity is unreliable
     * - Data freshness is less important than availability
     */
    data object Always : EditorCachePolicy()

    /**
     * Determines whether a cached response with the given storage date should be used.
     *
     * This method evaluates the cache policy against the provided dates to decide
     * if a cached response is still valid.
     *
     * @param date The date when the response was originally cached.
     * @param currentDate The current date to compare against. Defaults to now.
     *
     * @return `true` if the cached response should be used according to this policy,
     *         `false` if a fresh response should be fetched instead.
     *
     * ## Behavior by Policy
     *
     * - [Ignore]: Always returns `false` - cached responses are never used.
     * - [MaxAge]: Returns `true` only if `date + interval > currentDate`
     *   (i.e., the cached response hasn't expired yet).
     * - [Always]: Always returns `true` - cached responses are always used.
     */
    fun allowsResponseWith(date: Date, currentDate: Date = Date()): Boolean {
        return when (this) {
            is Ignore -> false
            is MaxAge -> Date(date.time + intervalMillis).after(currentDate)
            is Always -> true
        }
    }
}
