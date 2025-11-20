/**
 * WordPress dependencies
 */
import { useEffect } from '@wordpress/element';
import { useDispatch } from '@wordpress/data';
import { store as noticesStore } from '@wordpress/notices';
import { __ } from '@wordpress/i18n';

/**
 * Internal dependencies
 */
import { isDevMode } from '../../utils/dev-mode';
import { getGBKit } from '../../utils/bridge';

// Only display the notice on initial load
let noticeShown = false;

export function useDevModeNotice() {
	const { createWarningNotice } = useDispatch( noticesStore );

	useEffect( () => {
		const hasDevMode = isDevMode();
		const hasNativeBridge = !! getGBKit().post;

		if ( hasDevMode && ! noticeShown ) {
			noticeShown = true;
			const message = hasNativeBridge
				? __( 'Editor loaded in development mode.', 'gutenberg-kit' )
				: __(
						'Editor loaded in development mode without a native bridge.',
						'gutenberg-kit'
				  );
			createWarningNotice( message, {
				type: 'snackbar',
				isDismissible: true,
			} );
		}
	}, [ createWarningNotice ] );
}
