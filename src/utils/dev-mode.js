/**
 * Checks if the editor is running in development mode.
 *
 * @return {boolean} True if dev_mode query parameter is present.
 */
export function isDevMode() {
	if ( typeof window === 'undefined' || ! window.location ) {
		return false;
	}

	const urlParams = new URLSearchParams( window.location.search );
	return urlParams.has( 'dev_mode' );
}
