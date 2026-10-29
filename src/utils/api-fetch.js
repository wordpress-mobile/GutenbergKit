import apiFetch from '@wordpress/api-fetch';
import { __ } from '@wordpress/i18n';
import { isWithinAuthorizationScope } from './authorization-scope';
import { getGBKit, POST_FALLBACKS } from './bridge';
import { info, warn, error as logError } from './logger';
import { ensureTrailingSlash, stripTrailingSlash } from './url';

/**
 * @typedef {import('@wordpress/api-fetch').APIFetchMiddleware} APIFetchMiddleware
 * @typedef {import('@wordpress/api-fetch').FetchHandler} FetchHandler
 */

/** Matches `/wp/v2/media` but not sub-paths like `/wp/v2/media/123`. */
const MEDIA_UPLOAD_PATH = /^\/wp\/v2\/media(\?|$)/;

/** Matches `/wp/v2/media/<id>`, capturing the attachment ID. */
const MEDIA_ATTACHMENT_PATH = /^\/wp\/v2\/media\/(\d+)(\?|$)/;

/**
 * How much of a file each request to the native upload scheme carries.
 *
 * Large enough that a 1 GB video is a few hundred requests, small enough that the
 * page never holds more than one chunk's copy of a file in memory.
 */
export const NATIVE_UPLOAD_CHUNK_SIZE = 4 * 1024 * 1024;

/** Methods safe to repeat because they do not change server state. */
const RETRYABLE_METHODS = [ 'GET', 'HEAD', 'OPTIONS' ];

/** Base delay before each retry; jitter of up to the same amount is added. */
const RETRY_DELAYS_MS = [ 500, 2000 ];

/** Longest `Retry-After` delay worth waiting for; longer ones fail at once. */
const MAX_RETRY_AFTER_MS = 10_000;

/**
 * Initializes the API fetch configuration and middleware.
 *
 * @return {void}
 */
export function configureApiFetch() {
	const { siteApiRoot, preloadData = null } = getGBKit();

	// The root is joined to request paths by concatenation, so it has to supply
	// the separator. Hosts may configure it with or without the trailing slash,
	// as the native URL builders accept either.
	apiFetch.use(
		apiFetch.createRootURLMiddleware( ensureTrailingSlash( siteApiRoot ) )
	);
	apiFetch.use( corsMiddleware );
	apiFetch.use( apiPathModifierMiddleware );
	apiFetch.use( tokenAuthMiddleware );
	apiFetch.use( filterEndpointsMiddleware );
	// `apiFetch.use` unshifts, so the last registration runs first. Core's media
	// upload middleware is registered after the native one so that it runs
	// before it, wrapping it: the native middleware handles an upload without
	// calling `next`, so core's would never run at all from below. Both stay
	// above auth, namespacing, and the root URL, so the `post-process` requests
	// core issues through `next` are still authenticated and correctly
	// addressed.
	//
	// Recovery needs `x-wp-upload-attachment-id`, readable only same-origin or
	// when the server exposes it via CORS:
	//
	// - Through native code, which exposes it: the `gbk-upload:` scheme on iOS,
	//   the loopback server on Android. Every iOS upload with site credentials
	//   takes this path.
	// - Direct to WordPress, which does not expose it (see
	//   `rest_send_cors_headers()`): Android only. `GutenbergView` serves the
	//   editor from the site's origin, so this recovers when the REST API is
	//   on that origin too. It does not recover when the API is elsewhere, as
	//   with WP.com sites on `public-api.wordpress.com`.
	//
	// There is no fallback: core sends the header before
	// `wp_generate_attachment_metadata()`, so the fatal leaves no body to parse
	// the ID from.
	apiFetch.use( nativeMediaUploadMiddleware );
	apiFetch.use( mediaUploadMiddleware );
	apiFetch.use( stripDraftPostIdMiddleware );
	apiFetch.use( mediaPermissionsMiddleware );
	apiFetch.use( transformOEmbedApiResponse );
	apiFetch.use( siteIndexMiddleware );
	apiFetch.use(
		apiFetch.createPreloadingMiddleware( preloadData ?? defaultPreloadData )
	);
	apiFetch.setFetchHandler(
		withRateLimitRetry( apiFetch.defaultFetchHandler )
	);
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
	const isEligiblePath =
		options.path &&
		siteApiNamespace.length > 0 &&
		! namespaceExcludedPaths.some( ( path ) =>
			options.path.startsWith( path )
		);

	// Escape the namespaces so each is matched literally rather than as a
	// pattern.
	const alreadyHasSiteNamespace =
		new RegExp(
			`(${ siteApiNamespace.map( escapeRegExp ).join( '|' ) })`
		).test( options.path ) || /\/sites\/[^/]+\//.test( options.path );

	if ( isEligiblePath && ! alreadyHasSiteNamespace ) {
		// Insert the API namespace after the first two path segments, with a
		// single trailing slash.
		options.path = options.path.replace(
			/^(?<apiPath>\/?(?:[\w.-]+\/){2})/,
			`$<apiPath>${ ensureTrailingSlash( siteApiNamespace[ 0 ] ) }`
		);
	}

	return next( options );
}

/**
 * Escapes a string for literal use inside a regular expression.
 *
 * @param {string} value The string to escape.
 * @return {string} The escaped string.
 */
function escapeRegExp( value ) {
	return value.replace( /[.*+?^${}()|[\]\\]/g, '\\$&' );
}

/**
 * Middleware that handles token-based authentication.
 *
 * When an auth header is present, and the request is one the site's
 * credentials may go with, this middleware:
 * 1. Adds the Authorization header to the request
 * 2. Sets credentials to 'omit' to prevent cookies from interfering with token authentication
 *
 * This prevents authentication conflicts where browser cookies could disrupt
 * token-based authentication by being sent alongside the Authorization header.
 *
 * A request to anywhere but the site goes out without the header: the site's
 * credentials are not for another party's service.
 *
 * @type {APIFetchMiddleware}
 */
function tokenAuthMiddleware( options, next ) {
	const { authHeader } = getGBKit();
	options.headers = options.headers || {};

	if ( authHeader && isForSite( options ) ) {
		options.headers.Authorization = authHeader;
		options.credentials = 'omit'; // Avoid cookies disrupting token authentication
	}

	return next( options );
}

/**
 * Whether a request is one the site's credentials may go with.
 *
 * A request by `path` is for the site's API: the root URL middleware, which
 * runs later, joins the path to the API root and replaces any `url`. A request
 * by `url` alone can be for anywhere.
 *
 * @param {Object} options The api-fetch options.
 * @return {boolean} Whether the request may carry the site's credentials.
 */
function isForSite( options ) {
	if ( typeof options.path === 'string' ) {
		return true;
	}

	return isWithinAuthorizationScope( options.url, getGBKit() );
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
 * Middleware that routes media requests through native code: uploads for
 * processing (e.g. image resizing) before they reach WordPress, and attachment
 * deletions for the editor's orphan cleanup.
 *
 * Exported for testing only.
 *
 * Two transports, chosen by what the native host advertises in `GBKit`:
 *
 * - iOS: `nativeUploadScheme`. The file is sent in chunks to a URL scheme the
 *   editor's web view handles natively.
 * - Android: `nativeUploadPort` and `nativeUploadToken`. The request goes to a
 *   loopback HTTP server.
 *
 * With neither, requests pass through unmodified.
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
	const transport = nativeUploadTransport( getGBKit() );

	if ( ! transport ) {
		return next( options );
	}

	// Each helper returns `null` when the request is not its concern, so an
	// unhandled request falls through to the default path.
	return (
		nativeMediaDelete( options, transport, next ) ??
		nativeMediaUpload( options, transport ) ??
		next( options )
	);
}

/**
 * @typedef {Object} NativeUploadTransport
 * @property {?string} schemeBase The base URL of the native upload scheme (iOS).
 * @property {?number} port       The loopback upload server's port (Android).
 * @property {?string} token      The loopback upload server's token (Android).
 */

/**
 * The transport the native host advertises, or `null` when it advertises none.
 *
 * Read on every request, so a change the host makes to `GBKit` takes effect on
 * the next upload.
 *
 * @param {Object} gbkit The `GBKit` configuration.
 * @return {?NativeUploadTransport} The transport.
 */
function nativeUploadTransport( gbkit ) {
	const { nativeUploadScheme, nativeUploadPort, nativeUploadToken } = gbkit;
	if ( nativeUploadScheme ) {
		return { schemeBase: `${ nativeUploadScheme }://upload` };
	}
	if ( nativeUploadPort && nativeUploadToken ) {
		return { port: nativeUploadPort, token: nativeUploadToken };
	}
	return null;
}

/**
 * Routes a media upload through native code.
 *
 * Returns `null` when the request is not a media upload, so the caller falls
 * through to its normal handling.
 *
 * Intercepts `POST /wp/v2/media`, hands the file to native code, and returns
 * WordPress's response so the existing Gutenberg upload pipeline (blob previews,
 * save locking, entity caching, `post-process` recovery) works unchanged.
 *
 * @param {Object}                options   The api-fetch options.
 * @param {NativeUploadTransport} transport How to reach native code.
 * @return {?Promise} The relayed upload, or `null` if not applicable.
 */
function nativeMediaUpload( options, transport ) {
	if (
		! options.method ||
		options.method.toUpperCase() !== 'POST' ||
		! options.path ||
		! MEDIA_UPLOAD_PATH.test( options.path ) ||
		! ( options.body instanceof FormData )
	) {
		return null;
	}

	// Only intercept a genuine file upload. `FormData.get('file')` returns a
	// `File`, a string (a non-file field that happens to be named `file`), or
	// `null` (no such field). The `instanceof File` check covers all the
	// non-file cases at once — a missing field and a wrong-typed value both fall
	// through to the default path — and guarantees `file.name` below is safe.
	const file = options.body.get( 'file' );
	if ( ! ( file instanceof File ) ) {
		return null;
	}

	// Native code relays the upload with the original query string (e.g.
	// `?_embed`) and every sibling field (`post`, additionalData) — dropping
	// either would break the post association or the response's shape.
	const query = requestQuery( options.path );

	const upload = transport.schemeBase
		? schemeUpload( options, file, query, transport.schemeBase )
		: loopbackUpload( options, file, query, transport );

	// Use the two-argument form of `.then()` so the rejection handler catches
	// *only* a failure to reach native code — not errors thrown while handling
	// a response (those must surface as real failures).
	return upload.then( relayUploadResponse, ( connectionError ) =>
		rejectUnreachableUpload( connectionError, options )
	);
}

/**
 * Sends an upload to Android's loopback upload server, as one `multipart`
 * request carrying the original `FormData`.
 *
 * @param {Object}                options   The api-fetch options.
 * @param {File}                  file      The file being uploaded.
 * @param {string}                query     The request's query string.
 * @param {NativeUploadTransport} transport The loopback server's port and token.
 * @return {Promise<Response>} The server's response.
 */
function loopbackUpload( options, file, query, { port, token } ) {
	info(
		`Routing upload of ${ file.name } through native server on port ${ port }`
	);
	return fetch( `http://localhost:${ port }/upload${ query }`, {
		method: 'POST',
		headers: {
			'Relay-Authorization': `Bearer ${ token }`,
		},
		body: options.body,
		signal: options.signal,
	} );
}

/**
 * Sends an upload to iOS's native upload scheme.
 *
 * The file goes in chunks, each an `ArrayBuffer`: WebKit hands a URL scheme
 * handler only bodies it has buffered, and drops a `Blob` body — including a
 * `FormData` that holds one — without an error. The table of what was measured
 * is in `docs/code/media-uploads.md`. Chunking also keeps at most one chunk of
 * the file in the page's memory at a time.
 *
 * When native code refuses the upload — the file is too large, staging it
 * failed, or `stopMediaHandling()` has run — that refusal is the upload's error.
 * Nothing falls back to the web view's own path: on iOS that goes through the
 * REST relay, which holds the whole file in memory, enough to get the web view
 * killed over a large video.
 *
 * @param {Object} options    The api-fetch options.
 * @param {File}   file       The file being uploaded.
 * @param {string} query      The request's query string.
 * @param {string} schemeBase The native upload scheme's base URL.
 * @return {Promise<Response>} WordPress's response, or native code's refusal.
 */
async function schemeUpload( options, file, query, schemeBase ) {
	const { signal } = options;

	info( `Routing upload of ${ file.name } through the native upload scheme` );

	let sessionId = null;
	try {
		sessionId = await beginNativeUpload( schemeBase, file, signal );
		for (
			let offset = 0;
			offset < file.size;
			offset += NATIVE_UPLOAD_CHUNK_SIZE
		) {
			const chunk = await file
				.slice( offset, offset + NATIVE_UPLOAD_CHUNK_SIZE )
				.arrayBuffer();
			await expectOk(
				fetch(
					`${ schemeBase }/sessions/${ sessionId }/chunks?offset=${ offset }`,
					{ method: 'POST', body: chunk, signal }
				)
			);
		}
	} catch ( sendError ) {
		if ( sessionId ) {
			cancelNativeUpload( schemeBase, sessionId );
		}
		if ( sendError instanceof Response && ! signal?.aborted ) {
			return sendError;
		}
		throw sendError;
	}

	return finishNativeUpload(
		schemeBase,
		sessionId,
		uploadFields( options.body ),
		query,
		signal
	);
}

/**
 * Starts a native upload session for `file` and returns its ID.
 *
 * @param {string}       schemeBase The native upload scheme's base URL.
 * @param {File}         file       The file to upload.
 * @param {?AbortSignal} signal     Cancels the request.
 * @return {Promise<string>} The session ID.
 */
async function beginNativeUpload( schemeBase, file, signal ) {
	const response = await expectOk(
		fetch( `${ schemeBase }/sessions`, {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify( {
				filename: file.name,
				mimeType: file.type || 'application/octet-stream',
				size: file.size,
			} ),
			signal,
		} )
	);
	const { id } = await response.json();
	return id;
}

/**
 * Asks native code to upload a session's file to WordPress, and returns
 * WordPress's response.
 *
 * @param {string}       schemeBase The native upload scheme's base URL.
 * @param {string}       sessionId  The session to finish.
 * @param {Array}        fields     The upload's form fields.
 * @param {string}       query      The request's query string.
 * @param {?AbortSignal} signal     Cancels the upload.
 * @return {Promise<Response>} WordPress's response, relayed.
 */
function finishNativeUpload( schemeBase, sessionId, fields, query, signal ) {
	return fetch( `${ schemeBase }/sessions/${ sessionId }/finish`, {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify( { fields, query } ),
		signal,
	} );
}

/**
 * Abandons a native upload session, best effort: native code also sweeps idle
 * sessions, so a cancel that doesn't arrive only delays the cleanup.
 *
 * @param {string} schemeBase The native upload scheme's base URL.
 * @param {string} sessionId  The session to abandon.
 */
function cancelNativeUpload( schemeBase, sessionId ) {
	fetch( `${ schemeBase }/sessions/${ sessionId }/cancel`, {
		method: 'POST',
	} ).catch( () => {} );
}

/**
 * Resolves with the response when it is a 2xx, and rejects with it otherwise.
 *
 * @param {Promise<Response>} request The request.
 * @return {Promise<Response>} The successful response.
 */
async function expectOk( request ) {
	const response = await request;
	if ( ! response.ok ) {
		throw response;
	}
	return response;
}

/**
 * The upload's text fields — everything in the `FormData` except the file — in
 * order, as `{ name, value }` pairs, so repeated names (e.g. `field[]`) survive.
 *
 * @param {FormData} formData The upload's body.
 * @return {Array<{name: string, value: string}>} The fields.
 */
function uploadFields( formData ) {
	const fields = [];
	for ( const [ name, value ] of formData.entries() ) {
		if ( typeof value === 'string' ) {
			fields.push( { name, value } );
		}
	}
	return fields;
}

/**
 * Hands native code's relay of WordPress's response to core's media upload
 * middleware, which runs above this one.
 *
 * Core always asks for the raw `Response` (`parse: false`) so it can read
 * `x-wp-upload-attachment-id` off a failed upload and retry `post-process`. It
 * parses the response itself, so this only rejects on a non-2xx. That rejection
 * is not logged: core may still recover the upload.
 *
 * @param {Response} response WordPress's response, relayed.
 * @return {Promise<Response>|Response} The response.
 */
function relayUploadResponse( response ) {
	return response.ok ? response : Promise.reject( response );
}

/**
 * Rejects an upload that could not reach native code, or whose relay failed.
 *
 * @param {unknown} connectionError What the request rejected with.
 * @param {Object}  options         The api-fetch options.
 * @return {never} Always throws.
 */
function rejectUnreachableUpload( connectionError, options ) {
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
	// Otherwise native code could not be reached, or dropped the request,
	// once it may already have sent the file to WordPress. We deliberately do
	// NOT fall back to a direct re-upload: retrying a non-idempotent
	// POST /wp/v2/media could duplicate the attachment.
	logError( 'Native upload failed at the transport layer', connectionError );
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
		message: __( 'Could not get a valid response from the server.' ),
	};
}

/**
 * Routes a media attachment deletion through native code.
 *
 * Returns `null` when the request is not a media deletion, so the caller falls
 * through to its normal handling.
 *
 * Core's media upload middleware deletes the orphaned attachment when every
 * `post-process` retry fails. That request cannot be made directly from a
 * cross-origin editor: `@wordpress/api-fetch` tunnels `DELETE` as a `POST`
 * carrying `X-HTTP-Method-Override`, and core's `rest_allowed_cors_headers`
 * does not list that header, so the browser blocks it at preflight and the
 * orphan survives. Relaying through native code — which sets its own CORS
 * policy — is what lets the cleanup complete.
 *
 * This runs before `X-HTTP-Method-Override` exists: api-fetch's `httpV1`
 * middleware adds it further down the chain, so the method here is still a
 * plain `DELETE`.
 *
 * Once `stopMediaHandling()` has run, the upload scheme refuses every request
 * with a `503`. A deletion then goes down the chain instead, to the REST relay,
 * which sends it natively too: retrying is safe, since deleting an attachment
 * twice deletes it once.
 *
 * @param {Object}                                options   The api-fetch options.
 * @param {NativeUploadTransport}                 transport How to reach native code.
 * @param {(options: Object) => Promise<unknown>} next      The next middleware, for a refused deletion.
 * @return {?Promise} The relayed deletion, or `null` if not applicable.
 */
function nativeMediaDelete( options, transport, next ) {
	if ( options.method?.toUpperCase() !== 'DELETE' || ! options.path ) {
		return null;
	}

	const match = MEDIA_ATTACHMENT_PATH.exec( options.path );
	if ( ! match ) {
		return null;
	}

	const attachmentId = match[ 1 ];
	const query = requestQuery( options.path );

	info(
		`Routing deletion of attachment ${ attachmentId } through native code`
	);

	const request = transport.schemeBase
		? fetch( `${ transport.schemeBase }/media/${ attachmentId }/delete`, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify( { query } ),
				signal: options.signal,
		  } )
		: fetch(
				`http://localhost:${ transport.port }/media/${ attachmentId }${ query }`,
				{
					method: 'DELETE',
					headers: {
						'Relay-Authorization': `Bearer ${ transport.token }`,
					},
					signal: options.signal,
				}
		  );

	return request.then(
		( response ) => {
			if ( transport.schemeBase && response.status === 503 ) {
				return next( options );
			}

			if ( options.parse === false ) {
				if ( ! response.ok ) {
					return Promise.reject( response );
				}
				return response;
			}

			if ( ! response.ok ) {
				return response
					.json()
					.catch( () =>
						invalidUploadResponseError( response.status )
					)
					.then( ( body ) => {
						logError( 'Native media deletion failed', body );
						throw withResponseStatus( body, response.status );
					} );
			}

			return response.json().catch( () => {
				const error = invalidUploadResponseError( response.status );
				logError(
					'Native media deletion returned an invalid response',
					error
				);
				throw error;
			} );
		},
		( connectionError ) => {
			if ( options.signal?.aborted ) {
				throw uploadAbortError( options.signal );
			}
			logError(
				'Native media deletion failed at the transport layer',
				connectionError
			);
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
 * Mirrors Android's `HttpRequest.query`: the split is on the first `?`, and a
 * bare trailing `?` carries no parameters so it yields an empty string. Native
 * code appends the value to the WordPress URL unconditionally.
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
 * @param {number} status The response's HTTP status.
 * @return {{ code: string, message: string, data: { status: number } }} The normalized error.
 */
function invalidUploadResponseError( status ) {
	return {
		code: 'invalid_json',
		message: 'The upload server returned an invalid response.',
		data: { status },
	};
}

/**
 * Adds the response's status to an error body that has no `data`, as
 * `@wordpress/api-fetch`'s `parseAndThrowError` does. Any other body is
 * returned unchanged.
 *
 * @param {unknown} body   The parsed error body.
 * @param {number}  status The response's HTTP status.
 * @return {unknown} The error to reject with.
 */
function withResponseStatus( body, status ) {
	if (
		body &&
		typeof body === 'object' &&
		! Array.isArray( body ) &&
		body.data === undefined
	) {
		return { ...body, data: { status } };
	}
	return body;
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
 * Core's media upload middleware, with its orphan cleanup's failure handled.
 *
 * When every `post-process` retry fails, core deletes the attachment and never
 * reads the result. A failed delete would otherwise be an unhandled rejection,
 * which reaches the host as an exception with no useful message. Every
 * `DELETE` that reaches this `next` is that cleanup: core makes no other.
 *
 * The method is uppercased first. Core only recognizes an upload sent as
 * `POST`, and the native middleware below it relies on core to parse the
 * response, so an upload sent as `post` would otherwise reach the caller as a
 * raw `Response`. `fetch` uppercases the standard methods anyway.
 *
 * @type {APIFetchMiddleware}
 */
function mediaUploadMiddleware( options, next ) {
	const normalized = options.method
		? { ...options, method: options.method.toUpperCase() }
		: options;
	return apiFetch.mediaUploadMiddleware( normalized, ( request ) => {
		const response = next( request );
		if ( request.method === 'DELETE' ) {
			response.catch( ( cleanupError ) =>
				logError(
					'Could not delete the unfinished upload',
					cleanupError
				)
			);
		}
		return response;
	} );
}

/**
 * Middleware that strips the placeholder post ID from media upload requests.
 *
 * This middleware intercepts requests to the media endpoint and conditionally
 * removes the 'post' field if its value is '-1', which is used for draft posts.
 *
 * @type {APIFetchMiddleware}
 */
function stripDraftPostIdMiddleware( options, next ) {
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
 * Middleware restoring the `Allow` header on the media permissions check.
 *
 * Browsers hide `Allow` from cross-origin responses, so `canUser` would report
 * uploads as denied and the editor would remove its Upload buttons. WordPress
 * always allows `GET` on this collection, so a missing header was hidden rather
 * than omitted, and the user is assumed able to upload.
 *
 * @type {APIFetchMiddleware}
 */
function mediaPermissionsMiddleware( options, next ) {
	if (
		options.parse !== false ||
		options.method?.toUpperCase() !== 'OPTIONS' ||
		! options.path ||
		! MEDIA_UPLOAD_PATH.test( options.path )
	) {
		return next( options );
	}

	return next( options ).then( ( response ) => {
		if ( response.headers.has( 'allow' ) ) {
			return response;
		}

		const headers = new Headers( response.headers );
		headers.set( 'Allow', 'GET, POST' );
		return new Response( response.body, {
			status: response.status,
			statusText: response.statusText,
			headers,
		} );
	} );
}

/**
 * Remove the wrapping element from the oEmbed response, as it breaks
 * Gutenberg's sizing styles.
 *
 * A failed request is left to reject, so core stores `false` and blocks that
 * poll for a preview (e.g. VideoPress while processing an upload) ask again.
 *
 * @type {APIFetchMiddleware}
 *
 * @todo Hoist this host-specific logic to the host app.
 */
function transformOEmbedApiResponse( options, next ) {
	if ( options.path && options.path.indexOf( 'oembed' ) !== -1 ) {
		return next( options, next ).then( ( data ) => {
			if ( data?.html ) {
				/**
				 * Removes wrappers from YouTube, Vimeo, Dailymotion, TED block, e.g.
				 * <span class="embed-youtube">, <div class="embed-vimeo">, <div class="embed-dailymotion">, <div class="embed-ted">
				 * and return just the <iframe> child directly to allow wide & full width sizing.
				 */
				const doc = document.implementation.createHTMLDocument( '' );
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

			return data;
		} );
	}

	return next( options, next );
}

/**
 * Middleware resolving the REST API index locally on namespaced sites.
 *
 * Gutenberg's `root`/`__unstableBase` entity fetches the REST API index (`/`)
 * during editor initialization. On a namespaced site that path has no segments
 * for `apiPathModifierMiddleware` to insert the namespace into, so the request
 * targets the API host's root, which serves no index. Rather than let the
 * request fail, resolve the entity with `home` from the host's site URL. The
 * host supplies a single URL, so `url`, the WordPress address, has no accurate
 * source and is left unset.
 *
 * Consumers tolerate the remaining fields being absent: the site blocks read
 * the `site` entity when the user can edit settings, and client-side media
 * processing treats missing image sizes as none.
 *
 * Runs after the preloading middleware so a host-supplied index entry takes
 * precedence. `apiFetch.use()` prepends, so this is registered immediately
 * before it.
 *
 * @type {APIFetchMiddleware}
 */
function siteIndexMiddleware( options, next ) {
	const { siteApiNamespace = [], siteURL } = getGBKit();
	const isNamespacedSite = siteApiNamespace.length > 0;
	const isGet = ! options.method || options.method.toUpperCase() === 'GET';

	if ( ! isNamespacedSite || ! isGet || ! isRestIndexPath( options.path ) ) {
		return next( options );
	}

	const home = stripTrailingSlash( siteURL );
	return Promise.resolve( home ? { home } : {} );
}

/**
 * Whether a request path targets the REST API index.
 *
 * @param {string} [path] The request path, e.g. `/?_fields=name`.
 * @return {boolean} True for `/` with or without a query string.
 */
function isRestIndexPath( path ) {
	if ( typeof path !== 'string' ) {
		return false;
	}
	const pathname = path.split( '?' )[ 0 ];
	return pathname === '' || pathname === '/';
}

/**
 * Wraps a fetch handler to retry read-only requests the site rate-limits.
 *
 * core-data caches some failed resolutions for the session, so one throttled
 * request in the editor's load burst can break a block until reload. As a
 * fetch handler, it also retries each page `fetchAllMiddleware` requests.
 *
 * Exported for testing only.
 *
 * @param {FetchHandler} fetchHandler The handler performing the request.
 * @return {FetchHandler} The handler with retries.
 */
export function withRateLimitRetry( fetchHandler ) {
	return async ( options ) => {
		const method = ( options.method ?? 'GET' ).toUpperCase();
		if ( ! RETRYABLE_METHODS.includes( method ) ) {
			return fetchHandler( options );
		}

		for ( let attempt = 0; ; attempt++ ) {
			let response;
			let isOk = true;
			try {
				response = await fetchHandler( { ...options, parse: false } );
			} catch ( err ) {
				// Network, offline, and abort errors have no response.
				if ( typeof err?.status !== 'number' ) {
					throw err;
				}
				response = err;
				isOk = false;
			}

			if ( response.status === 429 && ! options.signal?.aborted ) {
				const request = `${ method } ${ options.url ?? options.path }`;
				if ( attempt < RETRY_DELAYS_MS.length ) {
					const delay = getRetryDelay( response, attempt );
					// A retry sent before a longer `Retry-After` elapses would fail too.
					if ( delay <= MAX_RETRY_AFTER_MS ) {
						info( `Retrying ${ request } after a 429 response` );
						await wait( delay, options.signal );
						continue;
					}
				}
				// core-data may cache this failure for the session.
				warn( `Giving up on ${ request } after a 429 response`, {
					retries: attempt,
				} );
			}

			if ( options.parse === false ) {
				if ( ! isOk ) {
					throw response;
				}
				return response;
			}
			return parseResponse( response, isOk );
		}
	};
}

/**
 * Returns how long to wait before retrying a rate-limited request.
 *
 * @param {Response} response The 429 response.
 * @param {number}   attempt  Zero-based index of the retry about to happen.
 * @return {number} Delay in milliseconds.
 */
function getRetryDelay( response, attempt ) {
	const retryAfter = response.headers?.get?.( 'retry-after' );
	if ( retryAfter ) {
		const seconds = Number( retryAfter );
		const delay = Number.isNaN( seconds )
			? Date.parse( retryAfter ) - Date.now()
			: seconds * 1000;
		if ( ! Number.isNaN( delay ) ) {
			return Math.max( delay, 0 );
		}
	}

	// Jitter spreads out requests that were throttled in the same burst.
	const delay = RETRY_DELAYS_MS[ attempt ];
	return delay + Math.random() * delay;
}

/**
 * Resolves after the given delay, or rejects as `fetch` would once aborted.
 *
 * @param {number}      ms       Delay in milliseconds.
 * @param {AbortSignal} [signal] Signal of the request being retried.
 * @return {Promise<void>} Resolves once the delay has elapsed.
 */
function wait( ms, signal ) {
	return new Promise( ( resolve, reject ) => {
		const onAbort = () => {
			clearTimeout( timer );
			reject( signal.reason );
		};
		const timer = setTimeout( () => {
			signal?.removeEventListener( 'abort', onAbort );
			resolve();
		}, ms );
		signal?.addEventListener( 'abort', onAbort, { once: true } );
	} );
}

/**
 * Parses a response the way api-fetch's default handler does, which does not
 * expose its parsing.
 *
 * @param {Response} response The response.
 * @param {boolean}  isOk     Whether the handler accepted the response.
 * @return {Promise<unknown>} The parsed body; rejects with it for an error response.
 */
async function parseResponse( response, isOk ) {
	if ( isOk && response.status === 204 ) {
		return null;
	}

	let body;
	try {
		if ( typeof response.text !== 'function' ) {
			body = await response.json();
		} else {
			const text = await response.text();
			body = isOk && text === '' ? null : JSON.parse( text );
		}
	} catch {
		throw {
			code: 'invalid_json',
			message: __( 'The response is not a valid JSON response.' ),
			data: { status: response.status },
		};
	}

	if ( ! isOk ) {
		throw withResponseStatus( body, response.status );
	}
	return body;
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
