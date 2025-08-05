/**
 * WordPress dependencies
 */
import { useEffect } from '@wordpress/element';
import { useDispatch } from '@wordpress/data';
import { store as noticesStore } from '@wordpress/notices';
import { __ } from '@wordpress/i18n';

// Only display the notice on initial load
let noticeShown = false;

export function useDevModeNotice() {
	const { createWarningNotice, removeAllNotices } =
		useDispatch( noticesStore );

	useEffect( () => {
		const url = new URL( window.location.href );
		const hasDevMode = url.searchParams.has( 'dev_mode' );

		if ( hasDevMode && ! noticeShown ) {
			noticeShown = true;
			createWarningNotice(
				__(
					'Editor loaded in development mode without a native bridge.',
					'gutenberg-kit'
				),
				{
					type: 'snackbar',
					isDismissible: true,
				}
			);
		}
	}, [ createWarningNotice, removeAllNotices ] );
}
