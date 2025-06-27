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

// Rely upon promises rather than async/await to avoid timeouts caused by
// circular dependencies. Addressing the circular dependencies is quite
// challenging due to Vite's preload helpers and bugs in `manualChunks`
// configuration.
//
// See:
// - https://github.com/vitejs/vite/issues/18551
// - https://github.com/vitejs/vite/issues/13952
// - https://github.com/vitejs/vite/issues/5189#issuecomment-2175410148
awaitGBKitGlobal()
	.then( initializeApiAndLoadI18n )
	.then( importLocalization )
	.then( configureLocalization )
	.then( loadRemainingAssets )
	.then( initializeEditorWithBlocks )
	.catch( handleInitializationError );

function initializeApiAndLoadI18n() {
	initializeApiFetch();

	// Ensure the i18n packages are loaded, then set the locale before importing
	// the rest of the packages.
	return loadEditorAssets( { allowedPackages: I18N_PACKAGES } );
}

function importLocalization() {
	return import( './utils/localization' );
}

function configureLocalization( localizationModule ) {
	const { configureLocale } = localizationModule;
	return configureLocale();
}

function loadRemainingAssets() {
	// Ensure the correct translation strings are used by postponing the import
	// of the remaining `@wordpress` packages until after the locale is set.
	return loadEditorAssets( {
		disallowedPackages: I18N_PACKAGES,
	} );
}

function initializeEditorWithBlocks( assetsResult ) {
	const { allowedBlockTypes } = assetsResult;
	return import( './utils/editor' ).then( ( { initializeEditor } ) => {
		initializeEditor( { allowedBlockTypes } );
	} );
}

function handleInitializationError( err ) {
	error( 'Error initializing editor', err );
	// Fallback to the local editor and display a notice. Because the remote
	// editor loading failed, it is more practical to rely upon the local
	// editor's scripts and styles for displaying the notice.
	window.location.href = 'index.html?error=gbkit_global_unavailable';
}
