import Foundation

/// The site's REST API root, in either of the two shapes WordPress gives it.
///
/// Pretty permalinks give a directory, `https://example.com/wp-json/`, and a
/// request's route is the path below it. Plain permalinks give a query,
/// `https://example.com/?rest_route=/`, and the route is that parameter's
/// value. ``path(below:)`` reads the route out of a URL in either shape, and
/// ``url(forPath:)`` builds the URL for one.
///
/// ``RestRelay`` sends the site credential only to a URL this builds, and its
/// redirect guard follows a site API request only to a URL this ``contains(_:)``.
/// Both ask the same question here, so they can't disagree about what is
/// inside the root.
struct SiteAPIRoot: Sendable {

    /// The root, slash-terminated, with the route value of a plain-permalink
    /// root decoded.
    ///
    /// Held as a string rather than a `URL` because the root is not always
    /// directory-shaped: resolving a relative URL against
    /// `https://example.com/?rest_route=/` would discard the query.
    let string: String

    /// The root the host app configured, normalized.
    ///
    /// WordPress advertises a plain-permalink root through `add_query_arg`,
    /// which percent-encodes the value: `index.php?rest_route=%2F`. The
    /// separators are decoded before the slash is added, so the slash lands
    /// inside the route value. Appended after `%2F`, it would make a root no
    /// path can extend: WordPress reads `rest_route=%2F/wp/v2/posts` as the
    /// route `//wp/v2/posts` and answers `rest_no_route`.
    ///
    /// A doubled trailing slash collapses to one. api-fetch builds its root
    /// with `ensureTrailingSlash`, which collapses it, so requests arrive below
    /// `…/wp-json/`. Kept doubled, the root would match none of them, and every
    /// one would go out without the site credential.
    init(_ configured: URL) {
        var root = configured.absoluteString
        if let query = root.firstIndex(of: "?") {
            root = String(root[..<query]) + Self.decodingSlashes(root[query...])
        }
        while root.hasSuffix("/") {
            root.removeLast()
        }
        string = root + "/"
    }

    /// Whether `target` is below the root, with a route that stays inside it.
    func contains(_ target: URL) -> Bool {
        path(below: target).flatMap(url(forPath:)) != nil
    }

    /// The part of `url` below the root — its route and query, without a
    /// leading slash — or `nil` when `url` isn't below the root.
    ///
    /// **Host aliases are tolerated; other hosts and path differences are
    /// not.** WordPress builds `Link` headers and `_links` hrefs from
    /// `home_url()`, which need not spell the host the app was configured with
    /// — `www.` versus bare, or wp-env's `localhost` versus the `127.0.0.1` its
    /// runtime writes into `WP_SITEURL`. The scheme may differ too — an `http`
    /// `siteurl` behind a TLS-terminating proxy — since the request is sent to
    /// the configured root whichever it names. The port has to match: another
    /// port on the same host is another server, and answering its request with
    /// the site's response is a different bug from the one this tolerance
    /// exists to fix. A *path* difference is likewise a different resource: in
    /// a subdirectory multisite `https://site/a/wp-json/` and
    /// `https://site/b/wp-json/` are separate sites.
    func path(below url: URL) -> String? {
        guard let target = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let root = URLComponents(string: string),
              let targetHost = target.host, let rootHost = root.host,
              Self.canonicalHost(targetHost) == Self.canonicalHost(rootHost),
              target.explicitPort == root.explicitPort else {
            return nil
        }

        if root.percentEncodedQuery != nil {
            return Self.queryRoutedPath(of: target, below: root)
        }

        let rootPath = root.percentEncodedPathOrSlash
        let targetPath = target.percentEncodedPathOrSlash
        guard targetPath.hasPrefix(rootPath) else { return nil }
        return String(targetPath.dropFirst(rootPath.count)) + (target.percentEncodedQuery.map { "?\($0)" } ?? "")
    }

    /// The URL for `path` — a route and query below the root — or `nil` if the
    /// result would address anything outside the root.
    ///
    /// The path is appended to the root. Appending rather than resolving is
    /// what `createRootURLMiddleware` does on the JavaScript side, and it is the
    /// only approach that works for both shapes: under plain permalinks the
    /// path has to merge into the root's query.
    ///
    /// Dot segments — literal or percent-encoded — are refused rather than
    /// normalized. A REST path never contains one, `URLSession` resolves them
    /// before sending, and a normalized `..` is the one thing that could walk
    /// out of the API root and reach the rest of the site with the credential
    /// attached.
    func url(forPath path: String) -> URL? {
        let separator = path.firstIndex(of: "?")
        // Leading slashes are dropped, so the path appends to the API root
        // rather than resolving against the site root.
        let relativePath = path[..<(separator ?? path.endIndex)].drop(while: { $0 == "/" })
        guard !Self.containsDotSegment(relativePath) else { return nil }

        var suffix = String(relativePath) + (separator.map { String(path[$0...]) } ?? "")
        // A root that already carries a query (plain permalinks) continues it
        // rather than starting a second one — mirroring `createRootURLMiddleware`.
        if string.contains("?"), let separator = suffix.firstIndex(of: "?") {
            suffix.replaceSubrange(separator...separator, with: "&")
        }

        guard let url = URL(string: string + suffix),
              url.absoluteString.hasPrefix(string) else {
            return nil
        }
        return url
    }

    /// A host reduced to the form the site's aliases share: every loopback
    /// spelling collapses to one, and a `www.` prefix is dropped.
    ///
    /// Only for deciding whether a host is the site's. In general `www.` and
    /// the bare name can be different servers.
    static func canonicalHost(_ host: String) -> String {
        let lowercased = host.lowercased()
        if ["localhost", "127.0.0.1", "::1", "[::1]"].contains(lowercased) {
            return "localhost"
        }
        return lowercased.hasPrefix("www.") ? String(lowercased.dropFirst(4)) : lowercased
    }

    /// `component` with its percent-encoded slashes decoded, and nothing else.
    ///
    /// Only the separators are decoded, so any other encoded byte reaches the
    /// site exactly as it was sent, rather than decoded once here and once more
    /// by PHP.
    private static func decodingSlashes(_ component: some StringProtocol) -> String {
        component.replacingOccurrences(of: "%2f", with: "/", options: .caseInsensitive)
    }

    /// The route and query below a plain-permalink root,
    /// `https://site/index.php?rest_route=/`, or `nil` when `target` isn't
    /// below it.
    ///
    /// A prefix match can't decide this shape: the root spells the route `/`,
    /// and every request spells it `%2F`. api-fetch's locale middleware
    /// rebuilds the query through `addQueryArgs`, and WordPress builds
    /// pagination `Link` URLs through `add_query_arg`; both percent-encode every
    /// value. So the route is read out of the query by name, its separators
    /// decoded, and the other parameters are carried verbatim after a `?`.
    /// ``url(forPath:)`` merges them into the root's query.
    private static func queryRoutedPath(of target: URLComponents, below root: URLComponents) -> String? {
        guard target.percentEncodedPathOrSlash == root.percentEncodedPathOrSlash,
              let rootQuery = root.percentEncodedQuery else {
            return nil
        }

        // The root's query is the single `rest_route=/` pair `get_rest_url()`
        // emits; on a namespaced site the value is longer (`/sites/1/`), but it
        // is still the one parameter every request continues.
        let rootRoute = queryPair(rootQuery)
        var pairs = (target.percentEncodedQuery ?? "")
            .split(separator: "&", omittingEmptySubsequences: false)
            .map(String.init)
        guard let index = pairs.firstIndex(where: { queryPair($0).name == rootRoute.name }) else { return nil }

        let route = decodingSlashes(queryPair(pairs.remove(at: index)).value)
        guard route.hasPrefix(rootRoute.value) else { return nil }

        let path = route.dropFirst(rootRoute.value.count)
        let query = pairs.joined(separator: "&")
        return query.isEmpty ? String(path) : "\(path)?\(query)"
    }

    /// A `name=value` query pair split at its first `=`, verbatim.
    private static func queryPair(_ pair: String) -> (name: String, value: String) {
        guard let separator = pair.firstIndex(of: "=") else { return (pair, "") }
        return (String(pair[..<separator]), String(pair[pair.index(after: separator)...]))
    }

    /// Whether `path` contains a `.` or `..` segment, including the
    /// percent-encoded spellings a server may decode before resolving it.
    ///
    /// The separators are decoded alongside the dots. A server that decodes
    /// `%2f` before normalizing — nginx normalizes the request URI ahead of
    /// location matching — reads `%2e%2e%2fwp-admin` as `../wp-admin`, which
    /// splitting on literal slashes alone would pass through. `%5c` is decoded
    /// too because Windows-hosted servers treat a backslash as a separator.
    private static func containsDotSegment(_ path: some StringProtocol) -> Bool {
        let decoded = path.lowercased()
            .replacingOccurrences(of: "%2e", with: ".")
            .replacingOccurrences(of: "%2f", with: "/")
            .replacingOccurrences(of: "%5c", with: "/")
            .replacingOccurrences(of: "\\", with: "/")
        guard decoded.contains(".") else { return false }
        return decoded.split(separator: "/", omittingEmptySubsequences: false).contains {
            $0 == "." || $0 == ".."
        }
    }
}
