/**
 * External dependencies
 */
import fs from 'fs';
import path from 'path';
import fetch from 'node-fetch';

const TRANSLATIONS_DIR = path.join( process.cwd(), 'src/translations/data' );
const SUPPORTED_LOCALES = [
	'en',
	'es',
	'fr',
	'de',
	'it',
	'pt',
	'ru',
	'ja',
	'zh',
	'ko',
	'nl',
	'sv',
	'da',
	'fi',
	'no',
	'pl',
	'cs',
	'hu',
	'ro',
	'tr',
	'bg',
	'el',
	'sk',
	'sl',
	'hr',
	'sr',
	'uk',
	'ar',
	'he',
	'fa',
	'hi',
	'bn',
	'id',
	'ms',
	'th',
	'vi',
	'tl',
	'af',
	'sw',
	'zu',
];

/**
 * Downloads translations for a specific locale from translate.wordpress.org.
 *
 * @param {string} locale The locale to download translations for.
 * @return {Promise<void>} A promise that resolves when translations are downloaded.
 */
async function downloadTranslations( locale ) {
	const url = `https://translate.wordpress.org/projects/wp-plugins/gutenberg/dev/${ locale }/default/export-translations/?format=json`;
	const response = await fetch( url );

	if ( ! response.ok ) {
		throw new Error( `Failed to download translations for ${ locale }` );
	}

	const translations = await response.json();
	const outputPath = path.join( TRANSLATIONS_DIR, `${ locale }.json` );

	// Ensure the translations directory exists
	if ( ! fs.existsSync( TRANSLATIONS_DIR ) ) {
		fs.mkdirSync( TRANSLATIONS_DIR, { recursive: true } );
	}

	// Write translations to file
	fs.writeFileSync( outputPath, JSON.stringify( translations, null, 2 ) );
}

/**
 * Downloads translations for all supported locales.
 */
async function downloadAllTranslations() {
	logInfo( 'Downloading translations...' );

	for ( const locale of SUPPORTED_LOCALES ) {
		try {
			logInfo( `Downloading translations for ${ locale }...` );
			await downloadTranslations( locale );
			logInfo( `✓ Downloaded translations for ${ locale }` );
		} catch ( error ) {
			logError(
				`✗ Failed to download translations for ${ locale }:`,
				error
			);
		}
	}

	logInfo( 'Translation download complete!' );
}

downloadAllTranslations().catch( ( error ) => {
	logError( 'Failed to download translations:', error );
	process.exit( 1 );
} );

function logInfo( message ) {
	// eslint-disable-next-line no-console
	console.log( message );
}

function logError( message ) {
	// eslint-disable-next-line no-console
	console.error( message );
}
