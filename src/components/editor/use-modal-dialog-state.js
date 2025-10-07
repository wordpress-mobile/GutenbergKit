/**
 * WordPress dependencies
 */
import { useEffect } from '@wordpress/element';

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
	useEffect( () => {
		if ( isModalVisible ) {
			onModalDialogOpened( dialogType );
		} else {
			onModalDialogClosed( dialogType );
		}
	}, [ isModalVisible, dialogType ] );
}
