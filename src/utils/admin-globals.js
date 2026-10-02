import { getGBKit, POST_FALLBACKS } from './bridge';
import { getAjaxUrl } from './ajax';

/**
 * Defines the screen globals WP Admin prints before any script runs, so plugin
 * scripts can read them while loading. The `thousandsSeparator` and
 * `decimalPoint` globals are omitted: core takes them from its own
 * translations, and they serve admin list screens the editor lacks.
 *
 * @see https://github.com/WordPress/wordpress-develop/blob/9868757/src/wp-admin/admin-header.php#L125-L141
 *
 * @param {boolean} isRTL Whether the editor renders right-to-left.
 *
 * @return {void}
 */
export function configureAdminGlobals( isRTL ) {
	const { siteURL, post } = getGBKit();
	const postType = post?.type || POST_FALLBACKS.type;

	Object.assign( window, {
		ajaxurl: getAjaxUrl( siteURL ),
		// The block editor's screen ID is its post type.
		pagenow: postType,
		typenow: postType,
		adminpage: post?.id > 0 ? 'post-php' : 'post-new-php',
		isRtl: isRTL ? 1 : 0,
	} );
}
