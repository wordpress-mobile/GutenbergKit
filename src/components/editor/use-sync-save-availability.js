import { useEffect, useRef } from '@wordpress/element';
import { useSelect } from '@wordpress/data';
import { store as editorStore } from '@wordpress/editor';
import { onEditorSaveAvailabilityChanged } from '../../utils/bridge';

/**
 * Synchronizes the host's save controls with the editor's save availability.
 *
 * Reports whether the post is saveable and whether saving is locked (e.g. by
 * an in-progress upload) once the post is set up, which precedes
 * `editorLoaded`, and then on each change.
 * Reporting stops when the editor unmounts; `onEditorUnavailable` tells the
 * host to disregard the last reported state.
 *
 * @return {void}
 */
export function useSyncSaveAvailability() {
	const { isReady, isSaveable, isSavingLocked } = useSelect( ( select ) => {
		const store = select( editorStore );
		return {
			isReady: store.__unstableIsEditorReady(),
			isSaveable: store.isEditedPostSaveable(),
			isSavingLocked: store.isPostSavingLocked(),
		};
	}, [] );
	const lastReported = useRef();

	useEffect( () => {
		if ( ! isReady ) {
			return;
		}

		const previous = lastReported.current;
		if (
			previous?.isSaveable === isSaveable &&
			previous?.isSavingLocked === isSavingLocked
		) {
			return;
		}

		lastReported.current = { isSaveable, isSavingLocked };
		onEditorSaveAvailabilityChanged( isSaveable, isSavingLocked );
	}, [ isReady, isSaveable, isSavingLocked ] );
}
