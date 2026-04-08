/**
 * WordPress dependencies
 */
import { useEffect } from '@wordpress/element';
import { useDispatch } from '@wordpress/data';
import { store as editorStore } from '@wordpress/editor';

export function useEditorSetup( post ) {
	const { setEditedPost, setupEditor } = useDispatch( editorStore );

	useEffect( () => {
		setupEditor( post, {} );

		// Temp, check why this isn't being called in the provider.
		setEditedPost( post.type, post.id );

		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, [] );
}
