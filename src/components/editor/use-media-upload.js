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

		callbackRegistry[ contextId ] = ( attachment ) => {
			onSelect( config.multiple ? attachment : attachment[ 0 ] );
		};

		window.editor = window.editor || {};
		window.editor.setMediaUploadAttachment = (
			attachment,
			receivedContextId
		) => {
			if ( ! receivedContextId ) {
				warn( 'setMediaUploadAttachment called without contextId' );
				return;
			}

			const callback = callbackRegistry[ receivedContextId ];
			if ( ! callback ) {
				warn(
					`No callback found for contextId: ${ receivedContextId }`
				);
				return;
			}

			callback( attachment );
		};

		return () => {
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
