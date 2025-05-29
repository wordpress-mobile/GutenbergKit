/**
 * WordPress dependencies
 */
import { addFilter, removeFilter } from '@wordpress/hooks';
import { useCallback, useEffect } from '@wordpress/element';

/**
 * Internal dependencies
 */
import { openMediaLibrary } from '../../utils/bridge';

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

	useEffect( () => {
		window.editor.setMediaUploadAttachment = ( attachment ) => {
			onSelect( config.multiple ? attachment : attachment[ 0 ] );
		};

		return () => {
			window.editor.setMediaUploadAttachment = () => {};
		};
	}, [ onSelect, config.multiple ] );

	const open = useCallback(
		() =>
			openMediaLibrary( {
				allowedTypes,
				multiple,
				value,
			} ),
		[ allowedTypes, multiple, value ]
	);

	return { open };
}
