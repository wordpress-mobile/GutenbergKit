/**
 * Internal dependencies
 */
import { getGBKit, getNetworkProxy } from './bridge';
import { debug } from './logger';

/**
 * Wraps `fetch` so requests for the site's REST API go through the native
 * loopback relay.
 *
 * Under iOS Lockdown Mode the editor's `file://` page loses its CORS exemption
 * and WordPress sanitizes its `Origin: file://` into an empty
 * `Access-Control-Allow-Origin`, so every direct REST request rejects. The
 * native host answers by running a loopback server and advertising it as
 * `GBKit.networkProxy`; it forwards each request to the site's REST API
 * natively and responds with CORS headers the web view accepts.
 *
 * ## Why the transport, and not `apiFetch`
 *
 * `apiFetch.use()` unshifts and api-fetch composes with `reduceRight`, so a
 * registered middleware always runs *outside* api-fetch's own middleware and
 * outside `defaultFetchHandler` — it would short-circuit past the `data`-to-body
 * serialization, the default `Accept` header, the HTTP v1 method override, and
 * every response-parsing rule, all of which would then have to be reimplemented
 * and kept in step with a package we do not control. `setFetchHandler` runs late
 * enough for the request half but still replaces the response half.
 *
 * Wrapping `fetch` puts the relay below all of it: api-fetch builds the whole
 * request, hands it to `fetch`, and parses whatever comes back. This layer only
 * changes where the request goes.
 *
 * @param {typeof fetch}                  next                The fetch to delegate to.
 * @param {Object}                        config              Relay configuration.
 * @param {{port: number, token: string}} config.networkProxy Relay connection details.
 * @param {string}                        config.siteApiRoot  The site's REST API root.
 * @return {typeof fetch} The wrapped fetch.
 */
export function createRelayFetch( next, { networkProxy, siteApiRoot } ) {
	// Slash-terminated so a sibling cannot match the root as a prefix
	// (`https://site/wp-json` would otherwise match `https://site/wp-jsonx/…`),
	// and parsed so both sides of every comparison normalize the same way —
	// default ports collapsed, host lowercased.
	const apiRoot = new URL(
		siteApiRoot.endsWith( '/' ) ? siteApiRoot : `${ siteApiRoot }/`
	);
	const relayRoot = `http://127.0.0.1:${ networkProxy.port }/proxy/`;
	const relayOrigin = new URL( relayRoot ).origin;

	return ( input, init ) => {
		const target = requestURL( input );
		const upstreamPath =
			target && target.origin !== relayOrigin
				? relayUpstreamPath( target, apiRoot )
				: null;

		// Not a site REST request: media uploads to the loopback server,
		// `blob:`/`data:`/`gbk-media-file:` reads, a third party's own API.
		// Those keep the network path they had before a relay existed.
		if ( upstreamPath === null ) {
			return next( input, init );
		}

		const headers = new Headers( init?.headers );
		// The site credential is injected natively, so it never travels over
		// loopback. The relay's own per-session token rides in
		// `Relay-Authorization` because `fetch()` silently strips `Proxy-*`.
		headers.delete( 'Authorization' );
		headers.set( 'Relay-Authorization', `Bearer ${ networkProxy.token }` );

		return next( relayRoot + upstreamPath, {
			...init,
			headers,
			// The relay answers `Access-Control-Allow-Origin: *`, which a
			// browser refuses to pair with a credentialed request — and
			// api-fetch defaults `credentials` to `include`. Cookies are not
			// how the loopback server authenticates anyway; the bearer token is.
			credentials: 'omit',
		} );
	};
}

/**
 * The relay wrapper for the host's configuration, or `null` when the host is
 * not running a relay.
 *
 * @return {import('./fetch-chain').FetchWrapper|null} The wrapper.
 */
export function createRelayFetchWrapper() {
	const networkProxy = getNetworkProxy();
	const { siteApiRoot } = getGBKit();

	if ( ! networkProxy || ! siteApiRoot ) {
		return null;
	}

	debug( `Relaying site REST requests through port ${ networkProxy.port }` );
	return ( next ) => createRelayFetch( next, { networkProxy, siteApiRoot } );
}

/**
 * The URL a `fetch` call addresses, or `null` when it cannot be determined.
 *
 * A `Request` object returns `null` rather than being relayed: rewriting one
 * means rebuilding it, and nothing in the editor's REST path constructs one —
 * api-fetch always calls `fetch( url, init )`. Such a request keeps the direct
 * path it had before a relay existed.
 *
 * @param {string|URL|Request} input The first argument to `fetch`.
 * @return {URL|null} The target URL.
 */
function requestURL( input ) {
	if ( typeof input !== 'string' && ! ( input instanceof URL ) ) {
		return null;
	}
	try {
		// Resolved against the document so a relative URL becomes a `file://`
		// (or dev-server) URL, which cannot match the API root and so is never
		// mistaken for a site request.
		return new URL( input, document.baseURI );
	} catch {
		return null;
	}
}

/**
 * The upstream path for a relayed request: the part of its target below the
 * site API root, without a leading slash. `null` for anything else.
 *
 * **Host aliases are tolerated; path differences are not.** WordPress builds
 * `Link` headers and `_links` hrefs from `home_url()`, which need not be the
 * host the app was configured with — `www.` versus bare, a mapped or
 * reverse-proxied domain, an `http` `siteurl` behind `https`. wp-env is the
 * everyday case, and a documented one: the Playground runtime resolves
 * `localhost` to `127.0.0.1` in `WP_SITEURL`, which the e2e fixtures already
 * work around by matching uploads on path rather than hostname (see
 * `e2e/wp-env-fixtures.js`). Those are the same resource under another name, so
 * the target is moved onto the root's origin before comparing. A *path*
 * difference is a different resource: in a subdirectory multisite
 * `https://site/a/wp-json/` and `https://site/b/wp-json/` are separate sites,
 * and matching across them would route one site's request into the other's API
 * root.
 *
 * @param {URL} target  The request's target.
 * @param {URL} apiRoot The site's REST API root, normalized and slash-terminated.
 * @return {string|null} The upstream path, or `null` when it is not a site request.
 */
function relayUpstreamPath( target, apiRoot ) {
	const aliased = new URL( target );
	// Assign the origin's parts separately: the `host` setter leaves an
	// existing port in place when the value carries none, so `host` alone turns
	// `http://127.0.0.1:8888/…` into `https://example.com:8888/…`.
	aliased.protocol = apiRoot.protocol;
	aliased.hostname = apiRoot.hostname;
	aliased.port = apiRoot.port;

	if ( ! aliased.href.startsWith( apiRoot.href ) ) {
		return null;
	}
	return aliased.href.slice( apiRoot.href.length );
}
