/**
 * WordPress dependencies
 */
import { setLocaleData } from '@wordpress/i18n';

/**
 * Internal dependencies
 */
import { getGBKit } from './bridge';
import { error } from './logger';
/**
 * Initializes i18n support for the editor.
 *
 * @return {Promise<void>} A promise that resolves when i18n is initialized.
 */
export async function configureLocale() {
	const { locale = 'en' } = getGBKit();
	await loadTranslations( locale );
}

/**
 * Loads translations for the specified locale from the downloaded files.
 *
 * @param {string} locale The locale to load translations for.
 * @return {Promise<void>} A promise that resolves when translations are loaded.
 */
export async function loadTranslations( locale ) {
	try {
		const { default: translations } = await import(
			`../translations/data/${ locale }.json`
		);
		setLocaleData( translations );
	} catch ( err ) {
		// Continue with default locale
		error( 'Error loading translations', err );
	}
}
