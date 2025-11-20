/**
 * Internal dependencies
 */
import { awaitGBKitGlobal, editorLoaded, getGBKit } from './bridge';
import { loadEditorAssets } from './editor-loader';
import { initializeVideoPressAjaxBridge } from './videopress-bridge';
import EditorLoadError from '../components/editor-load-error';
import { error } from './logger';
import './editor-styles';

/**
 * Initialize the bundled editor by loading assets and configuring modules
 * in the correct sequence.
 *
 * @return {Promise} Promise that resolves when initialization is complete
 */
export function setUpEditorEnvironment() {
	// Detect platform and add class to body for platform-specific styling
	if ( typeof window !== 'undefined' && window.webkit ) {
		document.body.classList.add( 'is-ios' );
	} else if ( typeof window !== 'undefined' && window.editorDelegate ) {
		document.body.classList.add( 'is-android' );
	}

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
		.then( initializeVideoPressAjaxBridge )
		.then( loadPluginsIfEnabled )
		.then( initializeEditor )
		.catch( handleError );
}

function configureLocale() {
	return import( './localization' ).then(
		( { configureLocale: _configureLocale } ) => _configureLocale()
	);
}

function loadRemainingGlobals() {
	// Load remaining WordPress globals after i18n is configured.
	return import( './wordpress-globals' );
}

function initializeApiFetchWrapper() {
	// Load api-fetch now that WordPress globals are available.
	return import( './api-fetch' ).then(
		( { initializeApiFetch: _initializeApiFetch } ) => {
			_initializeApiFetch();
		}
	);
}

function loadPluginsIfEnabled() {
	const { plugins } = getGBKit();

	if ( plugins ) {
		return loadEditorAssets()
			.then( ( { allowedBlockTypes } ) => {
				return { allowedBlockTypes };
			} )
			.catch( () => {
				return Promise.resolve( { pluginLoadFailed: true } );
			} );
	}

	return Promise.resolve( {} );
}

function initializeEditor( pluginLoadResult = {} ) {
	return import( './editor' ).then(
		( { initializeEditor: _initializeEditor } ) => {
			_initializeEditor( {
				allowedBlockTypes: pluginLoadResult?.allowedBlockTypes,
				pluginLoadFailed: pluginLoadResult?.pluginLoadFailed,
			} );
		}
	);
}

function handleError( err ) {
	error( 'Error initializing editor', err );
	const errorDetails = EditorLoadError( { error: err } );
	document.body.innerHTML = errorDetails;
	editorLoaded();
}
