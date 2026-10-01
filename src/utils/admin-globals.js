import { getGBKit, POST_FALLBACKS } from './bridge';
import { getAjaxUrl } from './ajax';
import { DEFAULT_LOCALE } from './localization';

/**
 * Defines the screen globals WP Admin prints before any script runs, so plugin
 * scripts can read them while loading.
 *
 * @see https://github.com/WordPress/wordpress-develop/blob/9868757/src/wp-admin/admin-header.php#L125-L141
 *
 * @param {boolean} isRTL Whether the editor renders right-to-left.
 *
 * @return {void}
 */
export function configureAdminGlobals( isRTL ) {
	const { siteURL, post, locale = DEFAULT_LOCALE } = getGBKit();
	const postType = post?.type || POST_FALLBACKS.type;

	Object.assign( window, {
		ajaxurl: getAjaxUrl( siteURL ),
		// The block editor's screen ID is its post type.
		pagenow: postType,
		typenow: postType,
		adminpage: post?.id > 0 ? 'post-php' : 'post-new-php',
		...getNumberSeparators( locale ),
		isRtl: isRTL ? 1 : 0,
	} );
}

/**
 * Derives the locale's number separators. Core reads them from the site's
 * translations; the browser's locale data agrees for most locales.
 *
 * @param {string} locale The editor locale, e.g. `pt_BR`.
 * @return {{thousandsSeparator: string, decimalPoint: string}} The separators.
 */
function getNumberSeparators( locale ) {
	let parts = [];
	try {
		parts = new Intl.NumberFormat(
			locale.replace( /_/g, '-' )
		).formatToParts( 1234567.8 );
	} catch {
		// Fall through to the `en_US` separators for an unrecognized locale.
	}

	return {
		thousandsSeparator:
			parts.find( ( { type } ) => type === 'group' )?.value ?? ',',
		decimalPoint:
			parts.find( ( { type } ) => type === 'decimal' )?.value ?? '.',
	};
}
