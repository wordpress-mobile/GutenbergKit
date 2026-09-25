/**
 * Routes a site URL through the dev server's site proxy.
 *
 * The dev server is cross-origin with the site, so requests to it need CORS
 * preflights, which double the requests sent while the editor loads, and fail
 * on endpoints without CORS headers. The proxy serves the site from the dev
 * server's origin instead. `GBK_SITE_PROXY_PATH` is only defined by the dev
 * server, so production builds use the site URL unchanged.
 *
 * @param {string} url Absolute site URL.
 * @return {string} The proxied URL, or `url` when no proxy applies.
 */
export function toSiteProxyUrl( url ) {
	const proxyPath = import.meta.env.GBK_SITE_PROXY_PATH;
	if ( ! proxyPath || ! url ) {
		return url;
	}

	let parsed;
	try {
		parsed = new URL( url );
	} catch {
		return url;
	}

	const { origin } = window.location;
	if (
		parsed.origin === origin ||
		! [ 'http:', 'https:' ].includes( parsed.protocol )
	) {
		return url;
	}

	const scheme = parsed.protocol.slice( 0, -1 );
	return `${ origin }${ proxyPath }/${ scheme }/${ parsed.host }${ parsed.pathname }${ parsed.search }${ parsed.hash }`;
}
