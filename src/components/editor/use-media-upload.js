/**
 * WordPress dependencies
 */
import { addFilter, removeFilter } from '@wordpress/hooks';
import { useCallback, useEffect, useRef } from '@wordpress/element';

/**
 * Internal dependencies
 */
import { openMediaLibrary } from '../../utils/bridge';
import { warn } from '../../utils/logger';

/**
 * Global registry for media upload callbacks indexed by context ID.
 * This allows multiple MediaPlaceholder instances to coexist without
 * overwriting each other's callbacks.
 */
const callbackRegistry = {};

/**
 * Counter for generating unique context IDs.
 */
let contextIdCounter = 0;

/**
 * @typedef {Object} MediaUploadConfig
 * @property {Function}        onSelect         Callback function to handle the selected media.
 * @property {string[]}        [allowedTypes]   Comma-separated list of media types to allow.
 * @property {boolean}         [multiple=false] Flag to indicate if multiple media items can be selected.
 * @property {number|number[]} [value]          The context's currently selected media.
 */

/**
 * Adds a filter for the MediaUpload component in the Gutenberg editor.
 *
 * @return {void}
 */
export function useMediaUpload() {
	useEffect( () => {
		addFilter( 'editor.MediaUpload', 'GutenbergKit', () => MediaUpload );

		return () => {
			removeFilter( 'editor.MediaUpload', 'GutenbergKit' );
		};
	}, [] );
}

/**
 * Component exposing the native media library.
 *
 * @param {MediaUploadConfig} props Component props.
 *
 * @return {Element} The rendered component.
 */
function MediaUpload( { render, ...config } ) {
	const { open } = useNativeMediaLibrary( config );

	return render( { open } );
}

/**
 * Establishes global bridge function to handle native Media Library interactions.
 *
 * @param {MediaUploadConfig} config Configuration object for the Media Library.
 *
 * @return {{open: ()=>void}} An object containing a function to open the Media Library.
 */
function useNativeMediaLibrary( { onSelect, ...config } ) {
	const { allowedTypes, multiple = false, value } = config;
	const contextIdRef = useRef( null );

	useEffect( () => {
		// Generate a unique context ID for this MediaPlaceholder instance
		const contextId = `media-upload-${ ++contextIdCounter }`;
		contextIdRef.current = contextId;

		// Register this instance's callback in the global registry
		callbackRegistry[ contextId ] = ( attachment ) => {
			onSelect( config.multiple ? attachment : attachment[ 0 ] );
		};

		// Set up the global bridge function that routes to the correct callback
		// based on the contextId returned from the native layer
		if (
			! window.editor.setMediaUploadAttachment ||
			! window.editor.setMediaUploadAttachment.__isRegistry
		) {
			window.editor.setMediaUploadAttachment = (
				attachment,
				receivedContextId
			) => {
				// If contextId is provided, use the registry (new behavior)
				if (
					receivedContextId &&
					callbackRegistry[ receivedContextId ]
				) {
					callbackRegistry[ receivedContextId ]( attachment );
				} else if ( receivedContextId ) {
					warn(
						`No callback found for contextId: ${ receivedContextId }`
					);
				} else {
					// Fallback: If no contextId, use the last registered callback (backward compatibility)
					const callbacks = Object.values( callbackRegistry );
					if ( callbacks.length > 0 ) {
						callbacks[ callbacks.length - 1 ]( attachment );
					}
				}
			};
			// Mark this function as the registry-based implementation
			window.editor.setMediaUploadAttachment.__isRegistry = true;
		}

		return () => {
			// Clean up this instance's callback when unmounted
			delete callbackRegistry[ contextIdRef.current ];
		};
	}, [ onSelect, config.multiple ] );

	const open = useCallback(
		() =>
			openMediaLibrary( {
				allowedTypes,
				multiple,
				value,
				contextId: contextIdRef.current,
			} ),
		[ allowedTypes, multiple, value ]
	);

	return { open };
}
