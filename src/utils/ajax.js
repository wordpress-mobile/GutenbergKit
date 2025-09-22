/**
 * Internal dependencies
 */
import { getGBKit } from './bridge';
import { warn, debug } from './logger';

/**
 * GutenbergKit lacks authentication cookies required for AJAX requests.
 * This configures a root URL and authentication header for AJAX requests.
 *
 * @return {void}
 */
export function configureAjax() {
	window.wp = window.wp || {};
	window.wp.ajax = window.wp.ajax || {};
	window.wp.ajax.settings = window.wp.ajax.settings || {};

	const { siteURL, authHeader } = getGBKit();
	configureAjaxUrl( siteURL );
	configureAjaxAuth( authHeader );
}

function configureAjaxUrl( siteURL ) {
	if ( ! siteURL ) {
		warn( 'Unable to configure AJAX URL without siteURL' );
		return;
	}

	// Global used within WordPress admin pages
	window.ajaxurl = `${ siteURL }/wp-admin/admin-ajax.php`;
	// Global used by WordPress' JavaScript API
	window.wp.ajax.settings.url = `${ siteURL }/wp-admin/admin-ajax.php`;

	debug( 'AJAX URL configured' );
}

function configureAjaxAuth( authHeader ) {
	if ( ! authHeader ) {
		warn( 'Unable to configure AJAX auth without authHeader' );
		return;
	}

	window.jQuery?.ajaxSetup( {
		headers: {
			Authorization: authHeader,
		},
	} );

	const originalSend = window.wp.ajax.send;
	window.wp.ajax.send = function ( options ) {
		const originalBeforeSend = options.beforeSend;

		options.beforeSend = function ( xhr ) {
			xhr.setRequestHeader( 'Authorization', authHeader );

			if ( typeof originalBeforeSend === 'function' ) {
				originalBeforeSend( xhr );
			}
		};

		return originalSend.call( this, options );
	};

	const originalPost = window.wp.ajax.post;
	window.wp.ajax.post = function ( options ) {
		const originalBeforeSend = options.beforeSend;

		options.beforeSend = function ( xhr ) {
			xhr.setRequestHeader( 'Authorization', authHeader );

			if ( typeof originalBeforeSend === 'function' ) {
				originalBeforeSend( xhr );
			}
		};

		return originalPost.call( this, options );
	};

	debug( 'AJAX auth configured' );
}
