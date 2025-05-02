/**
 * WordPress dependencies
 */
import apiFetch from '@wordpress/api-fetch';

/**
 * Internal dependencies
 */
import { awaitGBKitGlobal } from './utils/bridge';
import { initializeApiFetch } from './utils/api-fetch';
import { loadEditorAssets } from './utils/remote-editor';
import { error } from './utils/logger';
import './index.scss';

window.wp = window.wp || {};
window.wp.apiFetch = apiFetch;

const I18N_PACKAGES = [ 'i18n', 'hooks' ];

try {
	await awaitGBKitGlobal();
	initializeApiFetch();

	// Ensure the i18n packages are loaded, then set the locale before importing
	// the rest of the packages.
	await loadEditorAssets( { allowedPackages: I18N_PACKAGES } );
	const { configureLocale } = await import( './utils/localization' );
	await configureLocale();

	// Load the rest of the packages, excluding the i18n packages.
	const wpDependencies = await loadEditorAssets( {
		disallowedPackages: I18N_PACKAGES,
		unregisterBlocks: true,
	} );
	const { initializeEditor } = await import( './utils/editor' );
	initializeEditor( wpDependencies );
} catch ( err ) {
	error( 'Error initializing editor', err );
	// Fallback to the local editor and display a notice. Because the remote
	// editor loading failed, it is more practical to rely upon the local
	// editor's scripts and styles for displaying the notice.
	window.location.href = 'index.html?error=gbkit_global_unavailable';
}
