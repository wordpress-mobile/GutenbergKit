/**
 * WordPress dependencies
 */
import { useEffect, useRef } from '@wordpress/element';
import { useDispatch } from '@wordpress/data';
import { store as noticesStore } from '@wordpress/notices';
import { __ } from '@wordpress/i18n';

/**
 * Internal dependencies
 */
import { isDevMode } from '../../utils/dev-mode';
import { getGBKit } from '../../utils/bridge';

export function useDevModeNotice() {
	const noticeShownRef = useRef( false );
	const { createWarningNotice } = useDispatch( noticesStore );

	useEffect( () => {
		const hasDevMode = isDevMode();
		const hasNativeBridge = !! getGBKit().post;

		if ( hasDevMode && ! noticeShownRef.current ) {
			noticeShownRef.current = true;
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
