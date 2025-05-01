// Log levels in order of verbosity
const LOG_LEVELS = {
	ERROR: 0,
	WARN: 1,
	INFO: 2,
	DEBUG: 3,
	VERBOSE: 4,
};

// Default log level
let currentLogLevel = process.env.LOG_LEVEL || LOG_LEVELS.INFO;

/**
 * Set the current log level
 * @param {string} level - The log level to set (ERROR, WARN, INFO, DEBUG, VERBOSE)
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
		console.error( `[ERROR] ${ message }`, data || '' );
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
		console.warn( `[WARN] ${ message }`, data || '' );
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
		console.info( `[INFO] ${ message }`, data || '' );
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
		console.debug( `[DEBUG] ${ message }`, data || '' );
	}
};

/**
 * Log a verbose message
 * @param {string} message - The message to log
 * @param {*}      [data]  - Optional data to log
 */
const verbose = ( message, data ) => {
	if ( shouldLog( LOG_LEVELS.VERBOSE ) ) {
		// eslint-disable-next-line no-console
		console.log( `[VERBOSE] ${ message }`, data || '' );
	}
};

export { setLogLevel, error, warn, info, debug, verbose, LOG_LEVELS };
