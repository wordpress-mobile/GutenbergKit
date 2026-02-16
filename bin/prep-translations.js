/**
 * External dependencies
 */
import fs from 'fs';
import path from 'path';
import fetch from 'node-fetch';

/**
 * Internal dependencies
 */
import { info, error, debug } from '../src/utils/logger.js';

const TRANSLATIONS_DIR = path.join( process.cwd(), 'src/translations' );
const SUPPORTED_LOCALES = [
	'ar', // Arabic
	'bg', // Bulgarian
	'bo', // Tibetan
	'ca', // Catalan
	'cs', // Czech
	'cy', // Welsh
	'da', // Danish
	'de', // German
	'en-au', // English (Australia)
	'en-ca', // English (Canada)
	'en-gb', // English (UK)
	'en-nz', // English (New Zealand)
	'en-za', // English (South Africa)
	'el', // Greek
	'es', // Spanish
	'es-ar', // Spanish (Argentina)
	'es-cl', // Spanish (Chile)
	'es-cr', // Spanish (Costa Rica)
	'fa', // Persian
	'fr', // French
	'gl', // Galician
	'he', // Hebrew
	'hr', // Croatian
	'hu', // Hungarian
	'id', // Indonesian
	'is', // Icelandic
	'it', // Italian
	'ja', // Japanese
	'ka', // Georgian
	'ko', // Korean
	'nb', // Norwegian (Bokmål)
	'nl', // Dutch
	'nl-be', // Dutch (Belgium)
	'pl', // Polish
	'pt', // Portuguese
	'pt-br', // Portuguese (Brazil)
	'ro', // Romainian
	'ru', // Russian
	'sk', // Slovak
	'sq', // Albanian
	'sr', // Serbian
	'sv', // Swedish
	'th', // Thai
	'tr', // Turkish
	'uk', // Ukrainian
	'ur', // Urdu
	'vi', // Vietnamese
	'zh-cn', // Chinese (China)
	'zh-tw', // Chinese (Taiwan)
];

const CONCURRENCY_LIMIT = parseInt( process.env.L10N_BATCH_SIZE, 10 ) || 5;
const INTER_BATCH_DELAY_MS =
	parseInt( process.env.L10N_BATCH_DELAY_MS, 10 ) || 2000;
const MAX_RETRY_ATTEMPTS = parseInt( process.env.L10N_MAX_RETRIES, 10 ) || 5;
const MAX_429_BACKOFF_MS =
	parseInt( process.env.L10N_MAX_BACKOFF_MS, 10 ) || 60000;

/**
 * Prepare translations for all supported locales.
 *
 * @param {boolean} force Whether to force download even if cache exists.
 *
 * @return {Promise<void>} A promise that resolves when translations are prepared.
 */
async function prepareTranslations( force = false ) {
	if ( force ) {
		info( 'Ignoring cache, downloading translations...' );
	} else {
		info( 'Verifying translations...' );
	}

	info(
		`Translation config: batch=${ CONCURRENCY_LIMIT }, delay=${ INTER_BATCH_DELAY_MS }ms, retries=${ MAX_RETRY_ATTEMPTS }, maxBackoff=${ MAX_429_BACKOFF_MS }ms`
	);

	// Process locales in batches with delay between them
	for ( let i = 0; i < SUPPORTED_LOCALES.length; i += CONCURRENCY_LIMIT ) {
		// Delay between batches (not before the first)
		if ( i > 0 ) {
			debug( `Waiting ${ INTER_BATCH_DELAY_MS }ms before next batch...` );
			await new Promise( ( resolve ) =>
				setTimeout( resolve, INTER_BATCH_DELAY_MS )
			);
		}

		const batch = SUPPORTED_LOCALES.slice( i, i + CONCURRENCY_LIMIT );
		await Promise.all(
			batch.map( ( locale ) => downloadWithRetry( locale, force ) )
		);
	}

	info( '✓ Translations ready!' );
}

/**
 * Custom error for HTTP 429 responses, carrying the parsed Retry-After value.
 */
class RateLimitError extends Error {
	/**
	 * @param {string}      message    Error message.
	 * @param {number|null} retryAfter Parsed Retry-After value in seconds, or null.
	 */
	constructor( message, retryAfter = null ) {
		super( message );
		this.name = 'RateLimitError';
		this.retryAfter = retryAfter;
	}
}

/**
 * Parses the Retry-After header value.
 *
 * Supports both delta-seconds ("120") and HTTP-date formats.
 *
 * @param {string|null} headerValue The Retry-After header value.
 *
 * @return {number|null} The delay in seconds, or null if missing/unparseable.
 */
function parseRetryAfter( headerValue ) {
	if ( ! headerValue ) {
		return null;
	}

	// Try delta-seconds first (e.g., "120")
	const seconds = Number( headerValue );
	if ( Number.isFinite( seconds ) && seconds >= 0 ) {
		return seconds;
	}

	// Try HTTP-date format (e.g., "Wed, 21 Oct 2015 07:28:00 GMT")
	const date = new Date( headerValue );
	if ( ! isNaN( date.getTime() ) ) {
		const delayMs = date.getTime() - Date.now();
		return delayMs > 0 ? Math.ceil( delayMs / 1000 ) : 0;
	}

	return null;
}

/**
 * Downloads translations with retry logic, including 429-aware backoff.
 *
 * @param {string}  locale The locale to download translations for.
 * @param {boolean} force  Whether to force download even if cache exists.
 *
 * @return {Promise<void>} A promise that resolves when translations are downloaded.
 */
async function downloadWithRetry( locale, force = false ) {
	let lastError;

	for ( let attempt = 1; attempt <= MAX_RETRY_ATTEMPTS; attempt++ ) {
		try {
			await downloadTranslations( locale, force );
			return;
		} catch ( err ) {
			lastError = err;

			if ( attempt < MAX_RETRY_ATTEMPTS ) {
				const backoffMs = calculateBackoff( err, attempt );

				if ( backoffMs === null ) {
					error(
						`Giving up on '${ locale }': 429 backoff would exceed ${ MAX_429_BACKOFF_MS }ms`
					);
					break;
				}

				info(
					`Retrying '${ locale }' (attempt ${
						attempt + 1
					}/${ MAX_RETRY_ATTEMPTS }) in ${ Math.round(
						backoffMs / 1000
					) }s...`
				);
				await new Promise( ( resolve ) =>
					setTimeout( resolve, backoffMs )
				);
			}
		}
	}

	error(
		`Failed to download '${ locale }' after ${ MAX_RETRY_ATTEMPTS } attempts`
	);
	throw lastError;
}

/**
 * Calculates the backoff delay for a retry attempt.
 *
 * For 429 errors with Retry-After: uses the server-specified duration + jitter (0-1s).
 * For 429 errors without Retry-After: exponential backoff (5s, 10s, 20s, 40s) + jitter (0-2s).
 * For other errors: linear backoff (1s, 2s, 3s...).
 *
 * @param {Error}  err     The error from the previous attempt.
 * @param {number} attempt The attempt number (1-based) that just failed.
 *
 * @return {number|null} Delay in milliseconds, or null if backoff would exceed the max.
 */
function calculateBackoff( err, attempt ) {
	if ( err instanceof RateLimitError ) {
		let backoffMs;

		if ( err.retryAfter !== null ) {
			// Server told us how long to wait — add small jitter
			backoffMs = err.retryAfter * 1000 + Math.random() * 1000;
		} else {
			// No Retry-After: exponential backoff starting at 5s
			backoffMs =
				5000 * Math.pow( 2, attempt - 1 ) + Math.random() * 2000;
		}

		if ( backoffMs > MAX_429_BACKOFF_MS ) {
			return null;
		}

		return backoffMs;
	}

	// Non-429 errors: linear backoff (1s, 2s, 3s...)
	return attempt * 1000;
}

/**
 * Downloads translations for a specific locale from translate.wordpress.org.
 *
 * @param {string}  locale The locale to download translations for.
 * @param {boolean} force  Whether to force download even if cache exists.
 *
 * @return {Promise<void>} A promise that resolves when translations are downloaded.
 */
async function downloadTranslations( locale, force = false ) {
	if ( ! force && hasValidTranslations( locale ) ) {
		debug( `Skipping download of cached translations for ${ locale }` );
		return;
	}
	debug( `Downloading translations for ${ locale }...` );

	const url = `https://translate.wordpress.org/projects/wp-plugins/gutenberg/dev/${ locale }/default/export-translations/?format=json`;

	try {
		const response = await fetch( url );

		if ( ! response.ok ) {
			if ( response.status === 429 ) {
				const retryAfter = parseRetryAfter(
					response.headers.get( 'retry-after' )
				);
				throw new RateLimitError(
					`HTTP 429 Too Many Requests - ${ url }`,
					retryAfter
				);
			}

			throw new Error(
				`HTTP ${ response.status } ${ response.statusText } - ${ url }`
			);
		}

		let translations;
		try {
			translations = await response.json();
		} catch ( jsonError ) {
			throw new Error(
				`Invalid JSON response from ${ url }: ${ jsonError.message }`
			);
		}

		const outputPath = path.join( TRANSLATIONS_DIR, `${ locale }.json` );

		// Ensure the translations directory exists
		if ( ! fs.existsSync( TRANSLATIONS_DIR ) ) {
			fs.mkdirSync( TRANSLATIONS_DIR, { recursive: true } );
		}

		// Write translations to file
		fs.writeFileSync( outputPath, JSON.stringify( translations, null, 2 ) );
		debug( `✓ Downloaded translations for ${ locale }` );
	} catch ( err ) {
		if ( err instanceof RateLimitError ) {
			throw err;
		}

		// Re-throw with more context
		throw new Error(
			`Failed to download translations for ${ locale }: ${ err.message }`
		);
	}
}

/**
 * Checks if translations exist and are valid for a specific locale.
 *
 * @param {string} locale The locale to check.
 *
 * @return {boolean} Whether valid translations exist.
 */
function hasValidTranslations( locale ) {
	const filePath = path.join( TRANSLATIONS_DIR, `${ locale }.json` );
	if ( ! fs.existsSync( filePath ) ) {
		return false;
	}

	try {
		const content = fs.readFileSync( filePath, 'utf8' );
		const translations = JSON.parse( content );
		return translations && typeof translations === 'object';
	} catch ( err ) {
		return false;
	}
}

/**
 * Main entry point for the script.
 * Parses command line arguments and downloads translations.
 */
const forceDownload =
	process.argv.includes( '--force' ) || process.argv.includes( '-f' );

prepareTranslations( forceDownload ).catch( ( err ) => {
	error( 'Failed to prepare translations:', err );
	process.exit( 1 );
} );
