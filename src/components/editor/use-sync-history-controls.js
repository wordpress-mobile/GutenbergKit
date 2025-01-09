/**
 * WordPress dependencies
 */
import { useEffect } from '@wordpress/element';
import { useSelect } from '@wordpress/data';
import { store as editorStore } from '@wordpress/editor';

/**
 * Internal dependencies
 */
import { onEditorHistoryChanged } from '../../utils/bridge';

/**
 * Synchronizes the host's undo and redo history controls with the editor.
 *
 * This hook uses the `useSelect` hook to access the editor store and determine
 * whether there are undo and redo actions available. It then triggers the
 * `onEditorHistoryChanged` function whenever the availability of undo or redo
 * actions changes.
 *
 * @return {void}
 */
export function useSyncHistoryControls() {
	const { hasUndo, hasRedo } = useSelect((select) => {
		const store = select(editorStore);
		return {
			hasUndo: store.hasEditorUndo(),
			hasRedo: store.hasEditorRedo(),
		};
	}, []);

	useEffect(() => {
		onEditorHistoryChanged(hasUndo, hasRedo);
	}, [hasUndo, hasRedo]);
}
