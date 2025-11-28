/**
 * Internal dependencies
 */
import parseException from './exception-parser';
import { debug } from './logger';
import { isDevMode } from './dev-mode';
import { basicFetch } from './fetch';

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

	// Send preprocessed sections and patterns to native
	dispatchToBridge( 'showBlockInserter', {
		sections: window.blockInserter.sections,
		patterns: window.blockInserter.patterns,
		patternCategories: window.blockInserter.patternCategories,
		sourceRect,
	} );
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
 * @typedef GBKitConfig
 *
 * @property {boolean}  [themeStyles]            Controls if theme styles are applied to the editor.
 * @property {string}   [siteApiRoot]            The root URL of the site's API.
 * @property {string[]} [siteApiNamespace]       The namespace of the site's API; if multiple namespaces are provided, the first one is used as the default.
 * @property {string[]} [namespaceExcludedPaths] The paths that should not be namespaced.
 * @property {string}   [authHeader]             The authentication header.
 * @property {string}   [hideTitle]              Whether to hide the title.
 * @property {Post}     [post]                   The post data.
 */

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
	} catch ( error ) {
		return {};
	}
}

/**
 * @typedef {Object} Post
 * @property {string} [title]   The title of the post.
 * @property {string} [content] The content of the post.
 * @property {string} type      The type of the post.
 * @property {number} id        The ID of the post.
 * @property {number} [author]  The author ID of the post.
 * @property {string} [status]  The status of the post.
 */

/**
 * Retrieves the current post data from the GBKit global.
 *
 * @return {Post} The post object containing the following properties:
 */
export function getPost() {
	const { post } = getGBKit();
	if ( post ) {
		return {
			id: post.id,
			type: post.type || 'post',
			status: post.status,
			title: { raw: decodeURIComponent( post.title ) },
			content: { raw: decodeURIComponent( post.content ) },
		};
	}

	// Since we don't use the auto-save functionality, draft posts need to have an ID.
	// We assign a temporary ID of -1.
	return {
		id: -1,
		type: 'post',
		status: 'auto-draft',
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
 * @return {Promise<GBKitConfig>} Promise that resolves with GBKit config or rejects after timeout.
 */
export function awaitGBKitGlobal( timeoutMs = 3000 ) {
	return new Promise( ( resolve, reject ) => {
		const startTime = Date.now();

		const checkGBKit = () => {
			if ( window.GBKit ) {
				resolve( window.GBKit );
				return;
			}

			// In development mode, bypass the GBKit requirement and seed a default post,
			// allowing the editor to load without the native bridge to simplify testing.
			if ( isDevMode() ) {
				resolve( {
					post: {
						id: -1,
						type: 'post',
						title: '',
						content: '',
						status: 'auto-draft',
					},
					themeStyles: false,
					hideTitle: false,
				} );
			}

			if ( Date.now() - startTime >= timeoutMs ) {
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

/**
 * Retrieves the editor assets from the native host.
 *
 * @return {Promise<{scripts: string, styles: string, allowed_block_types: string[]}>} Promise that resolves with the assets object.
 */
export async function fetchEditorAssets() {
	if ( window.webkit ) {
		return await window.webkit.messageHandlers.loadFetchedEditorAssets.postMessage(
			{ asset: 'manifest' }
		);
	}

	const { siteApiRoot, editorAssetsEndpoint, authHeader } = getGBKit();
	const url = new URL(
		editorAssetsEndpoint || `${ siteApiRoot }wpcom/v2/editor-assets`
	);
	// The GutenbergKit bundle includes the required `@wordpress` modules
	url.searchParams.set( 'exclude', 'core,gutenberg' );
	// Use our fetch utility, as we have not yet loaded the `wp.apiFetch` utility
	return await basicFetch( url.toString(), {
		headers: { Authorization: authHeader },
	} );
}
