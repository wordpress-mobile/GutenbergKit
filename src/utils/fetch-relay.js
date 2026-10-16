import { getGBKit } from './bridge';
import { debug } from './logger';

/**
 * The relay wrapper for the host's configuration, or `null` when the host is
 * not running a relay.
 *
 * @return {import('./fetch-chain').FetchWrapper|null} The wrapper.
 */
export function createRelayFetchWrapper() {
	const { restRelay } = getGBKit();

	if ( ! restRelay ) {
		return null;
	}

	debug( `Relaying requests through ${ restRelay.endpoint }` );
	return ( next ) => createRelayFetch( next, { restRelay } );
}

/**
 * Wraps `fetch` so requests to other origins go through the native relay.
 *
 * Under iOS Lockdown Mode the editor's `file://` page loses its CORS exemption
 * and WordPress sanitizes its `Origin: file://` into an empty
 * `Access-Control-Allow-Origin`, so every direct REST request rejects. The
 * native host serves a URL scheme in the editor's own web view and advertises
 * it as `GBKit.restRelay`; it sends each request on natively and responds with
 * CORS headers the web view accepts. Every request takes this path, Lockdown
 * Mode or not, so there is one path to keep working.
 *
 * Each request goes to `restRelay.endpoint`, with the URL it was for in the
 * `url` query parameter. Native code decides how to send it: a request for the
 * site's REST API gets the site credential if it has no `Authorization` of its
 * own, and a request for any other host never does. A caller's own
 * `Authorization` is sent on either way.
 *
 * The relay wraps `fetch` rather than registering an api-fetch middleware or
 * fetch handler, either of which would replace api-fetch's own request building
 * and response parsing — the `data`-to-body serialization, the method override,
 * every parsing rule — and leave us reimplementing a package we do not control.
 * Below `fetch`, this layer only changes where the request goes.
 *
 * @param {typeof fetch}                 next             The fetch to delegate to.
 * @param {Object}                       config           Relay configuration.
 * @param {import('./bridge').RestRelay} config.restRelay Where the relay is.
 * @return {typeof fetch} The wrapped fetch.
 */
export function createRelayFetch( next, { restRelay } ) {
	// `async` so that a throw becomes a rejection, as it would from the `fetch`
	// this stands in for. `new Headers()` rejects a malformed name or value by
	// throwing, and api-fetch's middleware chain calls its `next` synchronously
	// — so a synchronous throw here escapes `apiFetch()` itself rather than
	// arriving at the caller's `.catch()`.
	return async ( input, init ) => {
		// A `no-cors` request has an opaque response by definition, so there is
		// no CORS rejection for the relay to solve — and relaying one hides
		// what it asks: the connectivity probe in `offline-indicator` would
		// report the site reachable whenever native code answered, which is
		// always.
		if ( init?.mode === 'no-cors' ) {
			return next( input, init );
		}

		const target = requestURL( input );
		if ( target === null || ! isRelayed( target ) ) {
			return next( input, init );
		}

		const headers = new Headers( init?.headers );
		const body = await bufferedBody( init?.body, headers );
		const url = encodeURIComponent( target.href );

		return next( `${ restRelay.endpoint }?url=${ url }`, {
			...init,
			headers,
			body,
			// The relay answers `Access-Control-Allow-Origin: *`, which a
			// browser refuses to pair with a credentialed request — and
			// api-fetch defaults `credentials` to `include`. The relay has no
			// use for cookies anyway.
			credentials: 'omit',
		} );
	};
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
		// Resolved against the document, so a relative URL becomes a `file://`
		// (or dev-server) URL, which `isRelayed` leaves alone.
		return new URL( input, document.baseURI );
	} catch {
		return null;
	}
}

/**
 * Whether a request goes through the relay: an `http` or `https` request to
 * another origin.
 *
 * Left on their own path: anything that isn't `http` or `https` — native
 * uploads over `gbk-upload:`, `blob:`/`data:`/`gbk-media-file:` reads, the
 * relay itself — and a request to the page's own origin, which CORS doesn't
 * apply to. That origin is a dev server's when the editor is loaded from one.
 *
 * @param {URL} target The request's target.
 * @return {boolean} Whether to relay it.
 */
function isRelayed( target ) {
	return (
		[ 'http:', 'https:' ].includes( target.protocol ) &&
		target.origin !== window.location.origin
	);
}

/**
 * A request body in a form WebKit delivers to a URL scheme handler.
 *
 * WebKit hands a scheme handler a string or an `ArrayBuffer` body, and drops a
 * `Blob` — or a `FormData` holding one — without an error: the request arrives
 * empty and still succeeds. So every body that is not a string is read into an
 * `ArrayBuffer` first, which costs the body's size in memory. That suits what
 * reaches here: JSON, and the few-megabyte chunks a block's own uploader
 * sends. Core's media uploads reach here only from an editor without site
 * credentials, which doesn't offer native uploads. Otherwise
 * `nativeMediaUploadMiddleware` sends them to native code in chunks before they
 * become a request.
 *
 * Every body, rather than those that are an `instanceof Blob` or `FormData`:
 * one made in another window — an iframe's — is an instance of that window's
 * class, not this one's, and WebKit drops it all the same. `Response` reads a
 * body whichever window made it.
 *
 * What arrives and what is dropped was measured body by body; the table is in
 * `docs/code/media-uploads.md`.
 *
 * `Response` also names the body's type, as `fetch` would have. It gives way
 * to a `Content-Type` the caller set, except for a `FormData`: its boundary
 * exists only in the serialization.
 *
 * @param {unknown} body    The request body, as `fetch` takes it.
 * @param {Headers} headers The request headers, updated in place.
 * @return {Promise<unknown>} The body to send.
 */
async function bufferedBody( body, headers ) {
	if ( body === undefined || body === null || typeof body === 'string' ) {
		return body;
	}

	const serialized = new Response( body );
	const contentType = serialized.headers.get( 'Content-Type' );
	if (
		contentType &&
		( contentType.startsWith( 'multipart/form-data' ) ||
			! headers.has( 'Content-Type' ) )
	) {
		headers.set( 'Content-Type', contentType );
	}
	return serialized.arrayBuffer();
}
