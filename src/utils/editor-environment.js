/**
 * Internal dependencies
 */
import {
	awaitGBKitGlobal,
	editorLoaded,
	getGBKit,
	logException,
} from './bridge';
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
		.then( setupGlobalErrorHandlers )
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

/**
 * Determines if an error originated from GutenbergKit code rather than
 * third-party scripts.
 *
 * @param {string|undefined} filename - The filename from the error event
 * @param {Error|undefined}  errorObj - The error object with stack trace
 * @return {boolean} True if the error appears to be from GutenbergKit code
 */
function isGutenbergKitError( filename, errorObj ) {
	// Check the filename first
	if ( filename ) {
		// GutenbergKit errors should have /gutenberg/ in the path or be from
		// the same origin
		if (
			filename.includes( '/gutenberg/' ) ||
			filename.includes( window.location.origin )
		) {
			return true;
		}
		// If filename is from a different origin, it's likely third-party
		if ( filename.startsWith( 'http' ) ) {
			return false;
		}
	}

	// If no filename, check the error stack trace
	if ( errorObj?.stack ) {
		const stack = errorObj.stack;
		// Look for GutenbergKit-related paths in the stack
		if (
			stack.includes( '/gutenberg/' ) ||
			stack.includes( window.location.origin )
		) {
			return true;
		}
	}

	// If we can't determine the origin, report it to be safe
	// Better to have some noise than miss legitimate errors
	return true;
}

/**
 * Sets up global error handlers to catch and report unhandled errors
 * and promise rejections.
 */
function setupGlobalErrorHandlers() {
	// Catch unhandled errors
	window.addEventListener( 'error', ( event ) => {
		// Filter out errors from third-party scripts
		if ( ! isGutenbergKitError( event.filename, event.error ) ) {
			return;
		}

		const errorObj = event.error || new Error( event.message );

		logException( errorObj, {
			context: {
				filename: event.filename,
				lineno: event.lineno,
				colno: event.colno,
			},
			tags: {},
			isHandled: false,
			handledBy: 'window.error',
		} );
	} );

	// Catch unhandled promise rejections
	window.addEventListener( 'unhandledrejection', ( event ) => {
		// Convert rejection reason to Error if it isn't already
		const errorObj =
			event.reason instanceof Error
				? event.reason
				: new Error( String( event.reason ) );

		// Filter out errors from third-party scripts
		if ( ! isGutenbergKitError( undefined, errorObj ) ) {
			return;
		}

		logException( errorObj, {
			context: {},
			tags: {},
			isHandled: false,
			handledBy: 'unhandledrejection',
		} );
	} );
}
