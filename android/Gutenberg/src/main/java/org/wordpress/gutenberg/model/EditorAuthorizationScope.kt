package org.wordpress.gutenberg.model

import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/**
 * The requests that may carry a site's credentials.
 *
 * Credentials go to the site and to its REST API, and nowhere else. An editor also downloads
 * plugin and theme assets from whichever hosts the site names, and one of those can be a third
 * party's — a script on a vendor's CDN, say — which has no business receiving them.
 *
 * An app that knows of other places its credentials belong names them: a site reached through
 * WordPress.com has assets on `wp.com` and files on `files.wordpress.com`, run by the same party
 * as its API. See [EditorConfiguration.Builder.setAuthHeaderDomains] for how they're named.
 *
 * @param siteURL The site's address.
 * @param siteApiRoot The root of the site's REST API.
 * @param domains Other places that may receive the site's credentials, over HTTPS only. A name is
 *   one host, exactly: `s0.wp.com`. A name that starts with `*.` is the domain that follows and
 *   every subdomain of it: `*.wp.com`. A name that isn't one of the two is ignored.
 */
class EditorAuthorizationScope(
    siteURL: String,
    siteApiRoot: String,
    domains: Collection<String> = emptySet()
) {

    /** Creates the scope for the site in [configuration]. */
    constructor(configuration: EditorConfiguration) : this(
        siteURL = configuration.siteURL,
        siteApiRoot = configuration.siteApiRoot,
        domains = configuration.authHeaderDomains
    )

    /** The origins that may receive credentials: the site's, and its REST API's. */
    private val origins: Set<Origin> = setOfNotNull(Origin.of(siteURL), Origin.of(siteApiRoot))

    private val names: List<Name> = domains.mapNotNull(Name::of)

    /** The hosts that may receive credentials over HTTPS, each named in full. */
    private val hosts: Set<String> = names.filterIsInstance<Name.Host>().map { it.host }.toSet()

    /**
     * The domains that may receive credentials over HTTPS along with their every subdomain:
     * `wp.com` for `*.wp.com`.
     */
    private val wildcardDomains: Set<String> =
        names.filterIsInstance<Name.DomainAndSubdomains>().map { it.domain }.toSet()

    /** Whether a request to [url] may carry the site's credentials. */
    fun allows(url: String): Boolean {
        val origin = Origin.of(url) ?: return false

        if (origin in origins) {
            return true
        }

        return origin.scheme == "https" &&
            (origin.host in hosts || wildcardDomains.any { origin.host == it || origin.host.endsWith(".$it") })
    }

    /** What an app names as a place for the site's credentials. */
    private sealed interface Name {
        /** One host, exactly. */
        data class Host(val host: String) : Name

        /** A domain and every subdomain of it. */
        data class DomainAndSubdomains(val domain: String) : Name

        companion object {
            private const val WILDCARD = "*."

            /**
             * `null` for a name that is neither: an empty one, or one with a wildcard anywhere
             * but in front. What a wildcard is over is the app's business: `*.com` is every
             * `.com` site.
             */
            fun of(name: String): Name? {
                // Without the dot that ends a fully qualified name
                val trimmed = name.trim().lowercase().removeSuffix(".")
                val isWildcard = trimmed.startsWith(WILDCARD)
                val domain = trimmed.removePrefix(WILDCARD)
                val labels = domain.split(".")

                return when {
                    labels.any { it.isEmpty() || it.contains("*") } -> null
                    isWildcard -> DomainAndSubdomains(domain)
                    else -> Host(domain)
                }
            }
        }
    }

    /** A URL's scheme, host and port: what has to match for two URLs to be the same place. */
    private data class Origin(val scheme: String, val host: String, val port: Int) {
        companion object {
            /** `null` for anything but an absolute `http` or `https` URL. */
            fun of(url: String): Origin? =
                url.toHttpUrlOrNull()?.let { Origin(scheme = it.scheme, host = it.host, port = it.port) }
        }
    }
}
