/**
 * External dependencies
 */
import fs from 'fs';
import path from 'path';
import fetch from 'node-fetch';

/**
 * Internal dependencies
 */
import { info, error } from '../src/utils/logger';

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
	info( 'Downloading translations...' );

	for ( const locale of SUPPORTED_LOCALES ) {
		try {
			info( `Downloading translations for ${ locale }...` );
			await downloadTranslations( locale );
			info( `✓ Downloaded translations for ${ locale }` );
		} catch ( err ) {
			error( `✗ Failed to download translations for ${ locale }:`, err );
		}
	}

	info( 'Translation download complete!' );
}

downloadAllTranslations().catch( ( err ) => {
	error( 'Failed to download translations:', err );
	process.exit( 1 );
} );
