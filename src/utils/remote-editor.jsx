/**
 * WordPress dependencies
 */
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
import { awaitGBKitGlobal } from './bridge';
import { loadEditorAssets } from './editor-loader';
import { initializeVideoPressAjaxBridge } from './videopress-bridge';
import { error, warn } from './logger';
import { isDevMode } from './dev-mode';

const I18N_PACKAGES = [ 'i18n', 'hooks' ];
const API_FETCH_PACKAGES = [ 'api-fetch', 'url' ];

/**
 * Initialize the remote editor by loading assets and configuring modules
 * in the correct sequence.
 *
 * @return {Promise} Promise that resolves when initialization is complete
 */
export function initializeRemoteEditor() {
	// Rely upon promises rather than async/await to avoid timeouts caused by
	// circular dependencies. Addressing the circular dependencies is quite
	// challenging due to Vite's preload helpers and bugs in `manualChunks`
	// configuration.
	//
	// See:
	// - https://github.com/vitejs/vite/issues/18551
	// - https://github.com/vitejs/vite/issues/13952
	// - https://github.com/vitejs/vite/issues/5189#issuecomment-2175410148
	return awaitGBKitGlobal()
		.then( initializeApiAndLoadI18n )
		.then( importL10n )
		.then( configureLocale ) // Configure locale before loading modules with strings
		.then( loadApiFetch )
		.then( initializeApiFetch ) // Configure API fetch before loading remaining modules
		.then( loadRemainingAssets )
		.then( initializeEditor )
		.catch( handleError );
}

function initializeApiAndLoadI18n() {
	return loadEditorAssets( { allowedPackages: I18N_PACKAGES } );
}

function importL10n() {
	return import( './localization' );
}

function configureLocale( localeModule ) {
	const { configureLocale: _configureLocale } = localeModule;
	return _configureLocale();
}

function loadApiFetch() {
	return loadEditorAssets( { allowedPackages: API_FETCH_PACKAGES } );
}

function loadRemainingAssets() {
	return loadEditorAssets( {
		disallowedPackages: [ ...I18N_PACKAGES, ...API_FETCH_PACKAGES ],
	} );
}

function initializeApiFetch( assetsResult ) {
	return import( './api-fetch' ).then(
		( { initializeApiFetch: _initializeApiFetch } ) => {
			_initializeApiFetch();
			return assetsResult;
		}
	);
}

function initializeEditor( assetsResult ) {
	initializeVideoPressAjaxBridge();

	const { allowedBlockTypes } = assetsResult;
	return import( './editor' ).then(
		( { initializeEditor: _initializeEditor } ) => {
			_initializeEditor( { allowedBlockTypes } );
		}
	);
}

function handleError( err ) {
	error( 'Error initializing editor', err );
	if ( isDevMode() ) {
		warn( 'Dev mode disabled automatic redirect to the local editor.' );
	} else {
		// Fallback to the local editor and display a notice. Because the remote
		// editor loading failed, it is more practical to rely upon the local
		// editor's scripts and styles for displaying the notice.
		window.location.href = 'index.html?error=gbkit_global_unavailable';
	}
}
