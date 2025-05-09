/**
 * WordPress dependencies
 */
import apiFetch from '@wordpress/api-fetch';
// Default styles that are needed for the editor.
import '@wordpress/components/build-style/style.css';
import '@wordpress/block-editor/build-style/style.css';
// Default styles that are needed for the core blocks.
import '@wordpress/block-library/build-style/style.css';
import '@wordpress/block-library/build-style/editor.css';
import '@wordpress/block-library/build-style/theme.css';
import '@wordpress/format-library/build-style/style.css';
import '@wordpress/block-editor/build-style/content.css';
import '@wordpress/editor/build-style/style.css';

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

	// Ensure the correct translation strings are used by postponing the import
	// of the remaining `@wordpress` packages until after the locale is set.
	const { allowedBlockTypes } = await loadEditorAssets( {
		disallowedPackages: I18N_PACKAGES,
	} );
	const { initializeEditor } = await import( './utils/editor' );
	initializeEditor( { allowedBlockTypes } );
} catch ( err ) {
	error( 'Error initializing editor', err );
	// Fallback to the local editor and display a notice. Because the remote
	// editor loading failed, it is more practical to rely upon the local
	// editor's scripts and styles for displaying the notice.
	window.location.href = 'index.html?error=gbkit_global_unavailable';
}
