package org.wordpress.gutenberg.model

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EditorAuthorizationScopeTest {

    private val site = EditorAuthorizationScope(siteURL = SITE_URL, siteApiRoot = SITE_API_ROOT)

    /** A scope for the test site that names [domains] as well. */
    private fun scope(vararg domains: String) = EditorAuthorizationScope(
        siteURL = SITE_URL,
        siteApiRoot = SITE_API_ROOT,
        domains = domains.toSet()
    )

    // MARK: - The site and its API

    @Test
    fun `a site's credentials may go to the site and its REST API`() {
        listOf(
            "https://example.com/wp-json/wp/v2/posts/1?context=edit",
            "https://example.com/wp-content/plugins/plugin/script.js?ver=1",
            "https://EXAMPLE.com/wp-content/themes/theme/style.css",
            "https://example.com:443/wp-json/"
        ).forEach { assertTrue(it, site.allows(it)) }
    }

    @Test
    fun `a site's credentials go nowhere else, unless the app names the place`() {
        listOf(
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
            "/wp-json/wp/v2/posts",
            "file:///wp-content/script.js",
            ""
        ).forEach { assertFalse(it, site.allows(it)) }
    }

    @Test
    fun `a site served in the clear is allowed its own credentials`() {
        val scope = EditorAuthorizationScope(
            siteURL = "http://localhost:8881",
            siteApiRoot = "http://localhost:8881/wp-json/"
        )

        assertTrue(scope.allows("http://localhost:8881/wp-json/wp/v2/posts"))
        assertFalse(scope.allows("http://localhost:9999/script.js"))
    }

    @Test
    fun `a site whose API is on another host is allowed its credentials at both`() {
        val scope = EditorAuthorizationScope(
            siteURL = "https://example.com",
            siteApiRoot = "https://api.example.com/wp-json/"
        )

        assertTrue(scope.allows("https://example.com/wp-content/script.js"))
        assertTrue(scope.allows("https://api.example.com/wp-json/wp/v2/posts"))
    }

    // MARK: - A named host

    @Test
    fun `a named host is that host, in any case, over HTTPS`() {
        val scope = scope("S0.wp.com")

        assertTrue(scope.allows("https://s0.wp.com/wp-content/plugins/plugin/script.js?m=1"))
        assertTrue(scope.allows("https://S0.WP.com/script.js"))
    }

    @Test
    fun `a named host is no other host`() {
        val scope = scope("s0.wp.com")

        listOf(
            // Its siblings, its subdomains, and the domain it's under
            "https://s1.wp.com/script.js",
            "https://cdn.s0.wp.com/script.js",
            "https://wp.com/script.js",
            // Hosts that only look like it
            "https://s0.wp.com.vendor.net/script.js",
            "https://nots0.wp.com/script.js",
            // The host itself, in the clear
            "http://s0.wp.com/script.js"
        ).forEach { assertFalse(it, scope.allows(it)) }
    }

    /** Naming a host never reaches past it, so even a top-level domain names only itself. */
    @Test
    fun `a top-level domain named as a host covers nothing under it`() {
        listOf("com", "net", "cool", "uk").forEach { domain ->
            val scope = scope(domain)

            assertFalse(domain, scope.allows("https://vendor.$domain/script.js"))
            assertFalse(domain, scope.allows("https://cdn.vendor.$domain/script.js"))
        }
    }

    // MARK: - A wildcard

    @Test
    fun `a wildcard is the domain it's over and every subdomain of it, however deep`() {
        val scope = scope("*.wp.com", "*.files.wordpress.com")

        listOf(
            "https://wp.com/script.js",
            "https://WP.com/script.js",
            "https://files.wordpress.com/image.png",
            "https://s0.wp.com/wp-content/plugins/plugin/script.js?m=1",
            "https://S1.WP.com/_static/??-eJx9jk",
            "https://i0.wp.com/example.com/image.png",
            "https://a.b.wp.com/script.js",
            "https://example.files.wordpress.com/2026/10/image.png",
            "https://Another.Files.WordPress.com/2026/10/image.png"
        ).forEach { assertTrue(it, scope.allows(it)) }
    }

    @Test
    fun `a wildcard is nothing else`() {
        val scope = scope("*.wp.com", "*.files.wordpress.com")

        listOf(
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
            "https://cdn.vendor.net/script.js"
        ).forEach { assertFalse(it, scope.allows(it)) }
    }

    /** What a wildcard is over is the app's business: nothing here second-guesses it. */
    @Test
    fun `a wildcard is taken at its word, however much it covers`() {
        val overTopLevelDomain = scope("*.com")
        assertTrue(overTopLevelDomain.allows("https://vendor.com/script.js"))
        assertTrue(overTopLevelDomain.allows("https://cdn.vendor.com/script.js"))
        assertFalse(overTopLevelDomain.allows("https://vendor.net/script.js"))
        assertFalse(overTopLevelDomain.allows("http://vendor.com/script.js"))

        val overRegistry = scope("*.co.uk")
        assertTrue(overRegistry.allows("https://vendor.co.uk/script.js"))
        assertFalse(overRegistry.allows("https://vendor.org.uk/script.js"))
    }

    // MARK: - Names

    @Test
    fun `a name can end with the dot that ends a fully qualified one`() {
        listOf("*.wp.com.", " *.wp.com ").forEach {
            assertTrue(it, scope(it).allows("https://s0.wp.com/script.js"))
        }
    }

    @Test
    fun `a name that is neither a host nor a wildcard over a domain names nowhere`() {
        listOf(
            "", " ", "*", "*.", ".",
            // Only `*.` in front is a wildcard
            ".wp.com", "s*.wp.com", "*wp.com", "wp.*", "s0.*.com", "*.*.com", "*.*.wp.com",
            // Not a host
            "wp..com", "https://s0.wp.com"
        ).forEach { domain ->
            val scope = scope(domain)

            assertFalse("'$domain'", scope.allows("https://s0.wp.com/script.js"))
            assertFalse("'$domain'", scope.allows("https://wp.com/script.js"))
            assertFalse("'$domain'", scope.allows("https://cdn.vendor.net/script.js"))
        }
    }

    // MARK: - Configuration

    @Test
    fun `the scope for a configuration takes the places the configuration names`() {
        val builder = EditorConfiguration.builder(
            siteURL = "https://example.com",
            siteApiRoot = "https://public-api.wordpress.com/",
            postType = PostTypeDetails.post
        )
        val asset = "https://s0.wp.com/script.js"

        // Where a site's API is says nothing about where else its credentials may go
        assertFalse(EditorAuthorizationScope(builder.build()).allows(asset))
        assertTrue(EditorAuthorizationScope(builder.setAuthHeaderDomains(setOf("*.wp.com")).build()).allows(asset))
    }

    private companion object {
        const val SITE_URL = "https://example.com"
        const val SITE_API_ROOT = "https://example.com/wp-json/"
    }
}
