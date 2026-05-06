/**
 * WordPress dependencies
 */
import { setLocaleData } from '@wordpress/i18n';

/**
 * Internal dependencies
 */
import { getGBKit } from './bridge';
import { warn, debug } from './logger';

const DEFAULT_LOCALE = 'en';

// Vite statically enumerates the translation bundles at build time, so the
// loader map below is always in sync with what we actually ship.
const TRANSLATION_MODULES = import.meta.glob( '../translations/*.json' );

/**
 * Initializes i18n support for the editor.
 *
 * @return {Promise<void>} A promise that resolves when i18n is initialized.
 */
export async function configureLocale() {
	const { locale = DEFAULT_LOCALE } = getGBKit();
	await loadTranslations( locale );
}

/**
 * Loads translations for the specified locale from the bundled files.
 *
 * The native side is responsible for resolving consumer-supplied locales to a
 * shipped tag before the value reaches JS. Anything that doesn't match a
 * bundled translation falls back to English.
 *
 * @param {string} locale The locale to load translations for.
 *
 * @return {Promise<void>} A promise that resolves when translations are loaded.
 */
async function loadTranslations( locale ) {
	if ( locale === DEFAULT_LOCALE ) {
		return;
	}

	const loader = TRANSLATION_MODULES[ `../translations/${ locale }.json` ];
	if ( ! loader ) {
		warn(
			`Translations unavailable for locale "${ locale }". Falling back to English.`
		);
		return;
	}

	try {
		debug( 'Loading translations for', locale );
		const { default: translations } = await loader();
		setLocaleData( translations );
	} catch ( err ) {
		warn(
			`Translations unavailable for locale "${ locale }". Falling back to English.`
		);
		debug( 'Translation loading error details:', err );
	}
}
