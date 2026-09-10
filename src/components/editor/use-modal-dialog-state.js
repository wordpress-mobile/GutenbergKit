/**
 * WordPress dependencies
 */
import { useEffect, useRef } from '@wordpress/element';

/**
 * Internal dependencies
 */
import { onModalDialogOpened, onModalDialogClosed } from '../../utils/bridge';

/**
 * Notifies the native host when a modal dialog opens or closes.
 *
 * This hook monitors the visibility state of a modal dialog and dispatches
 * bridge events to inform the native host app (iOS/Android) when the dialog
 * state changes. This allows the host app to respond appropriately, such as
 * disabling navigation UI while a web modal is active.
 *
 * @param {boolean} isModalVisible A boolean indicating whether the modal is visible.
 * @param {string}  dialogType     The type of modal dialog (e.g., 'block-inserter', 'media-library').
 *
 * @return {void}
 */
export function useModalDialogState( isModalVisible, dialogType ) {
	const isModalVisibleRef = useRef( isModalVisible );

	useEffect( () => {
		isModalVisibleRef.current = isModalVisible;

		if ( isModalVisible ) {
			onModalDialogOpened( dialogType );
		} else {
			onModalDialogClosed( dialogType );
		}
	}, [ isModalVisible, dialogType ] );

	// The editor can unmount with a dialog still open, most notably when its
	// `ErrorBoundary` catches. Report the dialog closed so the host does not
	// keep its navigation disabled for a dialog that no longer exists.
	useEffect(
		() => () => {
			if ( isModalVisibleRef.current ) {
				onModalDialogClosed( dialogType );
			}
		},
		[ dialogType ]
	);
}
