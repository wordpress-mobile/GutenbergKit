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
// list of supported locales here is always in sync with what we actually ship.
const TRANSLATION_MODULES = import.meta.glob( '../translations/*.json' );
const SUPPORTED_LOCALES = new Set(
	Object.keys( TRANSLATION_MODULES ).map( ( p ) =>
		p.replace( /^\.\.\/translations\//, '' ).replace( /\.json$/, '' )
	)
);

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
 * Resolves an arbitrary locale tag against the bundles we actually ship.
 *
 * Tries the full tag, then the language-only tag, then falls back to
 * `DEFAULT_LOCALE`. Inputs are normalised to lowercase with `_` replaced by
 * `-` so that platform-native identifiers (e.g. `pt_BR`, `en_GB`) match the
 * `pt-br` / `en-gb` filenames we ship.
 *
 * @param {string|null|undefined}        input       The locale tag from the consumer.
 * @param {Set<string>|Iterable<string>} [supported] Override the supported set.
 *                                                   Defaults to the bundles
 *                                                   shipped in `src/translations/`.
 *
 * @return {string} A shipped locale tag, or `DEFAULT_LOCALE`.
 */
export function resolveLocale( input, supported = SUPPORTED_LOCALES ) {
	if ( ! input ) {
		return DEFAULT_LOCALE;
	}

	const set = supported instanceof Set ? supported : new Set( supported );
	const normalized = String( input ).toLowerCase().replace( /_/g, '-' );

	if ( set.has( normalized ) ) {
		return normalized;
	}

	const language = normalized.split( '-' )[ 0 ];
	if ( language && set.has( language ) ) {
		return language;
	}

	return DEFAULT_LOCALE;
}

/**
 * Loads translations for the specified locale from the bundled files.
 *
 * @param {string} locale The locale to load translations for.
 *
 * @return {Promise<void>} A promise that resolves when translations are loaded.
 */
async function loadTranslations( locale ) {
	const resolved = resolveLocale( locale );

	if ( resolved !== locale ) {
		debug(
			`Resolved locale "${ locale }" to "${ resolved }" against bundled translations.`
		);
	}

	if ( resolved === DEFAULT_LOCALE ) {
		return;
	}

	const loader = TRANSLATION_MODULES[ `../translations/${ resolved }.json` ];
	if ( ! loader ) {
		// `resolveLocale` already gates on `SUPPORTED_LOCALES`, so this
		// branch only fires if the manifest and the bundle have drifted.
		warn(
			`Translations unavailable for locale "${ resolved }". Falling back to English.`
		);
		return;
	}

	try {
		debug( 'Loading translations for', resolved );
		const { default: translations } = await loader();
		setLocaleData( translations );
	} catch ( err ) {
		warn(
			`Translations unavailable for locale "${ resolved }". Falling back to English.`
		);
		debug( 'Translation loading error details:', err );
	}
}
