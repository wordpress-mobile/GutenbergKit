/**
 * Internal dependencies
 */
import {
	awaitGBKitGlobal,
	editorLoaded,
	getGBKit,
	logException,
} from './bridge';
import { configureLocale } from './localization';
import { loadEditorAssets } from './editor-loader';
import { configureAjax } from './ajax';
import { initializeVideoPressAjaxBridge } from './videopress-bridge';
import { initializeFetchInterceptor } from './fetch-interceptor';
import EditorLoadError from '../components/editor-load-error';
import { setLogLevel, error } from './logger';
import { setUpGlobalErrorHandlers } from './global-error-handler';
import { Platform } from './platform';
import { injectEditorStyles } from './editor-styles';

/**
 * Initialize the bundled editor by loading assets and configuring modules
 * in the correct sequence.
 *
 * @return {Promise} Promise that resolves when initialization is complete
 */
export async function setUpEditorEnvironment() {
	try {
		setUpGlobalErrorHandlers();
		setBodyClasses();
		await awaitGBKitGlobal();
		setLogLevelFromGBKit();
		initializeFetchInterceptor();
		const isRTL = await configureLocale();
		injectEditorStyles( isRTL );
		await initializeWordPressGlobals();
		await configureApiFetch();
		const pluginLoadResult = await loadPluginsIfEnabled();
		await initializeEditor( pluginLoadResult );
	} catch ( err ) {
		handleError( err );
	}
}

/**
 * Adds conditional CSS classes to `document.body`.
 *
 * @return {void}
 */
function setBodyClasses() {
	if ( typeof window === 'undefined' ) {
		return;
	}

	const classNames = [];

	if ( Platform.isIOS ) {
		classNames.push( 'is-ios' );
	} else if ( Platform.isAndroid ) {
		classNames.push( 'is-android' );
	}

	window.document.body.classList.add( ...classNames );
}

/**
 * Set the log level based on GBKit configuration.
 *
 * @return {void}
 */
function setLogLevelFromGBKit() {
	const { logLevel } = getGBKit();
	if ( logLevel ) {
		setLogLevel( logLevel );
	}
}

/**
 * Initialize WordPress global modules. Lazy-loaded to ensure the locale is
 * configured before importing these modules and referencing the corresponding
 * `window.wp` globals.
 *
 * @return {Promise} Promise that resolves when WordPress globals are initialized
 */
async function initializeWordPressGlobals() {
	const { initializeWordPressGlobals: _initializeWordPressGlobals } =
		await import( './wordpress-globals' );
	await _initializeWordPressGlobals();
}

/**
 * Configure `api-fetch` middleware and settings. Lazy-loaded to ensure
 * WordPress globals are available before importing `api-fetch` and
 * referencing `window.wp.apiFetch`.
 */
async function configureApiFetch() {
	const { configureApiFetch: _configureApiFetch } = await import(
		'./api-fetch'
	);
	_configureApiFetch();
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
		} catch ( err ) {
			logException( err, {
				isHandled: true,
				handledBy: 'loadPluginsIfEnabled',
			} );
			return { pluginLoadFailed: true };
		}
	}

	return { pluginLoadFailed: false };
}

/**
 * Initialize the editor module. Lazy-loaded to ensure WordPress globals are
 * available before importing the editor module and referencing `window.wp`
 * globals.
 *
 * @param {Object} pluginLoadResult - Results from plugin loading
 * @return {Promise} Promise that resolves when the editor is initialized
 */
async function initializeEditor( pluginLoadResult = {} ) {
	const { initializeEditor: _initializeEditor } = await import( './editor' );
	const { allowedBlockTypes } = pluginLoadResult;

	configureAjax();

	if ( ! allowedBlockTypes?.includes( 'videopress/video' ) ) {
		// The VideoPress block isn't available, so initialize the bridge to handle
		// any `core/video` blocks extended to rely upon VideoPress upload services.
		initializeVideoPressAjaxBridge();
	}

	_initializeEditor( {
		allowedBlockTypes,
		pluginLoadFailed: pluginLoadResult.pluginLoadFailed,
	} );
}

/**
 * Log and display an editor load error message.
 *
 * @param {Error} err - The error that occurred
 */
function handleError( err ) {
	logException( err, {
		isHandled: true,
		handledBy: 'setUpEditorEnvironment',
	} );
	error( 'Error initializing editor', err );
	const errorDetails = EditorLoadError( { error: err } );
	document.body.innerHTML = errorDetails;
	editorLoaded();
}
