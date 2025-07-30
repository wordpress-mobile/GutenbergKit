/**
 * Internal dependencies
 */
import { getGBKit } from './bridge';
import { warn, info, error } from './logger';

/**
 * VideoPress AJAX to REST API bridge.
 *
 * GutenbergKit lacks authentication cookies required for AJAX requests.
 * This module overrides wp.media.ajax to bridge specific VideoPress AJAX
 * requests to their corresponding REST API endpoints.
 */

/**
 * Initializes the VideoPress AJAX bridge.
 *
 * This function overrides wp.media.ajax to intercept VideoPress-specific
 * AJAX requests and redirect them to the appropriate REST API endpoints.
 *
 * @return {void}
 */
export function initializeVideoPressAjaxBridge() {
	// Ensure necessary globals are available
	if ( ! window.wp || ! window.wp.apiFetch ) {
		warn( 'VideoPress bridge: wp.apiFetch not available' );
		return;
	}

	// Initialize wp.ajax if not already present
	window.wp.ajax = window.wp.ajax || {};
	window.wp.ajax.settings = window.wp.ajax.settings || {};

	// Set up AJAX settings with site URL
	const { siteURL } = getGBKit();
	if ( siteURL ) {
		window.wp.ajax.settings.url = `${ siteURL }/wp-admin/admin-ajax.php`;
	}

	// Store original wp.media.ajax function if it exists
	const originalMediaAjax = window.wp.media?.ajax;

	// Override wp.media.ajax
	window.wp.media = window.wp.media || {};
	window.wp.media.ajax = ( ...args ) => {
		const [ action ] = args;

		// Handle VideoPress upload JWT request
		if ( action === 'videopress-get-upload-jwt' ) {
			return handleVideoPressUploadJWT();
		}

		// Fall back to original function or default behavior
		if ( originalMediaAjax ) {
			return originalMediaAjax( ...args );
		}

		// If no original function exists, return a rejected promise
		const deferred =
			window.jQuery?.Deferred?.() || createFallbackDeferred();
		deferred.reject( new Error( `Unhandled AJAX action: ${ action }` ) );
		return deferred.promise();
	};

	info( 'VideoPress AJAX bridge initialized' );
}

/**
 * Handles the VideoPress upload JWT request by calling the REST API.
 *
 * @return {Promise} jQuery Deferred promise that resolves with the JWT response.
 */
function handleVideoPressUploadJWT() {
	const deferred = window.jQuery?.Deferred?.() || createFallbackDeferred();

	window.wp
		.apiFetch( {
			path: '/wpcom/v2/videopress/upload-jwt',
			method: 'POST',
		} )
		.then( ( response ) => {
			if ( response.error ) {
				deferred.reject( response.error );
			} else {
				// Transform the response to match expected AJAX format
				const processedResponse = {
					...response,
					upload_action_url: response.upload_url,
				};
				delete processedResponse.upload_url;

				info(
					'VideoPress JWT obtained successfully',
					processedResponse
				);
				deferred.resolve( processedResponse );
			}
		} )
		.catch( ( err ) => {
			error( 'VideoPress JWT request failed', err );
			deferred.reject( err );
		} );

	return deferred.promise();
}

/**
 * Creates a fallback deferred object if jQuery is not available.
 *
 * @return {Object} Deferred-like object with resolve, reject, and promise methods.
 */
function createFallbackDeferred() {
	let resolveCallback, rejectCallback;
	const promise = new Promise( ( resolve, reject ) => {
		resolveCallback = resolve;
		rejectCallback = reject;
	} );

	return {
		resolve: resolveCallback,
		reject: rejectCallback,
		promise: () => promise,
	};
}
