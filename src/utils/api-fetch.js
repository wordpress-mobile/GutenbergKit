/**
 * WordPress dependencies
 */
import apiFetch from '@wordpress/api-fetch';
import { getQueryArg } from '@wordpress/url';
import { __ } from '@wordpress/i18n';

/**
 * Internal dependencies
 */
import { getGBKit, getNetworkProxy, POST_FALLBACKS } from './bridge';
import { info, error as logError } from './logger';

/**
 * @typedef {import('@wordpress/api-fetch').APIFetchMiddleware} APIFetchMiddleware
 */

/** Matches `POST /wp/v2/media` but not sub-paths like `/wp/v2/media/123`. */
const MEDIA_UPLOAD_PATH = /^\/wp\/v2\/media(\?|$)/;

/**
 * Initializes the API fetch configuration and middleware.
 *
 * @return {void}
 */
export function configureApiFetch() {
	const { siteApiRoot = '', preloadData = null } = getGBKit();
	const networkProxy = getNetworkProxy();

	// The relay replaces the transport rather than intercepting requests,
	// because `apiFetch.use()` unshifts and api-fetch applies its middleware
	// with `reduceRight`: a registered middleware can never run innermost, so
	// interception there would short-circuit past api-fetch's own middleware —
	// losing `_locale=user`, the `per_page=-1` expansion, and the HTTP v1
	// method override — and past everything `defaultFetchHandler` does.
	if ( networkProxy ) {
		apiFetch.setFetchHandler(
			createRelayFetchHandler( networkProxy, siteApiRoot )
		);
	}

	apiFetch.use( apiFetch.createRootURLMiddleware( siteApiRoot ) );
	apiFetch.use( corsMiddleware );
	apiFetch.use( apiPathModifierMiddleware );
	apiFetch.use( tokenAuthMiddleware );
	apiFetch.use( filterEndpointsMiddleware );
	apiFetch.use( nativeMediaUploadMiddleware );
	apiFetch.use( mediaUploadMiddleware );
	apiFetch.use( transformOEmbedApiResponse );
	apiFetch.use(
		apiFetch.createPreloadingMiddleware( preloadData ?? defaultPreloadData )
	);
}

/**
 * Header values api-fetch's own handler defaults, which this transport
 * replaces. WordPress treats `Accept` as a condition for handling a request as
 * a REST request (core trac 44534), so losing it changes what the site returns.
 */
const DEFAULT_RELAY_HEADERS = {
	Accept: 'application/json, */*;q=0.1',
};

/**
 * Builds the api-fetch transport that routes every request through the native
 * loopback relay.
 *
 * Under iOS Lockdown Mode the editor's `file://` page loses its CORS exemption
 * and WordPress sanitizes its `Origin: file://` into an empty
 * `Access-Control-Allow-Origin`, so every direct REST request rejects. The
 * native host answers by running a loopback server and advertising it as
 * `GBKit.networkProxy`; it forwards each request to the site's REST API
 * natively and responds with CORS headers the web view accepts.
 *
 * Whether to use it is decided by that configuration alone. The relay is only
 * advertised when the host knows direct requests cannot work, so attempting one
 * first would be a guaranteed-doomed round trip per request — and inferring the
 * answer from a response, as this once did, means one misleading response can
 * latch the editor onto the wrong path for the rest of the session.
 *
 * Installed as the fetch handler rather than a middleware, so api-fetch's own
 * middleware has already run and `options` carries the finished request.
 * `defaultFetchHandler` is not exported, so what it does — `data` to a JSON
 * body, default headers, response parsing and error normalization — is
 * reproduced here.
 *
 * @param {Object} networkProxy       Relay connection details.
 * @param {number} networkProxy.port  Loopback port.
 * @param {string} networkProxy.token Per-session bearer token.
 * @param {string} siteApiRoot        The site's REST API root.
 * @return {(options: Object) => Promise<any>} The fetch handler.
 */
function createRelayFetchHandler( networkProxy, siteApiRoot ) {
	// Slash-terminated so a sibling cannot match the root as a prefix
	// (`https://site/wp-json` would otherwise match `https://site/wp-jsonx/…`),
	// and parsed so both sides of the comparison are normalized the same way —
	// default ports collapsed, host lowercased.
	const apiRoot = new URL(
		siteApiRoot.endsWith( '/' ) ? siteApiRoot : `${ siteApiRoot }/`
	);
	// The upstream path follows the route; the relay resolves it natively
	// against the site API root, so no absolute URL is ever sent.
	const relayRoot = `http://127.0.0.1:${ networkProxy.port }/proxy/`;

	return async ( options ) => {
		const { data, parse = true, method = 'GET', signal } = options;

		const upstreamPath = relayUpstreamPath(
			options.url ?? options.path ?? '',
			apiRoot
		);
		if ( upstreamPath === null ) {
			logError(
				'api-fetch: refusing to relay a request outside the site API root',
				options.url ?? options.path
			);
			throw {
				code: 'fetch_error',
				message: __(
					'Could not get a valid response from the server.'
				),
			};
		}

		const headers = { ...DEFAULT_RELAY_HEADERS, ...options.headers };
		// The upstream `Authorization` header is injected natively, so the
		// site credential never travels over loopback. The relay's own
		// per-session token rides in `Relay-Authorization` because `fetch()`
		// silently strips `Proxy-*` headers.
		delete headers.Authorization;
		headers[ 'Relay-Authorization' ] = `Bearer ${ networkProxy.token }`;

		// `data` is api-fetch's shorthand for a JSON body, serialized by the
		// handler rather than by a middleware. Missing it meant every relayed
		// write sent `Content-Length: 0`, which WordPress accepts as a no-op:
		// silent data loss on every save.
		let { body } = options;
		if ( data ) {
			body = JSON.stringify( data );
			headers[ 'Content-Type' ] = 'application/json';
		}

		let response;
		try {
			// Only the fields the transport needs, rather than spreading the
			// remaining options: api-fetch defaults `credentials` to
			// `include`, which a browser refuses against the relay's
			// `Access-Control-Allow-Origin: *`.
			response = await globalThis.fetch( relayRoot + upstreamPath, {
				method,
				headers,
				body,
				signal,
			} );
		} catch ( relayError ) {
			// Mirror `defaultFetchHandler`'s rejection handling, including
			// re-throwing an abort for the caller to handle itself.
			if ( relayError?.name === 'AbortError' ) {
				throw relayError;
			}
			logError( 'api-fetch: relayed request failed', relayError );
			if ( ! globalThis.navigator.onLine ) {
				throw {
					code: 'offline_error',
					message: __(
						'Unable to connect. Please check your Internet connection.'
					),
				};
			}
			throw {
				code: 'fetch_error',
				message: __(
					'Could not get a valid response from the server.'
				),
			};
		}

		return parseRelayResponse( response, parse );
	};
}

/**
 * The upstream path for a relayed request: the part of its target below the
 * site API root, without a leading slash.
 *
 * Returns `null` for a target the relay cannot serve — an absolute URL for
 * somewhere other than the site's API. Paginated requests arrive this way:
 * `fetchAllMiddleware` follows the absolute URL WordPress puts in the `Link`
 * header, so the relay has to recognize the site's own API root in it.
 *
 * **Host aliases are tolerated; path differences are not.** WordPress builds
 * `Link` headers and `_links` hrefs from `home_url()`, which need not be the
 * host the app was configured with — `www.` versus bare, a mapped or
 * reverse-proxied domain, an `http` `siteurl` behind `https`. wp-env is the
 * everyday case: its credentials report `localhost` while WordPress reports
 * `127.0.0.1`. Those are the same resource under another name, so the target is
 * moved onto the root's origin before comparing. A *path* difference is a
 * different resource: in a subdirectory multisite `https://site/a/wp-json/` and
 * `https://site/b/wp-json/` are separate sites, and matching across them would
 * route one site's request into the other's API root.
 *
 * @param {string} target  The request's `url`, or its `path` when no root URL
 *                         middleware has run.
 * @param {URL}    apiRoot The site's REST API root, normalized and
 *                         slash-terminated.
 * @return {string|null} The upstream path, or `null` when it cannot be relayed.
 */
function relayUpstreamPath( target, apiRoot ) {
	let url;
	try {
		url = new URL( target );
	} catch {
		// Not an absolute URL, so it is a path relative to the API root.
		return target.replace( /^\/+/, '' );
	}

	// Assign the origin's parts separately: the `host` setter leaves an
	// existing port in place when the value carries none, so `host` alone turns
	// `http://127.0.0.1:8888/…` into `https://example.com:8888/…`.
	url.protocol = apiRoot.protocol;
	url.hostname = apiRoot.hostname;
	url.port = apiRoot.port;

	if ( ! url.href.startsWith( apiRoot.href ) ) {
		return null;
	}
	return url.href.slice( apiRoot.href.length );
}

/**
 * Parses a relayed response the way api-fetch's own handler does: unparsed
 * requests get the raw `Response`, 204s resolve to `null`, and error statuses
 * throw the decoded JSON body.
 *
 * @param {Response} response    The relay response.
 * @param {boolean}  shouldParse Whether the caller requested parsing.
 * @return {Promise<any>} The parsed body or the raw response.
 */
async function parseRelayResponse( response, shouldParse ) {
	if ( ! response.ok ) {
		if ( ! shouldParse ) {
			throw response;
		}
		throw await parseRelayJSON( response );
	}

	if ( ! shouldParse ) {
		return response;
	}

	if ( response.status === 204 ) {
		return null;
	}

	return parseRelayJSON( response );
}

/**
 * Decodes a relayed response body, normalizing a decode failure into the same
 * error api-fetch raises. The relay reports its own failures as WordPress-shaped
 * `{ code, message }` JSON, so a real error reaches the caller intact rather
 * than as an opaque parse failure.
 *
 * @param {Response} response The relay response.
 * @return {Promise<any>} The decoded body.
 */
async function parseRelayJSON( response ) {
	try {
		return await response.json();
	} catch {
		throw {
			code: 'invalid_json',
			message: __( 'The response is not a valid JSON response.' ),
		};
	}
}

/**
 * Middleware setting the CORS mode and remove a specific header causing CORS errors.
 *
 * @type {APIFetchMiddleware}
 *
 * @todo Address the CORS header hack.
 */
function corsMiddleware( options, next ) {
	options.mode = 'cors';

	// HACK: This custom header causes CORS errors. Although settings the mode to
	// 'cors' should prevent this header, incorrect middleware order results in
	// setting the header.
	// https://github.com/Automattic/jetpack/blob/7801b7f21e01d8a4a102c44dac69c6ebdd1e549d/projects/plugins/jetpack/extensions/editor.js#L22-L52
	if ( options.headers ) {
		delete options.headers[ 'x-wp-api-fetch-from-editor' ];
	}

	return next( options );
}

/**
 * Middleware modifying the API path by inserting the site API namespace.
 *
 * @type {APIFetchMiddleware}
 */
function apiPathModifierMiddleware( options, next ) {
	const { siteApiNamespace, namespaceExcludedPaths } = getGBKit();
	const namespaceRegex = new RegExp( `(${ siteApiNamespace.join( '|' ) })` );
	const isEligiblePath =
		options.path &&
		! namespaceExcludedPaths.some( ( path ) =>
			options.path.startsWith( path )
		);

	const alreadyHasSiteNamespace =
		namespaceRegex.test( options.path ) ||
		/\/sites\/[^/]+\//.test( options.path );

	if ( isEligiblePath && ! alreadyHasSiteNamespace ) {
		// Insert the API namespace after the first two path segments.
		options.path = options.path.replace(
			/^(?<apiPath>\/?(?:[\w.-]+\/){2})/,
			`$<apiPath>${ siteApiNamespace[ 0 ] }`
		);
	}

	return next( options );
}

/**
 * Middleware that handles token-based authentication.
 *
 * When an auth header is present, this middleware:
 * 1. Adds the Authorization header to the request
 * 2. Sets credentials to 'omit' to prevent cookies from interfering with token authentication
 *
 * This prevents authentication conflicts where browser cookies could disrupt
 * token-based authentication by being sent alongside the Authorization header.
 *
 * @type {APIFetchMiddleware}
 */
function tokenAuthMiddleware( options, next ) {
	const { authHeader } = getGBKit();
	options.headers = options.headers || {};

	if ( authHeader ) {
		options.headers.Authorization = authHeader;
		options.credentials = 'omit'; // Avoid cookies disrupting token authentication
	}

	return next( options );
}

/**
 * Middleware to filter out requests to specific endpoints.
 *
 * @type {APIFetchMiddleware}
 *
 * @todo Properly seed the post entity and remove this middleware.
 *
 * This was added to prevent re-fetching entity content provided by the native
 * host app, which can lead to content loss. However, we can likely avoid the
 * need for this middleware by ensuring we properly seed the entity content into
 * the store on initialization.
 *
 * This requires hoisting the relevant logic from `useEditorSetup` to occur
 * before we render the editor, and invoking `finishResolution`.
 *
 * See: https://github.com/wordpress-mobile/GutenbergKit/commit/c9b4fc9978a3760ba97f3f5d4359c2bc2155bb80
 */
function filterEndpointsMiddleware( options, next ) {
	const { post } = getGBKit();

	if ( ! post || post.id === undefined ) {
		return next( options );
	}

	// Apply the same fallback contract as `getPost()` so the filter still
	// engages on hosts whose payload omits restBase/restNamespace.
	const restNamespace = post.restNamespace || POST_FALLBACKS.restNamespace;
	const restBase = post.restBase || POST_FALLBACKS.restBase;
	const disabledPath = `/${ restNamespace }/${ restBase }/${ post.id }`;

	if (
		options.path === disabledPath ||
		options.path?.startsWith( `${ disabledPath }?` )
	) {
		return Promise.resolve( [] );
	}
	return next( options );
}

/**
 * Middleware that routes media uploads through the native host's local HTTP
 * server for processing (e.g. image resizing) before uploading to WordPress.
 *
 * Exported for testing only.
 *
 * When `nativeUploadPort` is configured in GBKit, this middleware intercepts
 * `POST /wp/v2/media` requests, forwards the file to the native server, and
 * returns the response in WordPress REST API attachment format so the existing
 * Gutenberg upload pipeline (blob previews, save locking, entity caching)
 * works unchanged.
 *
 * When the native server is not configured, requests pass through unmodified.
 *
 * Note: Ideally, media uploads would be handled via the `mediaUpload` editor
 * setting (see the Gutenberg Framework guides), but GutenbergKit uses
 * Gutenberg's `EditorProvider` which overwrites that setting internally:
 * https://github.com/WordPress/gutenberg/blob/29914e1d09a344edce58d938fa4992e1ec248e41/packages/editor/src/components/provider/use-block-editor-settings.js#L340
 *
 * Until GutenbergKit is refactored to use `BlockEditorProvider` and aligns
 * with the Gutenberg Framework guides (https://wordpress.org/gutenberg-framework/docs/intro/),
 * this api-fetch middleware approach is necessary. For context, see:
 * - https://github.com/wordpress-mobile/GutenbergKit/pull/24
 * - https://github.com/wordpress-mobile/GutenbergKit/pull/50
 * - https://github.com/wordpress-mobile/GutenbergKit/pull/108
 *
 * @type {APIFetchMiddleware}
 */
export function nativeMediaUploadMiddleware( options, next ) {
	const { nativeUploadPort, nativeUploadToken } = getGBKit();

	if (
		! nativeUploadPort ||
		! nativeUploadToken ||
		! options.method ||
		options.method.toUpperCase() !== 'POST' ||
		! options.path ||
		! MEDIA_UPLOAD_PATH.test( options.path ) ||
		! ( options.body instanceof FormData )
	) {
		return next( options );
	}

	// Only intercept a genuine file upload. `FormData.get('file')` returns a
	// `File`, a string (a non-file field that happens to be named `file`), or
	// `null` (no such field). The `instanceof File` check covers all the
	// non-file cases at once — a missing field and a wrong-typed value both fall
	// through to the default path — and guarantees `file.name` below is safe.
	const file = options.body.get( 'file' );
	if ( ! ( file instanceof File ) ) {
		return next( options );
	}

	info(
		`Routing upload of ${ file.name } through native server on port ${ nativeUploadPort }`
	);

	// Forward the original request body — the file plus every sibling field
	// (`post`, additionalData) — and the original query string (e.g. `?_embed`)
	// so the native server can relay them to WordPress unchanged. Rebuilding the
	// body with only `file` would drop the post association and additionalData.
	const query = requestQuery( options.path );

	// Use the two-argument form of `.then()` so the rejection handler catches
	// *only* a connection-level failure of the `fetch()` itself — not errors
	// thrown while handling a response (those must surface as real failures).
	return fetch( `http://localhost:${ nativeUploadPort }/upload${ query }`, {
		method: 'POST',
		headers: {
			'Relay-Authorization': `Bearer ${ nativeUploadToken }`,
		},
		body: options.body,
		signal: options.signal,
	} ).then(
		( response ) => {
			// The native server relays WordPress's response verbatim. On a
			// non-2xx, mirror @wordpress/api-fetch: reject with the parsed WP
			// error body ({ code, message, data }) so @wordpress/media-utils
			// surfaces WordPress's real message. On success, return WordPress's
			// attachment object unchanged so every consumer behaves exactly as
			// it would for a non-native upload.
			if ( ! response.ok ) {
				return response
					.json()
					.catch( () => {
						// An abort during the body read rejects json() too; surface
						// the cancellation, not an "invalid response" error.
						if ( options.signal?.aborted ) {
							throw uploadAbortError( options.signal );
						}
						return invalidUploadResponseError();
					} )
					.then( ( body ) => {
						logError( 'Native upload failed', body );
						// Throw the parsed body verbatim, even if it isn't the usual
						// WordPress `{ code, message, data }` shape. This is
						// deliberate: it mirrors `@wordpress/api-fetch`'s
						// `parseAndThrowError`, so a native-relayed error reaches
						// consumers identically to a direct upload's. We intentionally
						// don't reshape or second-guess a non-standard error body.
						throw body;
					} );
			}
			// A 2xx with a non-JSON body (e.g. an HTML error page injected by an
			// intermediary) rejects json(); normalize it the same way as the
			// non-ok path rather than surfacing a raw SyntaxError.
			return response.json().catch( () => {
				// An abort during the body read rejects json(); surface the
				// cancellation rather than an "invalid response" error notice.
				if ( options.signal?.aborted ) {
					throw uploadAbortError( options.signal );
				}
				const error = invalidUploadResponseError();
				logError( 'Native upload returned an invalid response', error );
				throw error;
			} );
		},
		( connectionError ) => {
			// A caller-initiated cancellation must propagate as the cancellation,
			// never be retried. Detect it via `signal.aborted` — the cancellation
			// *state* — rather than `connectionError.name === 'AbortError'`: the
			// state check also catches `AbortSignal.timeout()` (which rejects with
			// a TimeoutError, not an AbortError) and custom abort reasons, which a
			// name match would miss and wrongly fall back on. Rethrow the signal's
			// `reason` (the canonical abort error), not `connectionError`: if a
			// network failure and the abort race, `fetch` can reject with a network
			// TypeError even though the signal aborted, and rethrowing that would
			// make upstream treat a cancelled upload as a real failure — surfacing
			// a spurious error notice instead of a silent cancel.
			if ( options.signal?.aborted ) {
				throw uploadAbortError( options.signal );
			}
			// Otherwise the loopback upload server is unreachable at the transport
			// layer. We deliberately do NOT fall back to a direct re-upload:
			// reachability is gated proactively upstream — this middleware's guard
			// skips the native path when no port is advertised, and the native side
			// only advertises a port the WebView can actually reach (server running
			// + cleartext-to-localhost permitted, cleared on stop). So reaching here
			// means the server died out-of-band after a valid start; retrying a
			// non-idempotent POST /wp/v2/media could duplicate the attachment if the
			// native server had already relayed it to WordPress.
			logError(
				'Native upload failed at the transport layer',
				connectionError
			);
			// Normalize to the same `{ code, message }` shape
			// `@wordpress/api-fetch`'s default handler produces for a failed fetch,
			// so a native-upload transport failure surfaces to consumers (which key
			// off `error.code` and show `error.message`) exactly like a direct
			// upload's would — not as a raw, code-less TypeError with an
			// untranslated message. Same codes and strings as api-fetch, so the
			// existing translations apply.
			if ( ! globalThis.navigator.onLine ) {
				throw {
					code: 'offline_error',
					message: __(
						'Unable to connect. Please check your Internet connection.'
					),
				};
			}
			throw {
				code: 'fetch_error',
				message: __(
					'Could not get a valid response from the server.'
				),
			};
		}
	);
}

/**
 * The query component of a request path, including the leading `?`, or an empty
 * string when there is no query.
 *
 * Mirrors the `query` accessors on the native request types (`HttpRequest` on
 * Android, `ParsedHTTPRequest` on iOS): the split is on the first `?`, and a
 * bare trailing `?` carries no parameters so it yields an empty string. Keeping
 * the three in agreement means the value can be appended to an upstream URL
 * unconditionally, whichever side derived it.
 *
 * @param {string} path The request path, e.g. `/wp/v2/media?_embed`.
 * @return {string} The query, e.g. `?_embed`, or `''`.
 */
function requestQuery( path ) {
	const separator = path.indexOf( '?' );
	if ( separator === -1 ) {
		return '';
	}
	const value = path.slice( separator + 1 );
	return value ? `?${ value }` : '';
}

/**
 * The error rejected when the upload server's response body can't be parsed as
 * JSON. Shaped like a WordPress REST error so `@wordpress/media-utils` surfaces
 * it the same way as a real one, on both the non-2xx and 2xx paths.
 *
 * @return {{ code: string, message: string }} The normalized error.
 */
function invalidUploadResponseError() {
	return {
		code: 'invalid_json',
		message: 'The upload server returned an invalid response.',
	};
}

/**
 * The error to surface for a cancelled upload.
 *
 * Returns the signal's `reason` (the canonical abort error), falling back to a
 * canonical `AbortError` for engines that abort without populating `reason`.
 * Callers gate this behind `signal.aborted` (the cancellation *state*) rather
 * than an error's `name`, so a body-read rejection or a network error that
 * races the abort still surfaces as a silent cancel — not a spurious failure
 * notice.
 *
 * @param {AbortSignal} signal The aborted signal.
 * @return {Error} The error representing the cancellation.
 */
function uploadAbortError( signal ) {
	return (
		signal.reason ??
		new DOMException( 'The upload was aborted.', 'AbortError' )
	);
}

/**
 * Middleware to modify media upload requests.
 *
 * This middleware intercepts requests to the media endpoint and conditionally
 * removes the 'post' field if its value is '-1', which is used for draft posts.
 *
 * @type {APIFetchMiddleware}
 */
function mediaUploadMiddleware( options, next ) {
	if (
		options.path &&
		MEDIA_UPLOAD_PATH.test( options.path ) &&
		options.method === 'POST' &&
		options.body instanceof FormData &&
		options.body.get( 'post' ) === '-1'
	) {
		options.body.delete( 'post' );
	}

	return next( options );
}

/**
 * Remove the wrapping element from the oEmbed response, as it breaks
 * Gutenberg's sizing styles.
 *
 * @type {APIFetchMiddleware}
 *
 * @todo Hoist this host-specific logic to the host app.
 */
function transformOEmbedApiResponse( options, next ) {
	if ( options.path && options.path.indexOf( 'oembed' ) !== -1 ) {
		const url = getQueryArg( options.path, 'url' );
		const response = next( options, next );

		/**
		 * Creates an embed response emulating core's fallback link.
		 */
		function createFallbackResponse() {
			const link = document.createElement( 'a' );
			link.href = url;
			link.innerText = url;
			return {
				html: link.outerHTML,
				type: 'rich',
				provider_name: 'Embed',
			};
		}

		return new Promise( ( resolve ) => {
			response
				.then( ( data ) => {
					if ( data.html ) {
						/**
						 * Removes wrappers from YouTube, Vimeo, Dailymotion, TED block, e.g.
						 * <span class="embed-youtube">, <div class="embed-vimeo">, <div class="embed-dailymotion">, <div class="embed-ted">
						 * and return just the <iframe> child directly to allow wide & full width sizing.
						 */
						const doc =
							document.implementation.createHTMLDocument( '' );
						doc.body.innerHTML = data.html;
						const selectors = [
							'[class="embed-youtube"]',
							'[class="embed-vimeo"]',
							'[class="embed-dailymotion"]',
							'[class="embed-ted"]',
						].join( ',' );
						const wrapper = doc.querySelector( selectors );
						data.html = wrapper ? wrapper.innerHTML : data.html;
					}

					resolve( data );
				} )
				.catch( () => {
					resolve( createFallbackResponse() );
				} );
		} );
	}

	return next( options, next );
}

const defaultPreloadData = {
	'/wp/v2/types?context=view': {
		body: {
			post: {
				description: '',
				hierarchical: false,
				has_archive: false,
				name: 'Posts',
				slug: 'post',
				taxonomies: [ 'category', 'post_tag' ],
				rest_base: 'posts',
				rest_namespace: 'wp/v2',
				template: [],
				template_lock: false,
				_links: {},
			},
			page: {
				description: '',
				hierarchical: true,
				has_archive: false,
				name: 'Pages',
				slug: 'page',
				taxonomies: [],
				rest_base: 'pages',
				rest_namespace: 'wp/v2',
				template: [],
				template_lock: false,
				_links: {},
			},
		},
	},
	'/wp/v2/types/post?context=edit': {
		body: {
			name: 'Posts',
			slug: 'post',
			supports: {
				title: true,
				editor: true,
				author: true,
				thumbnail: true,
				excerpt: true,
				trackbacks: true,
				'custom-fields': true,
				comments: true,
				revisions: true,
				'post-formats': true,
				autosave: true,
			},
			taxonomies: [ 'category', 'post_tag' ],
			rest_base: 'posts',
			rest_namespace: 'wp/v2',
			template: [],
			template_lock: false,
		},
	},
};
