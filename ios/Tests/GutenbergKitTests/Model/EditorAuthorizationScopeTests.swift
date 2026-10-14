import Foundation
import Testing

@testable import GutenbergKit

@Suite
struct EditorAuthorizationScopeTests {

    private static let siteURL = URL(string: "https://example.com")!
    private static let siteApiRoot = URL(string: "https://example.com/wp-json/")!

    private let site = EditorAuthorizationScope(siteURL: siteURL, siteApiRoot: siteApiRoot)

    /// A scope for the test site that names `domains` as well.
    private func scope(naming domains: [String]) -> EditorAuthorizationScope {
        EditorAuthorizationScope(siteURL: Self.siteURL, siteApiRoot: Self.siteApiRoot, domains: domains)
    }

    private func url(_ string: String) -> URL {
        URL(string: string)!
    }

    // MARK: - The site and its API

    @Test(
        "a site's credentials may go to the site and its REST API",
        arguments: [
            "https://example.com/wp-json/wp/v2/posts/1?context=edit",
            "https://example.com/wp-content/plugins/plugin/script.js?ver=1",
            "https://EXAMPLE.com/wp-content/themes/theme/style.css",
            "https://example.com:443/wp-json/",
        ]
    )
    func allowsSite(url: String) {
        #expect(site.allows(self.url(url)))
    }

    @Test(
        "a site's credentials go nowhere else, unless the app names the place",
        arguments: [
            // Another party's host
            "https://cdn.vendor.net/script.js",
            // Hosts that only look like the site's
            "https://example.com.vendor.net/script.js",
            "https://notexample.com/script.js",
            "https://cdn.example.com/script.js",
            // The site's host, but not the place it was configured with
            "http://example.com/wp-content/plugins/plugin/script.js",
            "https://example.com:8443/script.js",
            // Places an app could name, and this one hasn't
            "https://s0.wp.com/wp-content/plugins/plugin/script.js",
            "https://example.files.wordpress.com/2026/10/image.png",
            // Nowhere at all
            "file:///wp-content/script.js",
            "data:text/javascript,",
        ]
    )
    func deniesEverywhereElse(url: String) {
        #expect(!site.allows(self.url(url)))
    }

    @Test("a site served in the clear is allowed its own credentials")
    func allowsSiteServedInTheClear() {
        let scope = EditorAuthorizationScope(
            siteURL: url("http://localhost:8881"),
            siteApiRoot: url("http://localhost:8881/wp-json/")
        )

        #expect(scope.allows(url("http://localhost:8881/wp-json/wp/v2/posts")))
        #expect(!scope.allows(url("http://localhost:9999/script.js")))
    }

    @Test("a site whose API is on another host is allowed its credentials at both")
    func allowsSiteAndApiOnDifferentHosts() {
        let scope = EditorAuthorizationScope(
            siteURL: url("https://example.com"),
            siteApiRoot: url("https://api.example.com/wp-json/")
        )

        #expect(scope.allows(url("https://example.com/wp-content/script.js")))
        #expect(scope.allows(url("https://api.example.com/wp-json/wp/v2/posts")))
    }

    // MARK: - A named host

    @Test("a named host is that host, in any case, over HTTPS")
    func allowsNamedHost() {
        let scope = scope(naming: ["S0.wp.com"])

        #expect(scope.allows(url("https://s0.wp.com/wp-content/plugins/plugin/script.js?m=1")))
        #expect(scope.allows(url("https://S0.WP.com/script.js")))
    }

    @Test(
        "a named host is no other host",
        arguments: [
            // Its siblings, its subdomains, and the domain it's under
            "https://s1.wp.com/script.js",
            "https://cdn.s0.wp.com/script.js",
            "https://wp.com/script.js",
            // Hosts that only look like it
            "https://s0.wp.com.vendor.net/script.js",
            "https://nots0.wp.com/script.js",
            // The host itself, in the clear
            "http://s0.wp.com/script.js",
        ]
    )
    func deniesAllButNamedHost(url: String) {
        #expect(!scope(naming: ["s0.wp.com"]).allows(self.url(url)))
    }

    /// Naming a host never reaches past it, so even a top-level domain names only itself.
    @Test("a top-level domain named as a host covers nothing under it", arguments: ["com", "net", "cool", "uk"])
    func namedTopLevelDomainCoversNothingUnderIt(domain: String) {
        let scope = scope(naming: [domain])

        #expect(!scope.allows(url("https://vendor.\(domain)/script.js")))
        #expect(!scope.allows(url("https://cdn.vendor.\(domain)/script.js")))
    }

    // MARK: - A wildcard

    @Test(
        "a wildcard is the domain it's over and every subdomain of it, however deep",
        arguments: [
            "https://wp.com/script.js",
            "https://WP.com/script.js",
            "https://files.wordpress.com/image.png",
            "https://s0.wp.com/wp-content/plugins/plugin/script.js?m=1",
            "https://S1.WP.com/_static/??-eJx9jk",
            "https://i0.wp.com/example.com/image.png",
            "https://a.b.wp.com/script.js",
            "https://example.files.wordpress.com/2026/10/image.png",
            "https://Another.Files.WordPress.com/2026/10/image.png",
        ]
    )
    func allowsDomainAndSubdomainsOfWildcard(url: String) {
        #expect(scope(naming: ["*.wp.com", "*.files.wordpress.com"]).allows(self.url(url)))
    }

    @Test(
        "a wildcard is nothing else",
        arguments: [
            // Hosts that only look like the domain or its subdomains
            "https://notwp.com/script.js",
            "https://wp.com.vendor.net/script.js",
            "https://files.wordpress.com.vendor.net/image.png",
            "https://notfiles.wordpress.com/image.png",
            // A domain above it
            "https://another.wordpress.com/script.js",
            // The domain and its subdomains, in the clear
            "http://wp.com/script.js",
            "http://s0.wp.com/script.js",
            "http://example.files.wordpress.com/2026/10/image.png",
            // Another party's host
            "https://cdn.vendor.net/script.js",
        ]
    )
    func deniesAllButDomainAndSubdomainsOfWildcard(url: String) {
        #expect(!scope(naming: ["*.wp.com", "*.files.wordpress.com"]).allows(self.url(url)))
    }

    /// What a wildcard is over is the app's business: nothing here second-guesses it.
    @Test("a wildcard is taken at its word, however much it covers")
    func takesWildcardAtItsWord() {
        let overTopLevelDomain = scope(naming: ["*.com"])
        #expect(overTopLevelDomain.allows(url("https://vendor.com/script.js")))
        #expect(overTopLevelDomain.allows(url("https://cdn.vendor.com/script.js")))
        #expect(!overTopLevelDomain.allows(url("https://vendor.net/script.js")))
        #expect(!overTopLevelDomain.allows(url("http://vendor.com/script.js")))

        let overRegistry = scope(naming: ["*.co.uk"])
        #expect(overRegistry.allows(url("https://vendor.co.uk/script.js")))
        #expect(!overRegistry.allows(url("https://vendor.org.uk/script.js")))
    }

    // MARK: - Names

    @Test("a name can end with the dot that ends a fully qualified one", arguments: ["*.wp.com.", " *.wp.com "])
    func allowsFullyQualifiedName(domain: String) {
        #expect(scope(naming: [domain]).allows(url("https://s0.wp.com/script.js")))
    }

    @Test(
        "a name that is neither a host nor a wildcard over a domain names nowhere",
        arguments: [
            "", " ", "*", "*.", ".",
            // Only `*.` in front is a wildcard
            ".wp.com", "s*.wp.com", "*wp.com", "wp.*", "s0.*.com", "*.*.com", "*.*.wp.com",
            // Not a host
            "wp..com", "https://s0.wp.com",
        ]
    )
    func ignoresMalformedName(domain: String) {
        let scope = scope(naming: [domain])

        #expect(!scope.allows(url("https://s0.wp.com/script.js")))
        #expect(!scope.allows(url("https://wp.com/script.js")))
        #expect(!scope.allows(url("https://cdn.vendor.net/script.js")))
    }

    // MARK: - Configuration

    @Test("the scope for a configuration takes the places the configuration names")
    func takesNamesFromConfiguration() {
        let builder = EditorConfigurationBuilder(
            postType: .post,
            siteURL: url("https://example.com"),
            siteApiRoot: url("https://public-api.wordpress.com/")
        )
        let asset = url("https://s0.wp.com/script.js")

        // Where a site's API is says nothing about where else its credentials may go
        #expect(!EditorAuthorizationScope(configuration: builder.build()).allows(asset))
        #expect(
            EditorAuthorizationScope(configuration: builder.setAuthHeaderDomains(["*.wp.com"]).build()).allows(asset)
        )
    }
}
