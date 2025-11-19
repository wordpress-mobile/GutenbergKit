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

	for ( const locale of SUPPORTED_LOCALES ) {
		await downloadWithRetry( locale, force );
	}

	info( '✓ Translations ready!' );
}

/**
 * Downloads translations with retry logic.
 *
 * @param {string}  locale      The locale to download translations for.
 * @param {boolean} force       Whether to force download even if cache exists.
 * @param {number}  maxAttempts Maximum number of attempts (default: 3).
 *
 * @return {Promise<void>} A promise that resolves when translations are downloaded.
 */
async function downloadWithRetry( locale, force = false, maxAttempts = 3 ) {
	let lastError;

	for ( let attempt = 1; attempt <= maxAttempts; attempt++ ) {
		try {
			await downloadTranslations( locale, force );
			return; // Success - exit retry loop
		} catch ( err ) {
			lastError = err;

			if ( attempt < maxAttempts ) {
				// Calculate backoff: 1s for first retry, 2s for second retry
				const backoffMs = attempt * 1000;
				info(
					`Retrying download for '${ locale }' (attempt ${
						attempt + 1
					}/${ maxAttempts }) in ${ backoffMs }ms...`
				);
				await new Promise( ( resolve ) =>
					setTimeout( resolve, backoffMs )
				);
			}
		}
	}

	// All attempts failed
	error( `Failed to download '${ locale }' after ${ maxAttempts } attempts` );
	throw lastError;
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
