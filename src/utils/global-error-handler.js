/**
 * Internal dependencies
 */
import { logException } from './bridge';

/**
 * Sets up global error handlers to catch and report unhandled errors
 * and promise rejections.
 */
export function setupGlobalErrorHandlers() {
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
