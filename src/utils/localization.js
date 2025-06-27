/**
 * Internal dependencies
 */
import { getGBKit } from './bridge';
import { error, debug } from './logger';

/**
 * Initializes i18n support for the editor.
 *
 * @param {Function} setLocaleData The function to set the locale data.
 *
 * @return {Promise<void>} A promise that resolves when i18n is initialized.
 */
export async function configureLocale( setLocaleData ) {
	const { locale = 'en' } = getGBKit();
	await loadTranslations( locale, setLocaleData );
}

/**
 * Loads translations for the specified locale from the downloaded files.
 *
 * @param {string}   locale        The locale to load translations for.
 * @param {Function} setLocaleData The function to set the locale data.
 *
 * @return {Promise<void>} A promise that resolves when translations are loaded.
 */
async function loadTranslations( locale, setLocaleData ) {
	if ( locale === DEFAULT_LOCALE ) {
		return;
	}

	try {
		debug( 'Loading translations for', locale );
		const { default: translations } = await import(
			`../translations/${ locale }.json`
		);
		setLocaleDataCompat( translations, setLocaleData );
	} catch ( err ) {
		// Continue with default locale
		error( 'Error loading translations', err );
	}
}

/**
 * Rudimentary utility bridging the setLocaleData function location between the
 * local and remote editors.
 *
 * @todo Align the architecture of the two editors so that the setLocaleData
 * function is the same in both and remove this function.
 *
 * @param {Object}   translations  The translations to set.
 * @param {Function} setLocaleData The function to set the locale data.
 */
function setLocaleDataCompat( translations, setLocaleData ) {
	if ( window.wp?.i18n?.setLocaleData ) {
		window.wp.i18n.setLocaleData( translations );
	} else {
		setLocaleData( translations );
	}
}

const DEFAULT_LOCALE = 'en';
