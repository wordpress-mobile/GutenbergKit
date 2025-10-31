/**
 * WordPress dependencies
 */
import { createRoot, StrictMode } from '@wordpress/element';

/**
 * Internal dependencies
 */
import { initializeApiFetch } from './api-fetch';
import { awaitGBKitGlobal, editorLoaded, getGBKit } from './bridge';
import { loadEditorAssets } from './editor-loader';
import EditorLoadError from '../components/editor-load-error';
import { error } from './logger';
import './editor-styles.js';
import { unregisterDisallowedBlocks } from './blocks';

/**
 * Initialize the bundled editor by loading assets and configuring modules
 * in the correct sequence.
 *
 * @return {Promise} Promise that resolves when initialization is complete
 */
export function initializeBundledEditor() {
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
		.then( configureLocale )
		.then( loadRemainingGlobals )
		.then( initializeApiFetchWrapper )
		.then( importEditor )
		.then( initializeEditor )
		.then( loadPluginsIfEnabled )
		.catch( handleError );
}

function configureLocale() {
	return import( './localization' ).then(
		( { configureLocale: _configureLocale } ) => _configureLocale()
	);
}

function loadRemainingGlobals() {
	// Load remaining WordPress globals after i18n is configured.
	// wordpress-i18n.js is already loaded in index.html, so we just need
	// to load the remaining modules.
	return import( './wordpress-globals' );
}

function initializeApiFetchWrapper() {
	initializeApiFetch();
}

function importEditor() {
	return import( './editor' );
}

function initializeEditor( editorModule ) {
	const { initializeEditor: _initializeEditor } = editorModule;
	_initializeEditor();
}

function loadPluginsIfEnabled() {
	const { plugins } = getGBKit();

	if ( plugins ) {
		return loadEditorAssets().then( ( { allowedBlockTypes } ) =>
			unregisterDisallowedBlocks( allowedBlockTypes )
		);
	}

	return Promise.resolve();
}

function handleError( err ) {
	error( 'Error initializing editor', err );
	const root = document.getElementById( 'root' );
	createRoot( root ).render(
		<StrictMode>
			<EditorLoadError error={ err } />
		</StrictMode>
	);
	editorLoaded();
}
