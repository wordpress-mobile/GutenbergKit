/**
 * WordPress dependencies
 */
import apiFetch from '@wordpress/api-fetch';
import { getBlockTypes } from '@wordpress/blocks';

/**
 * Internal dependencies
 */
import parseException from './exception-parser';

/**
 * Notifies the native host that the editor has loaded.
 *
 * @return {void}
 */
export function editorLoaded() {
	if ( window.editorDelegate ) {
		window.editorDelegate.onEditorLoaded();
	}

	if ( window.webkit ) {
		window.webkit.messageHandlers.editorDelegate.postMessage( {
			message: 'onEditorLoaded',
			body: {},
		} );
	}
}

/**
 * Notifies the native host that the editor content has changed.
 *
 * @return {void}
 */
export function onEditorContentChanged() {
	if ( window.editorDelegate ) {
		window.editorDelegate.onEditorContentChanged();
	}

	if ( window.webkit ) {
		window.webkit.messageHandlers.editorDelegate.postMessage( {
			message: 'onEditorContentChanged',
		} );
	}
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
	if ( window.editorDelegate ) {
		window.editorDelegate.onEditorHistoryChanged( hasUndo, hasRedo );
	}

	if ( window.webkit ) {
		window.webkit.messageHandlers.editorDelegate.postMessage( {
			message: 'onEditorHistoryChanged',
			body: { hasUndo, hasRedo },
		} );
	}
}

/**
 * Notifies the native host that the featured image has changed.
 *
 * @param {number} [mediaID] The featured image ID.
 *
 * @return {void}
 */
export function onEditorFeaturedImageChanged( mediaID ) {
	if ( window.editorDelegate ) {
		window.editorDelegate.onEditorFeaturedImageChanged( mediaID );
	}

	if ( window.webkit ) {
		window.webkit.messageHandlers.editorDelegate.postMessage( {
			message: 'onEditorFeaturedImageChanged',
			body: { mediaID },
		} );
	}
}

/**
 * Notifies the native host that blocks have changed.
 *
 * @param {boolean} [isEmpty=false] Whether the editor is empty.
 *
 * @return {void}
 */
export function onBlocksChanged( isEmpty = false ) {
	if ( window.editorDelegate ) {
		window.editorDelegate.onBlocksChanged( isEmpty );
	}

	if ( window.webkit ) {
		window.webkit.messageHandlers.editorDelegate.postMessage( {
			message: 'onBlocksChanged',
			body: { isEmpty },
		} );
	}
}

/**
 * Requests the native host to show the block picker.
 *
 * @return {void}
 */
export function showBlockPicker() {
	// Get all registered block types
	const allBlockTypes = getBlockTypes();
	const blockTypes = allBlockTypes.map( ( blockType ) => {
		return {
			name: blockType.name,
			title: blockType.title,
			description: blockType.description,
			category: blockType.category,
			keywords: blockType.keywords || [],
		};
	} );

	try {
		if ( window.editorDelegate ) {
			window.editorDelegate.showBlockPicker(
				JSON.stringify( { blockTypes } )
			);
		}

		if (
			window.webkit &&
			window.webkit.messageHandlers &&
			window.webkit.messageHandlers.editorDelegate
		) {
			window.webkit.messageHandlers.editorDelegate.postMessage( {
				message: 'showBlockPicker',
				body: { blockTypes },
			} );
		}
	} catch ( error ) {
		// eslint-disable-next-line no-console
		console.error( 'Error sending message to native:', error );
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
			{
				asset: 'manifest',
			}
		);
	}
	// Android implementation - uses same API call that will be intercepted
	const { siteApiRoot, editorAssetsEndpoint } = getGBKit();
	const url =
		editorAssetsEndpoint || `${ siteApiRoot }wpcom/v2/editor-assets`;
	return await apiFetch( {
		url,
	} );
}



/**
 * Inserts multiple media files, creating a gallery if there are multiple images,
 * or individual blocks for other media types.
 *
 * @param {Array} mediaItems Array of MediaInfo entities with { id, url, type, title, caption, alt, metadata }
 * @return {Promise<void>}
 */
export async function insertMediaFromFiles( mediaItems ) {
	try {
		// Import dependencies
		const { createBlock } = await import( '@wordpress/blocks' );
		const { dispatch } = await import( '@wordpress/data' );
		const blockEditorStore = ( await import( '@wordpress/block-editor' ) )
			.store;

		// Map media types to block types
		const getBlockType = ( mediaType ) => {
			switch ( mediaType ) {
				case 'image':
					return 'core/image';
				case 'video':
					return 'core/video';
				case 'audio':
					return 'core/audio';
				case 'file':
				default:
					return 'core/file';
			}
		};

		// Separate images from other media types
		const imageItems = mediaItems.filter( item => item.type === 'image' );
		const otherItems = mediaItems.filter( item => item.type !== 'image' );

		const blocksToInsert = [];

		// If multiple images, create a gallery
		if ( imageItems.length > 1 ) {
			// Create inner image blocks for the gallery
			const innerImageBlocks = imageItems.map( item => 
				createBlock( 'core/image', {
					url: item.url,
					id: item.id || undefined,
					alt: item.alt || '',
					caption: item.caption || '',
					title: item.title || undefined,
				})
			);

			// Create gallery block with inner blocks
			const galleryBlock = createBlock( 
				'core/gallery', 
				{
					columns: Math.min( imageItems.length, 3 ), // Max 3 columns
					imageCrop: true,
					linkTo: 'none',
				},
				innerImageBlocks // Inner blocks parameter
			);

			blocksToInsert.push( galleryBlock );
		} else if ( imageItems.length === 1 ) {
			// Single image, create an image block
			const item = imageItems[ 0 ];
			const imageBlock = createBlock( 'core/image', {
				url: item.url,
				id: item.id || undefined,
				alt: item.alt || '',
				caption: item.caption || '',
				title: item.title || undefined,
			} );
			blocksToInsert.push( imageBlock );
		}

		// Handle non-image media types individually
		for ( const item of otherItems ) {
			const blockType = getBlockType( item.type );
			const blockAttributes = {
				url: item.url,
				id: item.id || undefined,
				caption: item.caption || '',
			};

			// Add title for file blocks
			if ( blockType === 'core/file' && item.title ) {
				blockAttributes.fileName = item.title;
			}

			// Add controls for video/audio
			if ( blockType === 'core/video' || blockType === 'core/audio' ) {
				blockAttributes.controls = true;
			}

			const block = createBlock( blockType, blockAttributes );
			blocksToInsert.push( block );
		}

		// Insert all blocks
		if ( blocksToInsert.length > 0 ) {
			const insertedBlocks = dispatch( blockEditorStore ).insertBlocks( blocksToInsert );
			
			if ( !insertedBlocks || insertedBlocks.length === 0 ) {
				throw new Error( 'Failed to insert blocks' );
			}
		}

		// TODO: this doesn't actually trigger the uploads

	} catch ( error ) {
		// eslint-disable-next-line no-console
		console.error( 'Failed to insert media:', error );
		logException( error, {
			context: { mediaItems },
			tags: { feature: 'media-insert-multiple' },
		} );
	}
}