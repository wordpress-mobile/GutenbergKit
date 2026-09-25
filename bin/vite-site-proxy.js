/**
 * External dependencies
 */
import http from 'http';
import https from 'https';

/**
 * Dev server path that forwards requests to the site, e.g.
 * `/__site-proxy/https/example.com/wp-json/wp/v2/posts`.
 */
export const SITE_PROXY_PATH = '/__site-proxy';

/** Matches the target and remaining path of a proxied request. */
const PROXY_TARGET = /^\/(https?)\/([^/?#]+)([/?].*)?$/;

/** Hop-by-hop and dev-server-specific headers that must not be forwarded. */
const DROPPED_REQUEST_HEADERS = [
	'connection',
	'cookie',
	'keep-alive',
	'origin',
	'proxy-authorization',
	'referer',
	'te',
	'trailer',
	'transfer-encoding',
	'upgrade',
];

/** Hop-by-hop headers that must not be returned. */
const DROPPED_RESPONSE_HEADERS = [
	'connection',
	'keep-alive',
	'proxy-authenticate',
	'trailer',
	'transfer-encoding',
	'upgrade',
];

/**
 * Vite plugin serving the site's API from the dev server's origin.
 *
 * The dev server is cross-origin with the site, so every authenticated request
 * needs a CORS preflight. That doubles the requests sent while the editor
 * loads, which some hosts rate-limit, and it blocks endpoints without CORS
 * headers, such as `admin-ajax.php`. Production builds load from the site's
 * origin and need neither.
 *
 * @return {import('vite').Plugin} The plugin.
 */
export function siteProxy() {
	return {
		name: 'gbk-site-proxy',
		apply: 'serve',
		config: () => ( {
			define: {
				'import.meta.env.GBK_SITE_PROXY_PATH':
					JSON.stringify( SITE_PROXY_PATH ),
			},
		} ),
		configureServer( server ) {
			server.middlewares.use( SITE_PROXY_PATH, proxySiteRequest );
		},
	};
}

/**
 * Forwards a dev server request to the site and streams back its response.
 *
 * Exported for testing only.
 *
 * @param {http.IncomingMessage} req Request, with `url` relative to the proxy path.
 * @param {http.ServerResponse}  res Response.
 */
export function proxySiteRequest( req, res ) {
	const target = resolveTarget( req.url, req.headers.host );
	if ( ! target ) {
		res.statusCode = 403;
		res.end( 'The site proxy only forwards WordPress API requests.' );
		return;
	}

	const headers = { ...req.headers, host: target.upstream.host };
	for ( const name of DROPPED_REQUEST_HEADERS ) {
		delete headers[ name ];
	}

	const proxyBase = `http://${ req.headers.host }${ SITE_PROXY_PATH }/${ target.scheme }/${ target.host }`;
	const client = target.scheme === 'https' ? https : http;
	const upstreamRequest = client.request(
		target.upstream,
		{ method: req.method, headers },
		( upstreamResponse ) => {
			const responseHeaders = { ...upstreamResponse.headers };
			for ( const name of DROPPED_RESPONSE_HEADERS ) {
				delete responseHeaders[ name ];
			}
			// Keep pagination and redirects on the proxy.
			for ( const name of [ 'link', 'location' ] ) {
				if ( responseHeaders[ name ] ) {
					responseHeaders[ name ] = rewriteSiteUrls(
						responseHeaders[ name ],
						target.origins,
						proxyBase
					);
				}
			}
			res.writeHead( upstreamResponse.statusCode, responseHeaders );
			upstreamResponse.pipe( res );
		}
	);

	upstreamRequest.on( 'error', ( err ) => {
		if ( ! res.headersSent ) {
			res.statusCode = 502;
		}
		res.end( `Site proxy error: ${ err.message }` );
	} );
	req.pipe( upstreamRequest );
}

/**
 * Resolves the site URL a proxied request targets.
 *
 * Forwarding is limited to WordPress API requests, because the dev server may
 * be reachable from the local network. A target on the host the device used
 * to reach the dev server, such as the Android emulator's `10.0.2.2`, is this
 * machine, so it is reached through `localhost`.
 *
 * Exported for testing only.
 *
 * @param {string} url           Request URL relative to the proxy path.
 * @param {string} devServerHost The request's `Host` header.
 * @return {?{scheme: string, host: string, upstream: URL, origins: string[]}} The target, or null when not allowed.
 */
export function resolveTarget( url, devServerHost ) {
	const match = PROXY_TARGET.exec( url ?? '' );
	if ( ! match ) {
		return null;
	}

	const [ , scheme, host, rest = '/' ] = match;
	let upstream;
	try {
		upstream = new URL( `${ scheme }://${ host }${ rest }` );
	} catch {
		return null;
	}

	if ( ! isWordPressApiUrl( upstream ) ) {
		return null;
	}

	const origins = [ upstream.origin ];
	const devServerHostname = devServerHost?.replace( /:\d+$/, '' );
	if ( upstream.hostname === devServerHostname ) {
		upstream.hostname = 'localhost';
		origins.push( upstream.origin );
	}

	return { scheme, host, upstream, origins };
}

/**
 * Whether a URL is a WordPress REST API or AJAX request.
 *
 * @param {URL} url The URL.
 * @return {boolean} True for REST API and `admin-ajax.php` URLs.
 */
function isWordPressApiUrl( url ) {
	return (
		url.hostname === 'public-api.wordpress.com' ||
		/\/wp-json(\/|$)/.test( url.pathname ) ||
		url.pathname.endsWith( '/wp-admin/admin-ajax.php' ) ||
		url.searchParams.has( 'rest_route' )
	);
}

/**
 * Points absolute site URLs in a header value at the proxy.
 *
 * Exported for testing only.
 *
 * @param {string|string[]} value     Header value.
 * @param {string[]}        origins   Site origins to replace.
 * @param {string}          proxyBase Proxy URL standing in for the site origin.
 * @return {string|string[]} The rewritten value.
 */
export function rewriteSiteUrls( value, origins, proxyBase ) {
	if ( Array.isArray( value ) ) {
		return value.map( ( item ) =>
			rewriteSiteUrls( item, origins, proxyBase )
		);
	}

	return origins.reduce(
		( result, origin ) =>
			result.split( `${ origin }/` ).join( `${ proxyBase }/` ),
		value
	);
}
