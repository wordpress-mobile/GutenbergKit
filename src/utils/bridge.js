/**
 * Internal dependencies
 */
import parseException from './exception-parser';
import { debug, error } from './logger';
import { isDevMode } from './dev-mode';

/**
 * Generic function to dispatch messages to both Android and iOS bridges.
 *
 * @param {string} methodName The name of the method to call on the native side.
 * @param {Object} args       Arguments object to pass to the method.
 *
 * @return {void}
 */
function dispatchToBridge( methodName, args = {} ) {
	debug( `Bridge event: ${ methodName }`, args );

	// Android bridge - extract values in property definition order
	if ( window.editorDelegate ) {
		const method = window.editorDelegate[ methodName ];
		if ( method ) {
			method.apply( window.editorDelegate, Object.values( args ) );
		}
	}

	// iOS webkit bridge - use arguments object directly
	if ( window.webkit ) {
		window.webkit.messageHandlers.editorDelegate.postMessage( {
			message: methodName,
			body: args,
		} );
	}
}

/**
 * Notifies the native host that the editor has loaded.
 *
 * @return {void}
 */
export function editorLoaded() {
	dispatchToBridge( 'onEditorLoaded', {} );
}

/**
 * Notifies the native host that the editor content has changed.
 *
 * @return {void}
 */
export function onEditorContentChanged() {
	dispatchToBridge( 'onEditorContentChanged', {} );
}

/**
 * Notifies the native host that the editor history stack has changed.
 *
 * @param {boolean} hasUndo Whether the editor has undo history.
 * @param {boolean} hasRedo Whether the editor has redo history.
 *
 * @return {void}
 */
export function onEditorHistoryChanged( hasUndo, hasRedo ) {
	dispatchToBridge( 'onEditorHistoryChanged', { hasUndo, hasRedo } );
}

/**
 * Notifies the native host that the featured image has changed.
 *
 * @param {number} [mediaID] The featured image ID.
 *
 * @return {void}
 */
export function onEditorFeaturedImageChanged( mediaID ) {
	dispatchToBridge( 'onEditorFeaturedImageChanged', { mediaID } );
}

/**
 * Notifies the native host that blocks have changed.
 *
 * @param {boolean} [isEmpty=false] Whether the editor is empty.
 *
 * @return {void}
 */
export function onBlocksChanged( isEmpty = false ) {
	dispatchToBridge( 'onBlocksChanged', { isEmpty } );
}

/**
 * Requests the native host to show the block picker.
 *
 * The BlockInserterBridge component maintains the current inserter state
 * at window.blockInserter, which automatically stays in sync with the editor
 * via WordPress hooks (useInsertionPoint and useBlockTypesState).
 *
 * The sections array is preprocessed by preprocessBlockTypesForNativeInserter()
 * which handles ordering, contextual filtering, and localized section names.
 *
 * @param {Object} sourceRect The rectangle coordinates of the source element that triggered the inserter.
 *
 * @return {void}
 */
export function showBlockInserter( sourceRect ) {
	if ( ! window.blockInserter ) {
		debug(
			'BlockInserterBridge not available. Ensure editor is initialized.'
		);
		return;
	}

	const payload = {
		sections: window.blockInserter.sections,
		patterns: window.blockInserter.patterns,
		patternCategories: window.blockInserter.patternCategories,
		sourceRect,
	};

	debug( `Bridge event: showBlockInserter`, payload );

	// Not using `dispatchToBridge`: its Android branch flattens `args` with
	// `Object.values` and passes them as positional parameters. That works
	// when every value is a primitive, but `@JavascriptInterface` can't
	// receive arrays or objects — they arrive as `"[object Object]"`.
	// Instead we stringify for Android (single String arg) and pass the
	// structured body to iOS, matching the pattern used by openMediaLibrary,
	// onNetworkRequest, and logException.
	if ( window.editorDelegate ) {
		window.editorDelegate.showBlockInserter( JSON.stringify( payload ) );
	}

	if ( window.webkit ) {
		window.webkit.messageHandlers.editorDelegate.postMessage( {
			message: 'showBlockInserter',
			body: payload,
		} );
	}
}

/**
 * Requests the native host to open the Media Library
 *
 * @param {import('../hooks/use-media-upload').MediaUploadConfig} config Media Library configuration.
 *
 * @return {void}
 */
export function openMediaLibrary( config ) {
	debug( `Bridge event: openMediaLibrary`, config );

	if ( window.editorDelegate ) {
		window.editorDelegate.openMediaLibrary( JSON.stringify( config ) );
	}

	if ( window.webkit ) {
		window.webkit.messageHandlers.editorDelegate.postMessage( {
			message: 'openMediaLibrary',
			body: config,
		} );
	}
}

/**
 * Notifies the native host that an autocompleter was triggered.
 *
 * @param {string} type The type of autocompleter that was triggered (e.g. 'at-symbol', 'plus-symbol').
 *
 * @return {void}
 */
export function onAutocompleterTriggered( type ) {
	dispatchToBridge( 'onAutocompleterTriggered', { type } );
}

/**
 * Notifies the native host that a modal dialog has opened.
 *
 * @param {string} dialogType The type of modal dialog that opened (e.g. 'block-inserter', 'media-library').
 *
 * @return {void}
 */
export function onModalDialogOpened( dialogType ) {
	dispatchToBridge( 'onModalDialogOpened', { dialogType } );
}

/**
 * Notifies the native host that a modal dialog has closed.
 *
 * @param {string} dialogType The type of modal dialog that closed (e.g. 'block-inserter', 'media-library').
 *
 * @return {void}
 */
export function onModalDialogClosed( dialogType ) {
	dispatchToBridge( 'onModalDialogClosed', { dialogType } );
}

/**
 * Notifies the native host about a network request and its response.
 *
 * @param {Object}      requestData                 The network request data.
 * @param {string}      requestData.url             The request URL.
 * @param {string}      requestData.method          The HTTP method (GET, POST, etc.).
 * @param {Object|null} requestData.requestHeaders  The request headers object.
 * @param {string|null} requestData.requestBody     The request body.
 * @param {number}      requestData.status          The HTTP response status code.
 * @param {string}      requestData.statusText      The HTTP response status text (e.g., "OK", "Not Found").
 * @param {Object|null} requestData.responseHeaders The response headers object.
 * @param {string|null} requestData.responseBody    The response body.
 * @param {number}      requestData.duration        The request duration in milliseconds.
 *
 * @return {void}
 */
export function onNetworkRequest( requestData ) {
	debug( `Bridge event: onNetworkRequest`, requestData );

	if ( window.editorDelegate ) {
		window.editorDelegate.onNetworkRequest( JSON.stringify( requestData ) );
	}

	if ( window.webkit ) {
		window.webkit.messageHandlers.editorDelegate.postMessage( {
			message: 'onNetworkRequest',
			body: requestData,
		} );
	}
}

/**
 * @typedef GBKitConfig
 *
 * @property {boolean}  [themeStyles]            Controls if theme styles are applied to the editor.
 * @property {string}   [siteApiRoot]            The root URL of the site's API.
 * @property {string[]} [siteApiNamespace]       The namespace of the site's API; if multiple namespaces are provided, the first one is used as the default.
 * @property {string[]} [namespaceExcludedPaths] The paths that should not be namespaced.
 * @property {string}   [authHeader]             The authentication header.
 * @property {string}   [hideTitle]              Whether to hide the title.
 * @property {Post}     [post]                   The post data.
 * @property {boolean}  [enableNetworkLogging]   Enables logging of all network requests/responses to the native host via onNetworkRequest bridge method.
 * @property {number}   [nativeUploadPort]       Port the local HTTP server is listening on. If absent, the native upload override is not activated.
 * @property {string}   [nativeUploadToken]      Per-session auth token for requests to the local upload server.
 */

/**
 * Default values used when the native host omits fields from the post payload.
 * Centralized here so all consumers (getPost, filterEndpointsMiddleware) agree
 * on the fallback contract.
 */
export const POST_FALLBACKS = {
	id: -1,
	type: 'post',
	restBase: 'posts',
	restNamespace: 'wp/v2',
	status: 'draft',
};

/**
 * Retrieves the native-host-provided GBKit object from localStorage or returns
 * an empty object if not found.
 *
 * @return {GBKitConfig} The GBKit object.
 */
export function getGBKit() {
	if ( window.GBKit ) {
		return window.GBKit;
	}

	try {
		return JSON.parse( localStorage.getItem( 'GBKit' ) ) || {};
	} catch ( err ) {
		error( 'Failed to parse GBKit from localStorage', err );
		return {};
	}
}

/**
 * The native loopback relay's connection details, or `null` when the host is
 * not running one.
 *
 * Read from the injected global only, never through ``getGBKit``: its
 * `localStorage` fallback returns whatever the last editor session wrote, and
 * iOS does not clear it. A relay's port and per-session token are valid only
 * for the server that issued them, so a persisted copy points at a listener
 * that has been stopped — or, worse, at a port something else now owns. Every
 * REST request would go there.
 *
 * Falling back to no relay is the safe direction to be wrong in: requests take
 * the direct path, which is what they did before a relay existed.
 *
 * @return {{port: number, token: string}|null} The relay details.
 */
export function getNetworkProxy() {
	return window.GBKit?.networkProxy ?? null;
}

/**
 * @typedef {Object} Post
 * @property {string} [title]       The title of the post.
 * @property {string} [content]     The content of the post.
 * @property {string} type          The type of the post.
 * @property {string} restBase      The REST API base path for this post type.
 * @property {string} restNamespace The REST API namespace for this post type.
 * @property {number} id            The ID of the post.
 * @property {number} [author]      The author ID of the post.
 * @property {string} [status]      The status of the post.
 */

/**
 * Requests the latest persisted content from the native host.
 *
 * Used during editor initialization to recover content after WebView refresh.
 * The native host maintains the authoritative content via autosave events.
 *
 * @return {Promise<{title: string, content: string}|null>} The latest content or null if unavailable.
 */
export async function requestLatestContent() {
	if ( window.webkit?.messageHandlers?.requestLatestContent ) {
		try {
			return await window.webkit.messageHandlers.requestLatestContent.postMessage(
				{}
			);
		} catch ( err ) {
			error( 'Failed to request content from iOS host', err );
			return null;
		}
	}

	if ( window.editorDelegate?.requestLatestContent ) {
		try {
			const result = window.editorDelegate.requestLatestContent();
			return result ? JSON.parse( result ) : null;
		} catch ( err ) {
			error( 'Failed to request content from Android host', err );
			return null;
		}
	}

	return null;
}

/**
 * Retrieves the current post data from the native host
 *
 * Always requests content from the native host first, as it maintains the
 * latest content via autosave. Falls back to `window.GBKit.post` only if the
 * native bridge is unavailable (e.g., dev mode).
 *
 * Note: `window.GBKit.post.title/content` are "initial values" injected at
 * WebView load. After a WebView refresh, these may be stale. The native host
 * has the authoritative content from autosave.
 *
 * @return {Promise<Post>} The post object.
 */
export async function getPost() {
	const { post } = getGBKit();

	const hostContent = await requestLatestContent();

	if ( hostContent ) {
		debug( 'Using content from native host' );
		return {
			id: post?.id || POST_FALLBACKS.id,
			type: post?.type || POST_FALLBACKS.type,
			restBase: post?.restBase || POST_FALLBACKS.restBase,
			restNamespace: post?.restNamespace || POST_FALLBACKS.restNamespace,
			status: post?.status || POST_FALLBACKS.status,
			title: { raw: hostContent.title },
			content: { raw: hostContent.content },
		};
	}

	if ( post ) {
		debug( 'Native bridge unavailable, using GBKit initial content' );
		return {
			id: post.id || POST_FALLBACKS.id,
			type: post.type || POST_FALLBACKS.type,
			restBase: post.restBase || POST_FALLBACKS.restBase,
			restNamespace: post.restNamespace || POST_FALLBACKS.restNamespace,
			status: post.status || POST_FALLBACKS.status,
			title: { raw: decodeURIComponent( post.title ) },
			content: { raw: decodeURIComponent( post.content ) },
		};
	}

	// Fallback to default empty post
	return {
		...POST_FALLBACKS,
		title: { raw: '' },
		content: { raw: '' },
	};
}

/**
 * Logs an error to the host app.
 *
 * @param {Error}   exception                     The exception object to be logged.
 * @param {Object}  [options]                     Additional options.
 * @param {Object}  [options.context]             Additional context to be logged.
 * @param {Object}  [options.tags]                Additional tags to be logged.
 * @param {boolean} [options.isHandled=false]     Whether the error is handled.
 * @param {string}  [options.handledBy='Unknown'] The name of the error handler.
 *
 * @return {void}
 */
export function logException(
	exception,
	{ context, tags, isHandled, handledBy } = {
		context: {},
		tags: {},
		isHandled: false,
		handledBy: 'Unknown',
	}
) {
	const parsedException = {
		...parseException( exception, { context, tags } ),
		isHandled,
		handledBy,
	};

	debug( `Bridge event: logException`, parsedException );

	if ( window.editorDelegate ) {
		window.editorDelegate.onEditorExceptionLogged(
			JSON.stringify( parsedException )
		);
	}

	if ( window.webkit ) {
		window.webkit.messageHandlers.editorDelegate.postMessage( {
			message: 'onEditorExceptionLogged',
			body: parsedException,
		} );
	}
}

/**
 * Waits for the GBKit global to be available.
 *
 * @param {number} timeoutMs Timeout in milliseconds after which to reject.
 *
 * @return {Promise<void>} Promise that resolves with GBKit config or rejects after timeout.
 */
export function awaitGBKitGlobal( timeoutMs = 3000 ) {
	return new Promise( ( resolve, reject ) => {
		const startTime = Date.now();

		const checkGBKit = () => {
			if ( window.GBKit ) {
				resolve();
				return;
			}

			if ( Date.now() - startTime >= timeoutMs ) {
				// In development mode, bypass the GBKit requirement allowing the editor
				// to load without the native bridge to simplify testing.
				if ( isDevMode() ) {
					resolve();
					return;
				}

				reject(
					new Error( 'GBKit global not available after timeout' )
				);
				return;
			}

			setTimeout( checkGBKit, 100 );
		};

		checkGBKit();
	} );
}
