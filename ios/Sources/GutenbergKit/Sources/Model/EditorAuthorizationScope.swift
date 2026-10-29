import Foundation

/// The requests that may carry a site's credentials.
///
/// Credentials go to the site and to its REST API, and nowhere else. An editor also downloads
/// plugin and theme assets from whichever hosts the site names, and one of those can be a third
/// party's — a script on a vendor's CDN, say — which has no business receiving them.
///
/// An app that knows of other places its credentials belong names them: a site reached through
/// WordPress.com has assets on `wp.com` and files on `files.wordpress.com`, run by the same party
/// as its API. See ``EditorConfigurationBuilder/setAuthHeaderDomains(_:)`` for how they're named.
public struct EditorAuthorizationScope: Sendable, Hashable {

    /// The origins that may receive credentials: the site's, and its REST API's.
    private let origins: Set<Origin>

    /// The hosts that may receive credentials over HTTPS, each named in full.
    private let hosts: Set<String>

    /// The domains that may receive credentials over HTTPS along with their every subdomain:
    /// `wp.com` for `*.wp.com`.
    private let wildcardDomains: Set<String>

    /// Creates the scope for the site in `configuration`.
    public init(configuration: EditorConfiguration) {
        self.init(
            siteURL: configuration.siteURL,
            siteApiRoot: configuration.siteApiRoot,
            domains: configuration.authHeaderDomains
        )
    }

    /// Creates the scope for a site.
    ///
    /// - Parameters:
    ///   - siteURL: The site's address.
    ///   - siteApiRoot: The root of the site's REST API.
    ///   - domains: Other places that may receive the site's credentials, over HTTPS only. A name
    ///     is one host, exactly: `s0.wp.com`. A name that starts with `*.` is the domain that
    ///     follows and every subdomain of it: `*.wp.com`. A name that isn't one of the two is
    ///     ignored.
    public init(siteURL: URL, siteApiRoot: URL, domains: [String] = []) {
        let names = domains.compactMap(Name.init)

        self.origins = Set([Origin(siteURL), Origin(siteApiRoot)].compactMap { $0 })
        self.hosts = Set(names.compactMap { if case .host(let host) = $0 { host } else { nil } })
        self.wildcardDomains = Set(
            names.compactMap { if case .domainAndSubdomains(let domain) = $0 { domain } else { nil } }
        )
    }

    /// Whether a request to `url` may carry the site's credentials.
    public func allows(_ url: URL) -> Bool {
        guard let origin = Origin(url) else {
            return false
        }

        if self.origins.contains(origin) {
            return true
        }

        return origin.scheme == "https"
            && (self.hosts.contains(origin.host)
                || self.wildcardDomains.contains { origin.host == $0 || origin.host.hasSuffix("." + $0) })
    }

    /// What an app names as a place for the site's credentials.
    private enum Name {
        /// One host, exactly.
        case host(String)

        /// A domain and every subdomain of it.
        case domainAndSubdomains(String)

        /// `nil` for a name that is neither: an empty one, or one with a wildcard anywhere but
        /// in front. What a wildcard is over is the app's business: `*.com` is every `.com` site.
        init?(_ name: String) {
            var name = name.trimmingCharacters(in: .whitespaces).lowercased()

            // The dot that ends a fully qualified name
            if name.hasSuffix(".") {
                name.removeLast()
            }

            let isWildcard = name.hasPrefix("*.")
            let domain = isWildcard ? String(name.dropFirst(2)) : name
            let labels = domain.split(separator: ".", omittingEmptySubsequences: false)

            guard labels.allSatisfy({ !$0.isEmpty && !$0.contains("*") }) else {
                return nil
            }

            self = isWildcard ? .domainAndSubdomains(domain) : .host(domain)
        }
    }

    /// A URL's scheme, host and port: what has to match for two URLs to be the same place.
    private struct Origin: Sendable, Hashable {
        let scheme: String
        let host: String
        let port: Int

        /// `nil` for a URL with no host, or with a scheme whose default port isn't known.
        init?(_ url: URL) {
            guard
                let scheme = url.scheme?.lowercased(),
                let host = url.host()?.lowercased(),
                let port = url.port ?? Self.defaultPorts[scheme]
            else {
                return nil
            }

            self.scheme = scheme
            self.host = host
            self.port = port
        }

        private static let defaultPorts = ["http": 80, "https": 443]
    }
}
