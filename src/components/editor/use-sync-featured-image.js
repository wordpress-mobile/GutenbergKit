/**
 * WordPress dependencies
 */
import { useEffect } from '@wordpress/element';
import { useSelect } from '@wordpress/data';
import { store as editorStore } from '@wordpress/editor';

/**
 * Internal dependencies
 */
import { onEditorFeaturedImageChanged } from '../../utils/bridge';

/**
 * Unidirectionally synchronizes the featured image with the host.
 */
export function useSyncFeaturedImage() {
	const { featuredImageId } = useSelect( ( select ) => {
		const { getEditedPostAttribute } = select( editorStore );
		return {
			featuredImageId: getEditedPostAttribute( 'featured_media' ),
		};
	}, [] );

	useEffect( () => {
		if ( ! featuredImageId ) {
			return;
		}

		onEditorFeaturedImageChanged( featuredImageId );
	}, [ featuredImageId ] );
}
