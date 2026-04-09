/**
 * WordPress dependencies
 */
import { useEffect } from '@wordpress/element';
import { useSelect } from '@wordpress/data';
import { store as editorStore } from '@wordpress/editor';

/**
 * Internal dependencies
 */
import { onSaveAvailabilityChanged } from '../../utils/bridge';

/**
 * Synchronizes the host's save availability state with the editor.
 *
 * This hook subscribes to the editor store's save-related selectors and
 * dispatches an `onSaveAvailabilityChanged` bridge event whenever any of
 * the values change.
 *
 * @return {void}
 */
export function useSyncSaveAvailability() {
	const { isDirty, isSaveable, isSavingLocked, isSaving, isAutosaving } =
		useSelect( ( select ) => {
			const store = select( editorStore );
			return {
				isDirty: store.isEditedPostDirty(),
				isSaveable: store.isEditedPostSaveable(),
				isSavingLocked: store.isPostSavingLocked(),
				isSaving: store.isSavingPost(),
				isAutosaving: store.isAutosavingPost(),
			};
		}, [] );

	useEffect( () => {
		onSaveAvailabilityChanged( {
			isDirty,
			isSaveable,
			isSavingLocked,
			isSaving,
			isAutosaving,
		} );
	}, [ isDirty, isSaveable, isSavingLocked, isSaving, isAutosaving ] );
}
