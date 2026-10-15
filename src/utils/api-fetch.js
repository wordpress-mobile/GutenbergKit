import apiFetch from '@wordpress/api-fetch';
import { getQueryArg } from '@wordpress/url';
import { __ } from '@wordpress/i18n';
import { getGBKit, POST_FALLBACKS } from './bridge';
import { info, warn, error as logError } from './logger';
import { ensureTrailingSlash, stripTrailingSlash } from './url';

/**
 * @typedef {import('@wordpress/api-fetch').APIFetchMiddleware} APIFetchMiddleware
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
	// - Through the native upload server, which exposes it: works on both
	//   platforms. This is the only path that recovers everywhere.
	// - Direct to WordPress, which does not expose it (see
	//   `rest_send_cors_headers()`): never recovers on iOS, which loads from
	//   `file://`. On Android it recovers only when the editor is genuinely
	//   same-origin — `GutenbergView` derives the asset domain from the site's
	//   host, which drops the port, so a site on a non-default port (any local
	//   dev setup) is cross-origin and does not recover.
	//
	// There is no fallback: core sends the header before
	// `wp_generate_attachment_metadata()`, so the fatal leaves no body to parse
	// the ID from.
	apiFetch.use( nativeMediaUploadMiddleware );
	apiFetch.use( apiFetch.mediaUploadMiddleware );
	apiFetch.use( stripDraftPostIdMiddleware );
	apiFetch.use( mediaPermissionsMiddleware );
	apiFetch.use( transformOEmbedApiResponse );
	apiFetch.use( siteIndexMiddleware );
	apiFetch.use(
		apiFetch.createPreloadingMiddleware( preloadData ?? defaultPreloadData )
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
		nativeMediaDelete( options, transport ) ??
		nativeMediaUpload( options, transport, next ) ??
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
 * @param {Object}                                options   The api-fetch options.
 * @param {NativeUploadTransport}                 transport How to reach native code.
 * @param {(options: Object) => Promise<unknown>} next      The next middleware.
 * @return {?Promise} The relayed upload, or `null` if not applicable.
 */
function nativeMediaUpload( options, transport, next ) {
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
		? schemeUpload( options, file, query, transport.schemeBase, next )
		: loopbackUpload( options, file, query, transport );

	// Use the two-argument form of `.then()` so the rejection handler catches
	// *only* a failure to reach native code — not errors thrown while handling
	// a response (those must surface as real failures).
	return upload.then(
		( outcome ) =>
			outcome.fallback ??
			relayUploadResponse( outcome.response, options ),
		( connectionError ) =>
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
 * @return {Promise<{response: Response}>} The server's response.
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
	} ).then( ( response ) => ( { response } ) );
}

/**
 * Sends an upload to iOS's native upload scheme.
 *
 * The file goes in chunks, each an `ArrayBuffer`: WebKit hands a URL scheme
 * handler only bodies it has buffered, and drops a `Blob` body — including a
 * `FormData` that holds one — without an error. Chunking also keeps at most one
 * chunk of the file in the page's memory at a time.
 *
 * A failure before `finish` means WordPress never saw the file, so the upload
 * falls back to the web view's own path rather than failing: nothing can be
 * duplicated. From `finish` on, native code may already have sent the file, so a
 * failure there is reported, not retried.
 *
 * @param {Object}                                options    The api-fetch options.
 * @param {File}                                  file       The file being uploaded.
 * @param {string}                                query      The request's query string.
 * @param {string}                                schemeBase The native upload scheme's base URL.
 * @param {(options: Object) => Promise<unknown>} next       The next middleware, for the fallback.
 * @return {Promise<{response?: Response, fallback?: Promise}>} The outcome.
 */
async function schemeUpload( options, file, query, schemeBase, next ) {
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
		if ( signal?.aborted ) {
			throw sendError;
		}
		warn(
			'Native upload unavailable; uploading through the web view instead',
			sendError
		);
		return { fallback: next( options ) };
	}

	return {
		response: await finishNativeUpload(
			schemeBase,
			sessionId,
			uploadFields( options.body ),
			query,
			signal
		),
	};
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
 * Resolves with the response when it is a 2xx, and rejects otherwise.
 *
 * @param {Promise<Response>} request The request.
 * @return {Promise<Response>} The successful response.
 */
async function expectOk( request ) {
	const response = await request;
	if ( ! response.ok ) {
		throw new Error(
			`Native upload request failed with status ${ response.status }`
		);
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
 * Turns native code's relay of WordPress's response into what the caller asked
 * for.
 *
 * @param {Response} response WordPress's response, relayed.
 * @param {Object}   options  The api-fetch options.
 * @return {Promise|Response} The response or its parsed body.
 */
function relayUploadResponse( response, options ) {
	// `parse: false` asks for raw `Response` semantics. Core's media
	// upload middleware runs above this one and makes exactly that
	// request so it can read `x-wp-upload-attachment-id` off a failed
	// upload and retry `post-process`. Honor it by resolving or
	// rejecting with the `Response` itself, leaving the parsing (and
	// the recovery decision) to that middleware — parsing here would
	// hide the header and turn a recoverable upload into a permanent
	// failure.
	if ( options.parse === false ) {
		if ( ! response.ok ) {
			// A handoff to core's post-process retry, not an outcome —
			// core reads `x-wp-upload-attachment-id` off this response and
			// may still recover. Stay silent (as `nativeMediaDelete` does)
			// rather than reporting a failure that hasn't happened yet.
			return Promise.reject( response );
		}
		return response;
	}

	// Native code relays WordPress's response verbatim. On a
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
	// POST /wp/v2/media could duplicate the attachment. (The scheme transport
	// falls back itself, earlier, while that is still safe.)
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
 * @param {Object}                options   The api-fetch options.
 * @param {NativeUploadTransport} transport How to reach native code.
 * @return {?Promise} The relayed deletion, or `null` if not applicable.
 */
function nativeMediaDelete( options, transport ) {
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
			if ( options.parse === false ) {
				if ( ! response.ok ) {
					return Promise.reject( response );
				}
				return response;
			}

			if ( ! response.ok ) {
				return response
					.json()
					.catch( () => invalidUploadResponseError() )
					.then( ( body ) => {
						logError( 'Native media deletion failed', body );
						throw body;
					} );
			}

			return response.json().catch( () => {
				const error = invalidUploadResponseError();
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
