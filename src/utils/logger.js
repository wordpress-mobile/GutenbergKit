// Log levels in order of verbosity
const LOG_LEVELS = {
	ERROR: 0,
	WARN: 1,
	INFO: 2,
	DEBUG: 3,
};

// Default log level
let currentLogLevel = LOG_LEVELS.INFO;

// Check for log level from environment variable (Node.js)
if ( typeof process !== 'undefined' && process?.env?.LOG_LEVEL ) {
	const envLogLevel = process.env.LOG_LEVEL.toUpperCase();
	if ( LOG_LEVELS[ envLogLevel ] !== undefined ) {
		currentLogLevel = LOG_LEVELS[ envLogLevel ];
	}
}

// Check for log level from URL parameter (browser) - takes precedence
const urlLogLevel = getLogLevelFromURL();
if ( urlLogLevel ) {
	const upperCaseLevel = urlLogLevel.toUpperCase();
	if ( LOG_LEVELS[ upperCaseLevel ] !== undefined ) {
		currentLogLevel = LOG_LEVELS[ upperCaseLevel ];
	}
}

/**
 * Get log level from URL parameters (for browser environments)
 *
 * @return {string|null} The log level from URL parameter or null if not found
 */
function getLogLevelFromURL() {
	if ( typeof window !== 'undefined' && window.location ) {
		const urlParams = new URLSearchParams( window.location.search );
		return urlParams.get( 'log_level' );
	}
	return null;
}

/**
 * Set the current log level
 * @param {string} level - The log level to set (ERROR, WARN, INFO, DEBUG)
 */
const setLogLevel = ( level ) => {
	if ( LOG_LEVELS[ level ] !== undefined ) {
		currentLogLevel = LOG_LEVELS[ level ];
	} else {
		// eslint-disable-next-line no-console
		console.warn(
			`Invalid log level: ${ level }. Using default level INFO.`
		);
	}
};

/**
 * Check if a message should be logged based on the current log level
 * @param {number} level - The level of the message to check
 *
 * @return {boolean} - Whether the message should be logged
 */
const shouldLog = ( level ) => {
	return level <= currentLogLevel;
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

		if ( typeof window !== 'undefined' && window.webkit ) {
			window.webkit.messageHandlers.editorDelegate.postMessage( {
				message: 'log',
				body: {
					level: 'error',
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

		if ( typeof window !== 'undefined' && window.webkit ) {
			window.webkit.messageHandlers.editorDelegate.postMessage( {
				message: 'log',
				body: {
					level: 'warn',
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

		if ( typeof window !== 'undefined' && window.webkit ) {
			window.webkit.messageHandlers.editorDelegate.postMessage( {
				message: 'log',
				body: {
					level: 'warn',
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

		if ( typeof window !== 'undefined' && window.webkit ) {
			window.webkit.messageHandlers.editorDelegate.postMessage( {
				message: 'log',
				body: {
					level: 'debug',
					message,
					data,
				},
			} );
		}
	}
};

export { setLogLevel, error, warn, info, debug, LOG_LEVELS };
