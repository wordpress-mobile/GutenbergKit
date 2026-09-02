/**
 * Internal dependencies
 */
import { getGBKit } from './bridge';
import { debug } from './logger';

/** Hostnames that name the loopback interface. */
const LOOPBACK_HOSTNAMES = new Set( [ 'localhost', '127.0.0.1', '[::1]' ] );

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
 * The relay wraps `fetch` rather than registering an api-fetch middleware or
 * fetch handler, either of which would replace api-fetch's own request building
 * and response parsing — the `data`-to-body serialization, the method override,
 * every parsing rule — and leave us reimplementing a package we do not control.
 * Below `fetch`, this layer only changes where the request goes.
 *
 * @param {typeof fetch}                    next                The fetch to delegate to.
 * @param {Object}                          config              Relay configuration.
 * @param {import('./bridge').NetworkProxy} config.networkProxy Relay connection details.
 * @param {string}                          config.siteApiRoot  The site's REST API root.
 * @return {typeof fetch} The wrapped fetch.
 */
export function createRelayFetch( next, { networkProxy, siteApiRoot } ) {
	const apiRoot = normalizedApiRoot( siteApiRoot );
	const relayRoot = networkProxy.baseURL;
	const localServerPort = String( networkProxy.port );
	const relayAuthorization = `Bearer ${ networkProxy.token }`;
	const apiRootHost = canonicalHost( apiRoot.hostname );

	// `async` so that a throw becomes a rejection, as it would from the `fetch`
	// this stands in for. `new Headers()` rejects a malformed name or value by
	// throwing, and api-fetch's middleware chain calls its `next` synchronously
	// — so a synchronous throw here escapes `apiFetch()` itself rather than
	// arriving at the caller's `.catch()`.
	return async ( input, init ) => {
		// A `no-cors` request has an opaque response by definition, so there is
		// no CORS rejection for the relay to solve — and relaying one breaks it:
		// a browser attaches only CORS-safelisted headers to a no-cors request,
		// so `Relay-Authorization` is dropped and the loopback server answers
		// 407. Opaque responses hide that, which is the trap: the connectivity
		// probe in `offline-indicator` would report the site reachable whenever
		// the relay's own server was up, which is always.
		if ( init?.mode === 'no-cors' ) {
			return next( input, init );
		}

		const target = requestURL( input );
		const upstreamPath =
			target && ! addressesLocalServer( target, localServerPort )
				? relayUpstreamPath( target, apiRoot, apiRootHost )
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
		headers.set( 'Relay-Authorization', relayAuthorization );

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
	const { networkProxy, siteApiRoot } = getGBKit();

	if ( ! networkProxy || ! siteApiRoot ) {
		return null;
	}

	debug( `Relaying site REST requests through port ${ networkProxy.port }` );
	return ( next ) => createRelayFetch( next, { networkProxy, siteApiRoot } );
}

/**
 * The site API root as a `URL`, slash-terminated, with the route value of a
 * plain-permalink root decoded.
 *
 * Slash-terminated so a sibling cannot match the root as a prefix
 * (`https://site/wp-json` would otherwise match `https://site/wp-jsonx/…`),
 * and parsed so both sides of every comparison normalize the same way —
 * default ports collapsed, host lowercased.
 *
 * A plain-permalink root carries its route in the query, and WordPress
 * advertises it percent-encoded — `index.php?rest_route=%2F` — because it
 * builds the URL through `add_query_arg`. The separators are decoded before
 * the slash is added so it lands inside the route value: appended after
 * `%2F`, it would make a root that no path can extend, since WordPress reads
 * `rest_route=%2F/wp/v2/posts` as the route `//wp/v2/posts`. `RestRelay`
 * normalizes the same way, so both sides agree on what the root is.
 *
 * @param {string} siteApiRoot The site's REST API root as configured.
 * @return {URL} The normalized root.
 */
function normalizedApiRoot( siteApiRoot ) {
	const separator = siteApiRoot.indexOf( '?' );
	const root =
		separator === -1
			? siteApiRoot
			: siteApiRoot.slice( 0, separator ) +
			  decodeSlashes( siteApiRoot.slice( separator ) );
	return new URL( root.endsWith( '/' ) ? root : `${ root }/` );
}

/**
 * A URL component with its percent-encoded slashes decoded, and nothing else.
 *
 * Only the separators are decoded so any other encoded byte reaches the site
 * exactly as it was sent, rather than decoded once here and once more by PHP.
 *
 * @param {string} component A URL component.
 * @return {string} The component with `%2F` spelled `/`.
 */
function decodeSlashes( component ) {
	return component.replace( /%2f/gi, '/' );
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
 * Whether a target addresses the native local server, in any spelling of
 * loopback.
 *
 * The relay and the media upload route share one server, and they are addressed
 * by different names: the relay route by address, the upload route by hostname
 * (`localhost` is what Android hosts permit cleartext to). Neither is a site
 * request, so both keep the path they had before a relay existed — the port
 * identifies the server whichever name reached it.
 *
 * @param {URL}    target The request's target.
 * @param {string} port   The local server's port.
 * @return {boolean} Whether the target is the local server.
 */
function addressesLocalServer( target, port ) {
	return target.port === port && LOOPBACK_HOSTNAMES.has( target.hostname );
}

/**
 * The upstream path for a relayed request: the part of its target below the
 * site API root, without a leading slash. `null` for anything else.
 *
 * **Host aliases are tolerated; other hosts and path differences are not.**
 * WordPress builds `Link` headers and `_links` hrefs from `home_url()`, which
 * need not spell the host the app was configured with — `www.` versus bare, or
 * wp-env's `localhost` versus the `127.0.0.1` its runtime writes into
 * `WP_SITEURL` (the e2e fixtures work around the same thing by matching uploads
 * on path rather than hostname, see `e2e/wp-env-fixtures.js`). Only the scheme
 * may differ beyond that — an `http` `siteurl` behind a TLS-terminating proxy.
 * The port has to match: another port on the same host is another server, and
 * answering its request with the site's response is a different bug from the
 * one this tolerance exists to fix. A *path* difference is likewise a different
 * resource: in a subdirectory multisite `https://site/a/wp-json/` and
 * `https://site/b/wp-json/` are separate sites.
 *
 * Anything else keeps the direct path it had before a relay existed, because
 * rewriting it would send a third party's request to the user's own site with
 * the site credential attached. The cost is an alias this cannot recognize —
 * a site reached by LAN IP whose `home_url()` says `localhost`, a mapped
 * domain, a migration — where a paginated `Link` target goes direct and fails
 * under Lockdown Mode. Growing the list of spellings cannot close that: the
 * fix is for the relay to canonicalize the URLs the site emits, since it knows
 * the response came from the configured root and this layer can only guess.
 *
 * @param {URL}    target      The request's target.
 * @param {URL}    apiRoot     The site's REST API root, normalized and slash-terminated.
 * @param {string} apiRootHost `apiRoot`'s hostname in canonical form.
 * @return {string|null} The upstream path, or `null` when it is not a site request.
 */
function relayUpstreamPath( target, apiRoot, apiRootHost ) {
	if (
		canonicalHost( target.hostname ) !== apiRootHost ||
		target.port !== apiRoot.port
	) {
		return null;
	}

	if ( apiRoot.search ) {
		return queryRoutedPath( target, apiRoot );
	}

	const aliased = new URL( target );
	// Only the scheme and the host spelling are left to reconcile; the port
	// matched above, and assigning `hostname` leaves it in place.
	aliased.protocol = apiRoot.protocol;
	aliased.hostname = apiRoot.hostname;

	if ( ! aliased.href.startsWith( apiRoot.href ) ) {
		return null;
	}
	return aliased.href.slice( apiRoot.href.length );
}

/**
 * The upstream path for a request to a root that carries its route in the
 * query — plain permalinks, `https://site/index.php?rest_route=/`.
 *
 * A prefix match on the href cannot decide this shape: the root spells the
 * route `/`, and every request that reaches here spells it `%2F`. api-fetch's
 * locale middleware rebuilds the query through `addQueryArgs`, and WordPress
 * builds pagination `Link` URLs through `add_query_arg`; both percent-encode
 * every value. So the route is read out of the query by name, its separators
 * decoded, and the other parameters are carried verbatim after a `?` — the
 * relay merges them into the root's query, as `createRootURLMiddleware` did.
 *
 * The host and port were matched by the caller. The scheme is not compared,
 * for the same reason it is not for a pretty-permalink root: an `http`
 * `siteurl` behind a TLS-terminating proxy.
 *
 * @param {URL} target  The request's target.
 * @param {URL} apiRoot The site's REST API root, whose query names the route.
 * @return {string|null} The upstream path, or `null` when it is not a site request.
 */
function queryRoutedPath( target, apiRoot ) {
	if ( target.pathname !== apiRoot.pathname ) {
		return null;
	}

	// The root's query is the single `rest_route=/` pair `get_rest_url()`
	// emits; on a namespaced site the value is longer (`/sites/1/`), but it
	// is still the one parameter every request continues.
	const rootRoute = splitQueryPair( apiRoot.search.slice( 1 ) );
	const pairs = target.search.slice( 1 ).split( '&' );
	const index = pairs.findIndex(
		( pair ) => splitQueryPair( pair ).name === rootRoute.name
	);
	if ( index === -1 ) {
		return null;
	}

	const route = decodeSlashes( splitQueryPair( pairs[ index ] ).value );
	if ( ! route.startsWith( rootRoute.value ) ) {
		return null;
	}

	const path = route.slice( rootRoute.value.length );
	const query = pairs.filter( ( _, i ) => i !== index ).join( '&' );
	return query ? `${ path }?${ query }` : path;
}

/**
 * A `name=value` query pair split at its first `=`, verbatim.
 *
 * @param {string} pair One pair of a query string.
 * @return {{name: string, value: string}} The name and the value, the latter `''` if absent.
 */
function splitQueryPair( pair ) {
	const separator = pair.indexOf( '=' );
	return separator === -1
		? { name: pair, value: '' }
		: {
				name: pair.slice( 0, separator ),
				value: pair.slice( separator + 1 ),
		  };
}

/**
 * A hostname reduced to the form its aliases share: every loopback spelling
 * collapses to one, and a `www.` prefix is dropped.
 *
 * @param {string} hostname A URL hostname.
 * @return {string} The canonical form.
 */
function canonicalHost( hostname ) {
	if ( LOOPBACK_HOSTNAMES.has( hostname ) ) {
		return 'localhost';
	}
	return hostname.replace( /^www\./, '' );
}
