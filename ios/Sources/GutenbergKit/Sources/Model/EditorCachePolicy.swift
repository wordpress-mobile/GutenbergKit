import Foundation

/// A policy that determines how cached responses should be validated and used.
///
/// `EditorCachePolicy` provides three caching strategies that control when cached
/// HTTP responses are considered valid. This is used by `EditorURLCache` to decide
/// whether to return a cached response or require a fresh network request.
///
/// ## Usage
///
/// ```swift
/// // Never use cached responses
/// let cache = EditorURLCache(cachePolicy: .ignore)
///
/// // Use cached responses if they're less than 1 hour old
/// let cache = EditorURLCache(cachePolicy: .maxAge(3600))
///
/// // Always use cached responses regardless of age
/// let cache = EditorURLCache(cachePolicy: .always)
/// ```
///
/// ## Choosing a Policy
///
/// - Use ``ignore`` during development or when debugging to ensure fresh data.
/// - Use ``maxAge(_:)`` for production scenarios where data freshness matters.
/// - Use ``always`` for offline-first scenarios or when network availability is limited.
///
public enum EditorCachePolicy: Sendable {

    /// Ignores the cache and always requires fresh data from the network.
    ///
    /// When this policy is active, all cached responses are considered invalid,
    /// forcing new network requests for every operation.
    ///
    /// Use this policy when:
    /// - Debugging caching issues
    /// - Testing network behavior
    /// - Data must always be fresh
    ///
    case ignore

    /// Uses cached responses only if they are younger than the specified age.
    ///
    /// The associated `TimeInterval` value represents the maximum age in seconds
    /// that a cached response is considered valid. Responses older than this
    /// threshold are treated as stale and will not be used.
    ///
    /// - Parameter interval: The maximum age in seconds for valid cached responses.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Cache responses for up to 5 minutes
    /// let policy = EditorCachePolicy.maxAge(300)
    ///
    /// // Cache responses for up to 1 hour
    /// let policy = EditorCachePolicy.maxAge(3600)
    ///
    /// // Cache responses for up to 1 day
    /// let policy = EditorCachePolicy.maxAge(86400)
    /// ```
    ///
    case maxAge(TimeInterval)

    /// Always uses cached responses regardless of their age.
    ///
    /// When this policy is active, any cached response is considered valid,
    /// no matter how old it is. This provides maximum cache utilization
    /// at the expense of data freshness.
    ///
    /// Use this policy when:
    /// - Operating in offline-first mode
    /// - Network connectivity is unreliable
    /// - Data freshness is less important than availability
    ///
    case always

    /// Determines whether a cached response with the given storage date should be used.
    ///
    /// This method evaluates the cache policy against the provided dates to decide
    /// if a cached response is still valid.
    ///
    /// - Parameters:
    ///   - date: The date when the response was originally cached.
    ///   - currentDate: The current date to compare against. Defaults to `Date.now`.
    ///
    /// - Returns: `true` if the cached response should be used according to this policy,
    ///            `false` if a fresh response should be fetched instead.
    ///
    /// ## Behavior by Policy
    ///
    /// - ``ignore``: Always returns `false` - cached responses are never used.
    /// - ``maxAge(_:)``: Returns `true` only if `date + interval > currentDate`
    ///   (i.e., the cached response hasn't expired yet).
    /// - ``always``: Always returns `true` - cached responses are always used.
    ///
    internal func allowsResponseWith(date: Date, currentDate: Date = .now) -> Bool {
        switch self {
        case .ignore: false
        case .maxAge(let interval): date.addingTimeInterval(interval) > currentDate
        case .always: true
        }
    }
}
