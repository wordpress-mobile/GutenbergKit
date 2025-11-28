/**
 * Internal dependencies
 */
import { awaitGBKitGlobal, editorLoaded, getGBKit } from './bridge';
import { configureLocale } from './localization';
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
 * Adds platform-specific CSS classes to document.body based on the provided
 * global-like object.
 *
 * @param {Object} [global] - `window` or a mocked environment
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

/**
 * Initialize WordPress global modules. Lazy-loaded to ensure the locale is
 * configured before importing these modules and referencing the corresponding
 * `window.wp` globals.
 *
 * @return {Promise} Promise that resolves when WordPress globals are initialized
 */
async function loadWordPressGlobals() {
	const { initializeWordPressGlobals } = await import(
		'./wordpress-globals'
	);
	initializeWordPressGlobals();
}

/**
 * Configure `api-fetch` middleware and settings. Lazy-loaded to ensure
 * WordPress globals are available before importing `api-fetch` and
 * referencing `window.wp.apiFetch`.
 */
async function initializeApiFetchWrapper() {
	const { initializeApiFetch: _initializeApiFetch } = await import(
		'./api-fetch'
	);
	_initializeApiFetch();
}

/**
 * @typedef {Object} PluginLoadResult
 *
 * @property {string[] | undefined} [allowedBlockTypes] Array of allowed block types provided by the API.
 * @property {boolean}              [pluginLoadFailed]  Indicates if plugin loading failed.
 */

/**
 * Load plugins if enabled in GBKit settings.
 *
 * @return {Promise<PluginLoadResult>} Promise resolving to plugin load results
 */
async function loadPluginsIfEnabled() {
	const { plugins } = getGBKit();

	if ( plugins ) {
		try {
			const { allowedBlockTypes } = await loadEditorAssets();
			return { allowedBlockTypes, pluginLoadFailed: false };
		} catch {
			return { pluginLoadFailed: true };
		}
	}

	return { pluginLoadFailed: false };
}

/**
 * Initialize the editor module. Lazy-loaded to ensure WordPress globals are
 * before importing the editor module and referencing `window.wp` globals.
 *
 * @param {Object} pluginLoadResult - Results from plugin loading
 * @return {Promise} Promise that resolves when the editor is initialized
 */
async function initializeEditor( pluginLoadResult = {} ) {
	const { initializeEditor: _initializeEditor } = await import( './editor' );
	_initializeEditor( {
		allowedBlockTypes: pluginLoadResult.allowedBlockTypes,
		pluginLoadFailed: pluginLoadResult.pluginLoadFailed,
	} );
}

/**
 * Log and display an editor load error message.
 *
 * @param {Error} err - The error that occurred
 */
function handleError( err ) {
	error( 'Error initializing editor', err );
	const errorDetails = EditorLoadError( { error: err } );
	document.body.innerHTML = errorDetails;
	editorLoaded();
}
