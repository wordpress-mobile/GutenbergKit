/**
 * Internal dependencies
 */
import { getGBKit } from './bridge';
import { warn, debug } from './logger';

/**
 * Configure AJAX for use without authentication cookies.
 *
 * GutenbergKit runs in a WebView without WordPress session cookies,
 * so AJAX requests need explicit URL and token-based authentication.
 * Additionally, WordPress core media globals (`wp.media.ajax`,
 * `wp.media.post`) are normally set by wp-includes/js/media-models.js,
 * which GutenbergKit doesn't load — so we alias them here.
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
	configureMediaAjax();
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

	if ( typeof window.wp.ajax.send === 'function' ) {
		const originalSend = window.wp.ajax.send;
		window.wp.ajax.send = function ( action, options = {} ) {
			const originalBeforeSend = options.beforeSend;

			options.beforeSend = function ( xhr ) {
				xhr.setRequestHeader( 'Authorization', authHeader );

				if ( typeof originalBeforeSend === 'function' ) {
					originalBeforeSend( xhr );
				}
			};

			return originalSend.call( this, action, options );
		};
	}

	if ( typeof window.wp.ajax.post === 'function' ) {
		const originalPost = window.wp.ajax.post;
		window.wp.ajax.post = function ( action, options = {} ) {
			const originalBeforeSend = options.beforeSend;

			options.beforeSend = function ( xhr ) {
				xhr.setRequestHeader( 'Authorization', authHeader );

				if ( typeof originalBeforeSend === 'function' ) {
					originalBeforeSend( xhr );
				}
			};

			return originalPost.call( this, action, options );
		};
	}

	debug( 'AJAX auth configured' );
}

/**
 * Alias `wp.media.ajax` and `wp.media.post` to the (now-authenticated)
 * `wp.ajax.send` and `wp.ajax.post`. WordPress core normally sets these
 * in `wp-includes/js/media-models.js`, which GutenbergKit doesn't load.
 *
 * @see https://github.com/WordPress/wordpress-develop/blob/117af7e/src/js/_enqueues/wp/media/models.js#L134
 */
function configureMediaAjax() {
	window.wp.media = window.wp.media || {};
	window.wp.media.ajax = window.wp.ajax.send;
	window.wp.media.post = window.wp.ajax.post;
}
