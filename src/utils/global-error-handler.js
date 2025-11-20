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
		if ( isExternalError( event.filename, event.error ) ) {
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

		if ( isExternalError( undefined, errorObj ) ) {
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
 * Determines if an error originated from an external third-party script.
 *
 * Detects external HTTP(S) URLs from different origins (third-party scripts).
 * GutenbergKit errors (same-origin, file://, or unknown sources) return false.
 *
 * @param {string|undefined} filename - The filename from the error event
 * @param {Error|undefined}  errorObj - The error object with stack trace
 * @return {boolean} True if the error is from an external source (should be filtered)
 */
function isExternalError( filename, errorObj ) {
	// Detect external HTTP(S) URLs from different origins (third-party scripts)
	if (
		filename?.startsWith( 'http' ) &&
		! filename.includes( window.location.origin )
	) {
		return true;
	}

	// Check stack trace for external URLs
	if ( errorObj?.stack ) {
		const stackLines = errorObj.stack.split( '\n' );
		for ( const line of stackLines ) {
			// Check if any line in stack contains external HTTP URL
			if (
				line.includes( 'http' ) &&
				! line.includes( window.location.origin )
			) {
				return true;
			}
		}
	}

	return false;
}
