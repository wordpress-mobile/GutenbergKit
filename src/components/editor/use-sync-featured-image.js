import { useEffect, useRef } from '@wordpress/element';
import { useSelect } from '@wordpress/data';
import { store as editorStore } from '@wordpress/editor';
import { onEditorFeaturedImageChanged } from '../../utils/bridge';

/**
 * Unidirectionally synchronizes the featured image with the host.
 *
 * Only changes made in the editor are reported. The initial value comes from
 * the preloaded server record, which may predate the host's own edits.
 */
export function useSyncFeaturedImage() {
	const { featuredImageId } = useSelect( ( select ) => {
		const { getEditedPostAttribute } = select( editorStore );
		return {
			featuredImageId: getEditedPostAttribute( 'featured_media' ),
		};
	}, [] );
	const lastFeaturedImageId = useRef( featuredImageId );

	useEffect( () => {
		if ( featuredImageId === lastFeaturedImageId.current ) {
			return;
		}

		lastFeaturedImageId.current = featuredImageId;

		if ( ! featuredImageId ) {
			return;
		}

		onEditorFeaturedImageChanged( featuredImageId );
	}, [ featuredImageId ] );
}
