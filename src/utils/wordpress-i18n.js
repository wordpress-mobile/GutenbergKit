/**
 * WordPress dependencies
 */
import * as hooks from '@wordpress/hooks';
import * as i18n from '@wordpress/i18n';

initializeWordPressI18n();

/**
 * Initialize WordPress i18n globals by defining i18n-related modules on the
 * `window.wp` namespace. This must be done before other WordPress modules are
 * loaded, as they depend on i18n being configured.
 *
 * @return {void}
 */
function initializeWordPressI18n() {
	// Initialize the wp namespace if it doesn't exist
	window.wp = window.wp || {};

	// Define i18n-related WordPress modules on window.wp
	window.wp.hooks = hooks;
	window.wp.i18n = i18n;
}
