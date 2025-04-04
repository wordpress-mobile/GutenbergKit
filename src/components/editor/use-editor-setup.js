/**
 * WordPress dependencies
 */
import { useEffect } from '@wordpress/element';
import { useDispatch } from '@wordpress/data';
import { store as coreStore } from '@wordpress/core-data';
import { store as editorStore } from '@wordpress/editor';

/**
 * Internal dependencies
 */
import { postTypeEntities } from '../../utils/post-type-entities';

export function useEditorSetup( post ) {
	const { addEntities, receiveEntityRecords } = useDispatch( coreStore );
	const { setEditedPost, setupEditor } = useDispatch( editorStore );

	useEffect( () => {
		addEntities( postTypeEntities );
		receiveEntityRecords( 'postType', post.type, post );

		setupEditor( post, {} );

		// Temp, check why this isn't being called in the provider.
		setEditedPost( post.type, post.id );

		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, [] );
}
