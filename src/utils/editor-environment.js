/**
 * Internal dependencies
 */
import { awaitGBKitGlobal, editorLoaded, getGBKit } from './bridge';
import { loadEditorAssets } from './editor-loader';
import { initializeVideoPressAjaxBridge } from './videopress-bridge';
import EditorLoadError from '../components/editor-load-error';
import { error } from './logger';
import { setUpGlobalErrorHandlers } from './global-error-handler';
import './editor-styles';

/**
 * Initialize the bundled editor by loading assets and configuring modules
 * in the correct sequence.
 *
 * @return {Promise} Promise that resolves when initialization is complete
 */
export async function setUpEditorEnvironment() {
	setUpGlobalErrorHandlers();
	setBodyClasses( window );

	try {
		await awaitGBKitGlobal();
		await configureLocale();
		await loadWordPressGlobals();
		await initializeApiFetchWrapper();
		initializeVideoPressAjaxBridge();
		const pluginLoadResult = await loadPluginsIfEnabled();
		await initializeEditor( pluginLoadResult );
	} catch ( err ) {
		handleError( err );
	}
}

/**
 * Adds platform-specific CSS classes to document.body based on the provided global-like object.
 *
 * @param {Object} [global] - `window` or a mocked environment, used to detect platform features.
 * @return {void}
 */
function setBodyClasses( global ) {
	if ( typeof global === 'undefined' ) {
		return;
	}
	const { document: { body } = {} } = global;

	// Detect platform and add class to body for platform-specific styling
	if ( global.webkit ) {
		body.classList.add( 'is-ios' );
	} else if ( global.editorDelegate ) {
		body.classList.add( 'is-android' );
	}
}

async function configureLocale() {
	const { configureLocale: _configureLocale } = await import(
		'./localization'
	);
	return _configureLocale();
}

async function loadWordPressGlobals() {
	// Load remaining WordPress globals after locale is configured.
	await import( './wordpress-globals' );
}

async function initializeApiFetchWrapper() {
	// Load api-fetch now that WordPress globals are available.
	const { initializeApiFetch: _initializeApiFetch } = await import(
		'./api-fetch'
	);
	_initializeApiFetch();
}

async function loadPluginsIfEnabled() {
	const { plugins } = getGBKit();

	if ( plugins ) {
		try {
			const { allowedBlockTypes } = await loadEditorAssets();
			return { allowedBlockTypes };
		} catch {
			return { pluginLoadFailed: true };
		}
	}

	return {};
}

async function initializeEditor( pluginLoadResult = {} ) {
	const { initializeEditor: _initializeEditor } = await import( './editor' );
	_initializeEditor( {
		allowedBlockTypes: pluginLoadResult?.allowedBlockTypes,
		pluginLoadFailed: pluginLoadResult?.pluginLoadFailed,
	} );
}

function handleError( err ) {
	error( 'Error initializing editor', err );
	const errorDetails = EditorLoadError( { error: err } );
	document.body.innerHTML = errorDetails;
	editorLoaded();
}
