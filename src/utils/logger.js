/**
 * Internal dependencies
 */
import { Platform } from './platform';

// Log levels in order of verbosity
const LOG_LEVELS = {
	ERROR: 'error',
	WARN: 'warn',
	INFO: 'info',
	DEBUG: 'debug',
};

// Numeric values for log level comparison
const LOG_LEVEL_VALUES = {
	error: 0,
	warn: 1,
	info: 2,
	debug: 3,
};

// Default log level
let currentLogLevel = LOG_LEVELS.INFO;

// Check for log level from environment variable (Node.js)
if ( typeof process !== 'undefined' && process?.env?.LOG_LEVEL ) {
	const envLogLevel = process.env.LOG_LEVEL.toLowerCase();
	if ( LOG_LEVEL_VALUES[ envLogLevel ] !== undefined ) {
		currentLogLevel = envLogLevel;
	}
}

/**
 * Set the current log level
 * @param {string} level - The log level to set (error, warn, info, debug)
 */
const setLogLevel = ( level ) => {
	if ( typeof level !== 'string' || ! level ) {
		warn(
			`Invalid log level configuration: ${ level }. Using default level info.`
		);
		return;
	}

	const normalizedLevel = level.toLowerCase();
	if ( LOG_LEVEL_VALUES[ normalizedLevel ] !== undefined ) {
		currentLogLevel = normalizedLevel;
	} else {
		warn(
			`Invalid log level configuration: ${ level }. Using default level info.`
		);
	}
};

/**
 * Check if a message should be logged based on the current log level
 * @param {string} level - The level of the message to check
 *
 * @return {boolean} - Whether the message should be logged
 */
const shouldLog = ( level ) => {
	return LOG_LEVEL_VALUES[ level ] <= LOG_LEVEL_VALUES[ currentLogLevel ];
};

/**
 * Log an error message
 * @param {string} message - The message to log
 * @param {*}      [data]  - Optional data to log
 */
const error = ( message, data ) => {
	if ( shouldLog( LOG_LEVELS.ERROR ) ) {
		// eslint-disable-next-line no-console
		console.error( `[GBK] ${ message }`, data || '' );

		if ( Platform.isIOS ) {
			window.webkit.messageHandlers.editorDelegate.postMessage( {
				message: 'log',
				body: {
					level: LOG_LEVELS.ERROR,
					message,
					data,
				},
			} );
		}
	}
};

/**
 * Log a warning message
 * @param {string} message - The message to log
 * @param {*}      [data]  - Optional data to log
 */
const warn = ( message, data ) => {
	if ( shouldLog( LOG_LEVELS.WARN ) ) {
		// eslint-disable-next-line no-console
		console.warn( `[GBK] ${ message }`, data || '' );

		if ( Platform.isIOS ) {
			window.webkit.messageHandlers.editorDelegate.postMessage( {
				message: 'log',
				body: {
					level: LOG_LEVELS.WARN,
					message,
					data,
				},
			} );
		}
	}
};

/**
 * Log an info message
 * @param {string} message - The message to log
 * @param {*}      [data]  - Optional data to log
 */
const info = ( message, data ) => {
	if ( shouldLog( LOG_LEVELS.INFO ) ) {
		// eslint-disable-next-line no-console
		console.info( `[GBK] ${ message }`, data || '' );

		if ( Platform.isIOS ) {
			window.webkit.messageHandlers.editorDelegate.postMessage( {
				message: 'log',
				body: {
					level: LOG_LEVELS.INFO,
					message,
					data,
				},
			} );
		}
	}
};

/**
 * Log a debug message
 * @param {string} message - The message to log
 * @param {*}      [data]  - Optional data to log
 */
const debug = ( message, data ) => {
	if ( shouldLog( LOG_LEVELS.DEBUG ) ) {
		// eslint-disable-next-line no-console
		console.debug( `[GBK] ${ message }`, data || '' );

		if ( Platform.isIOS ) {
			window.webkit.messageHandlers.editorDelegate.postMessage( {
				message: 'log',
				body: {
					level: LOG_LEVELS.DEBUG,
					message,
					data,
				},
			} );
		}
	}
};

export { setLogLevel, error, warn, info, debug, LOG_LEVELS };
