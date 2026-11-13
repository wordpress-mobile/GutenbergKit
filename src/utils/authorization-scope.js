/**
 * Whether a request to `requestUrl` may carry the site's credentials.
 *
 * Credentials go to the site and to its REST API, and nowhere else. A request
 * can be for anywhere — a plugin's block can call another party's service —
 * and that party has no business receiving them.
 *
 * An app that knows of other places its credentials belong names them in
 * `authHeaderDomains`: a site reached through WordPress.com has assets on
 * `wp.com` and files on `files.wordpress.com`, run by the same party as its
 * API. Only requests over HTTPS qualify, and each name is taken exactly as
 * written:
 *
 * - `s0.wp.com` is that one host, and not its subdomains.
 * - `*.wp.com` is `wp.com` and every subdomain of it.
 *
 * A wildcard is taken at its word: `*.com` is every `.com` site.
 *
 * For the site and its API, scheme, host, and port must all match, so that a
 * lookalike host (e.g. `https://example.com.evil.com`) or the site's host in
 * the clear is refused.
 *
 * @param {string}   requestUrl               The URL of the outgoing request.
 * @param {Object}   site                     The site the credentials belong to.
 * @param {string}   [site.siteURL]           The site's home URL.
 * @param {string}   [site.siteApiRoot]       The root URL of the site's API.
 * @param {string[]} [site.authHeaderDomains] Other places that may receive the credentials.
 * @return {boolean} Whether the request may carry the site's credentials.
 */
export function isWithinAuthorizationScope(
	requestUrl,
	{ siteURL, siteApiRoot, authHeaderDomains = [] } = {}
) {
	const request = parseUrl( requestUrl );

	if ( ! request ) {
		return false;
	}

	if (
		request.origin === parseUrl( siteURL )?.origin ||
		request.origin === parseUrl( siteApiRoot )?.origin
	) {
		return true;
	}

	return (
		request.protocol === 'https:' &&
		authHeaderDomains
			.map( parseName )
			.some( ( name ) => name?.matches( request.hostname ) )
	);
}

/**
 * Parses an absolute `http` or `https` URL.
 *
 * @param {string} [value] The URL to parse.
 * @return {URL|undefined} The parsed URL, or `undefined` for anything else:
 *                         a relative URL, or a scheme with no origin of its
 *                         own, belongs to no site.
 */
function parseUrl( value ) {
	try {
		const url = new URL( value );
		return [ 'http:', 'https:' ].includes( url.protocol ) ? url : undefined;
	} catch {
		return undefined;
	}
}

/**
 * Parses what an app names as a place for the site's credentials: one host,
 * or with `*.` in front, a domain and every subdomain of it.
 *
 * @param {string} name The name as the app wrote it.
 * @return {{matches: function(string): boolean}|undefined} What the name
 *         covers, or `undefined` for a name that is neither: an empty one,
 *         or one with a wildcard anywhere but in front.
 */
function parseName( name ) {
	// Without the dot that ends a fully qualified name
	const trimmed = String( name ?? '' )
		.trim()
		.toLowerCase()
		.replace( /\.$/, '' );
	const isWildcard = trimmed.startsWith( '*.' );
	const domain = isWildcard ? trimmed.slice( 2 ) : trimmed;
	const labels = domain.split( '.' );

	if ( labels.some( ( label ) => label === '' || label.includes( '*' ) ) ) {
		return undefined;
	}

	if ( ! isWildcard ) {
		return { matches: ( hostname ) => hostname === domain };
	}

	return {
		matches: ( hostname ) =>
			hostname === domain || hostname.endsWith( `.${ domain }` ),
	};
}
