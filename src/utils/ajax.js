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

	const { siteURL: rawSiteURL, authHeader } = getGBKit();
	const siteURL = rawSiteURL?.replace( /\/+$/, '' );
	configureAjaxUrl( siteURL );
	configureAjaxAuth( siteURL, authHeader );
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

function configureAjaxAuth( siteURL, authHeader ) {
	if ( ! siteURL ) {
		warn( 'Unable to configure AJAX auth without siteURL' );
		return;
	}

	if ( ! authHeader ) {
		warn( 'Unable to configure AJAX auth without authHeader' );
		return;
	}

	if ( ! window.jQuery?.ajaxPrefilter ) {
		warn( 'Unable to configure AJAX auth: jQuery not available' );
		return;
	}

	let siteOrigin;
	try {
		siteOrigin = new URL( siteURL ).origin;
	} catch {
		warn( 'Unable to configure AJAX auth: invalid siteURL' );
		return;
	}

	window.jQuery.ajaxPrefilter( function ( options ) {
		if ( ! isSameOrigin( options.url, siteOrigin ) ) {
			return;
		}

		const originalBeforeSend = options.beforeSend;
		options.beforeSend = function ( xhr ) {
			xhr.setRequestHeader( 'Authorization', authHeader );
			if ( typeof originalBeforeSend === 'function' ) {
				originalBeforeSend( xhr );
			}
		};
	} );

	debug( 'AJAX auth configured' );
}

/**
 * Check whether a request URL shares the same origin as the site.
 *
 * Uses `URL.origin` so that scheme, host, and port must all match exactly,
 * preventing credential leakage to lookalike domains (e.g.
 * `https://example.com.evil.com`).
 *
 * @param {string} requestUrl The URL of the outgoing request.
 * @param {string} siteOrigin The origin derived from `siteURL`.
 * @return {boolean} Whether the request targets the same origin.
 */
function isSameOrigin( requestUrl, siteOrigin ) {
	try {
		return new URL( requestUrl ).origin === siteOrigin;
	} catch {
		return false;
	}
}

/**
 * Alias `wp.media.ajax` and `wp.media.post` to the (now-authenticated)
 * `wp.ajax.send` and `wp.ajax.post`. WordPress core normally sets these
 * in `wp-includes/js/media-models.js`, which GutenbergKit doesn't load.
 *
 * @see https://github.com/WordPress/wordpress-develop/blob/117af7e/src/js/_enqueues/wp/media/models.js#L134
 */
function configureMediaAjax() {
	if ( ! window.wp.ajax.send || ! window.wp.ajax.post ) {
		warn(
			'Unable to configure media AJAX: wp.ajax.send/post not available'
		);
		return;
	}

	window.wp.media = window.wp.media || {};
	window.wp.media.ajax = window.wp.ajax.send;
	window.wp.media.post = window.wp.ajax.post;
}
