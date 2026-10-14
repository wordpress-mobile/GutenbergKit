import { useEffect } from '@wordpress/element';
import { useDispatch } from '@wordpress/data';
import { store as editorStore } from '@wordpress/editor';

export function useEditorSetup( post ) {
	const { setupEditor } = useDispatch( editorStore );

	useEffect( () => {
		setupEditor( post, {} );

		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, [] );
}
